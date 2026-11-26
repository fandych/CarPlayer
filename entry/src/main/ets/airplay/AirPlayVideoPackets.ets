import { splitH264NalUnits as splitNativeH264NalUnits } from '../video/H264NalUnits';

export const AIRPLAY_VIDEO_HEADER_SIZE: number = 128;
export const VIDEO_CONFIG_OPCODE: number = 1;
export const VIDEO_FRAME_OPCODE: number = 0;
export const ENCRYPTED_VIDEO_FLAG: number = 0x04;
export const CHACHA_TAG_SIZE: number = 16;
export const MAX_QUEUED_FRAMES: number = 6;
export const MAX_QUEUED_VIDEO_BYTES: number = 2 * 1024 * 1024;
export const MAX_FRAME_QUEUE_AGE_MS: number = 200;
export const H264_SYNC_FRAME_FLAG: number = 0x02;

export interface EncodedH264Event {
  type: 'diagnostic' | 'codecConfig' | 'frame' | 'streamChanged' | 'error' | 'overflow';
  data?: Uint8Array;
  timestampUs: number;
  flags: number;
  message?: string;
}

export enum AirPlayVideoEncryptionMode {
  CHACHA20_POLY1305 = 0,
  AES_128_CTR = 1
}

export function splitH264NalUnits(data: Uint8Array): Uint8Array[] {
  return splitNativeH264NalUnits(data);
}

export function buildAvcConfigurationRecord(units: Uint8Array[]): Uint8Array {
  const sequenceParameters: Uint8Array[] = [];
  const pictureParameters: Uint8Array[] = [];
  for (const unit of units) {
    const type = unit.length > 0 ? unit[0] & 0x1f : -1;
    if (type === 7) {
      sequenceParameters.push(unit);
    } else if (type === 8) {
      pictureParameters.push(unit);
    }
  }
  const sps = sequenceParameters[0];
  const pps = pictureParameters[0];
  if (!sps || !pps || sps.length < 4 || sps.length > 0xffff || pps.length > 0xffff) {
    throw new Error('H.264 codec configuration is missing a usable SPS or PPS');
  }
  const record = new Uint8Array(11 + sps.length + pps.length);
  let offset = 0;
  record[offset++] = 1;
  record[offset++] = sps[1];
  record[offset++] = sps[2];
  record[offset++] = sps[3];
  record[offset++] = 0xff;
  record[offset++] = 0xe1;
  writeBe16(record, offset, sps.length);
  offset += 2;
  record.set(sps, offset);
  offset += sps.length;
  record[offset++] = 1;
  writeBe16(record, offset, pps.length);
  offset += 2;
  record.set(pps, offset);
  return record;
}

export function patchH264SpsLevel(sps: Uint8Array): Uint8Array {
  if (sps.length < 4 || sps[3] >= 0x28) {
    return sps;
  }
  const patched = sps.slice();
  patched[3] = 0x28;
  return patched;
}

export function packH264Nals(units: Uint8Array[]): Uint8Array {
  let totalLength = 0;
  for (const unit of units) {
    if (unit.length === 0 || unit.length > 0xffffffff) {
      throw new Error('H.264 NAL unit has an invalid length');
    }
    totalLength += 4 + unit.length;
  }
  if (totalLength > 4 * 1024 * 1024) {
    throw new Error('H.264 access unit exceeds the 4 MiB safety limit');
  }
  const packed = new Uint8Array(totalLength);
  let offset = 0;
  for (const unit of units) {
    writeBe32(packed, offset, unit.length);
    offset += 4;
    packed.set(unit, offset);
    offset += unit.length;
  }
  return packed;
}

export function buildAirPlayVideoConfigHeader(bodyLength: number, width: number, height: number): Uint8Array {
  validateVideoShape(width, height);
  const header = buildAirPlayVideoHeader(VIDEO_CONFIG_OPCODE, bodyLength, false);
  writeFloat32Le(header, 16, width);
  writeFloat32Le(header, 20, height);
  return header;
}

export function buildAirPlayVideoFrameHeader(bodyLength: number, nowMillis: number = Date.now()): Uint8Array {
  const header = buildAirPlayVideoHeader(VIDEO_FRAME_OPCODE, bodyLength, true, nowMillis);
  header[6] = ENCRYPTED_VIDEO_FLAG;
  return header;
}

export function buildVideoFrameNonce(counter: bigint): Uint8Array {
  if (counter < BigInt(0) || counter > BigInt('18446744073709551615')) {
    throw new Error('H.264 frame nonce counter is out of range');
  }
  const nonce = new Uint8Array(12);
  for (let index = 0; index < 8; index++) {
    nonce[4 + index] = Number((counter >> BigInt(index * 8)) & BigInt(0xff));
  }
  return nonce;
}

export function containsH264Idr(units: Uint8Array[]): boolean {
  return units.some((unit: Uint8Array): boolean => unit.length > 0 && (unit[0] & 0x1f) === 5);
}

export function sameNalUnit(previous: Uint8Array | undefined, current: Uint8Array): boolean {
  return previous !== undefined && previous.length === current.length &&
    previous.every((value: number, index: number): boolean => value === current[index]);
}

function buildAirPlayVideoHeader(
  opcode: number,
  bodyLength: number,
  includeTimestamp: boolean,
  nowMillis: number = Date.now()
): Uint8Array {
  if (!Number.isInteger(bodyLength) || bodyLength < 0 || bodyLength > 4 * 1024 * 1024) {
    throw new Error(`AirPlay video body length is out of range: ${bodyLength}`);
  }
  const header = new Uint8Array(AIRPLAY_VIDEO_HEADER_SIZE);
  writeLe32(header, 0, bodyLength);
  header[4] = opcode;
  if (includeTimestamp) {
    const seconds = Math.floor(nowMillis / 1000) + 2208988800;
    const fraction = Math.floor(((nowMillis % 1000) * 0x100000000) / 1000);
    const ntp = (BigInt(seconds) << BigInt(32)) | BigInt(fraction);
    for (let index = 0; index < 8; index++) {
      header[8 + index] = Number((ntp >> BigInt(index * 8)) & BigInt(0xff));
    }
  }
  return header;
}

export function validateVideoShape(width: number, height: number): void {
  if (!Number.isInteger(width) || !Number.isInteger(height) ||
    width < 320 || height < 240 || width > 4096 || height > 2160 ||
    (width & 1) !== 0 || (height & 1) !== 0) {
    throw new Error(`Unsupported AirPlay H.264 dimensions ${width}x${height}`);
  }
}

function writeLe32(target: Uint8Array, offset: number, value: number): void {
  target[offset] = value & 0xff;
  target[offset + 1] = (value >>> 8) & 0xff;
  target[offset + 2] = (value >>> 16) & 0xff;
  target[offset + 3] = (value >>> 24) & 0xff;
}

function writeBe16(target: Uint8Array, offset: number, value: number): void {
  target[offset] = (value >>> 8) & 0xff;
  target[offset + 1] = value & 0xff;
}

function writeBe32(target: Uint8Array, offset: number, value: number): void {
  target[offset] = (value >>> 24) & 0xff;
  target[offset + 1] = (value >>> 16) & 0xff;
  target[offset + 2] = (value >>> 8) & 0xff;
  target[offset + 3] = value & 0xff;
}

function writeFloat32Le(target: Uint8Array, offset: number, value: number): void {
  const buffer = new ArrayBuffer(4);
  new DataView(buffer).setFloat32(0, value, true);
  target.set(new Uint8Array(buffer), offset);
}
