import { MediaPacketCipher } from '../crypto/MediaPacketCipher';
import { concatBytes } from '../protocol/Iap2Codec';
import { formatProtocolEvent } from '../session/ProtocolLogger';
import { splitH264NalUnits as splitNativeH264NalUnits } from '../video/NativeH264Data';

export const AIRPLAY_VIDEO_HEADER_SIZE: number = 128;
const VIDEO_CONFIG_OPCODE: number = 1;
const VIDEO_FRAME_OPCODE: number = 0;
const ENCRYPTED_VIDEO_FLAG: number = 0x04;
const CHACHA_TAG_SIZE: number = 16;
const MAX_QUEUED_FRAMES: number = 6;
const MAX_QUEUED_VIDEO_BYTES: number = 2 * 1024 * 1024;
const MAX_FRAME_QUEUE_AGE_MS: number = 200;
const H264_SYNC_FRAME_FLAG: number = 0x02;

export interface EncodedH264Event {
  type: 'diagnostic' | 'codecConfig' | 'frame' | 'streamChanged' | 'error' | 'overflow';
  data?: Uint8Array;
  timestampUs: number;
  flags: number;
  message?: string;
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

export class AirPlayVideoStreamSender {
  private readonly cipher: MediaPacketCipher;
  private readonly width: number;
  private readonly height: number;
  private readonly sendBytes: (data: Uint8Array) => Promise<void>;
  private readonly log: (message: string) => void;
  private readonly requestKeyFrame: () => void;
  private frameCounter: bigint = BigInt(0);
  private configSent: boolean = false;
  private pendingSps?: Uint8Array;
  private pendingPps?: Uint8Array;
  private sendQueue: Promise<void> = Promise.resolve();
  private framesSent: number = 0;
  private queuedFrames: number = 0;
  private queuedBytes: number = 0;
  private failed: boolean = false;
  private frameGeneration: number = 0;
  private awaitingKeyFrame: boolean = false;
  private awaitingConfigKeyFrame: boolean = true;

  constructor(
    streamKey: Uint8Array,
    width: number,
    height: number,
    sendBytes: (data: Uint8Array) => Promise<void>,
    log: (message: string) => void,
    requestKeyFrame: () => void = (): void => {}
  ) {
    validateVideoShape(width, height);
    if (streamKey.length !== 32) {
      throw new Error('AirPlay screen-stream key must be 32 bytes');
    }
    this.cipher = new MediaPacketCipher(streamKey, true, log);
    this.width = width;
    this.height = height;
    this.sendBytes = sendBytes;
    this.log = log;
    this.requestKeyFrame = requestKeyFrame;
  }

  handleEncoderEvent(event: EncodedH264Event): Promise<void> {
    if (this.failed) {
      return Promise.reject(new Error('AirPlay screen stream failed; a new session is required'));
    }
    const isFrame = event.type === 'frame';
    const byteLength = isFrame ? event.data?.length ?? 0 : 0;
    if (isFrame && (this.queuedFrames >= MAX_QUEUED_FRAMES ||
      (this.queuedFrames > 0 && this.queuedBytes + byteLength > MAX_QUEUED_VIDEO_BYTES))) {
      this.beginFrameRecovery('frame/byte budget exceeded');
      return Promise.resolve();
    }
    if (isFrame && this.awaitingKeyFrame) {
      if ((event.flags & H264_SYNC_FRAME_FLAG) === 0 &&
        (!event.data || !containsH264Idr(splitH264NalUnits(event.data)))) {
        return Promise.resolve();
      }
      this.awaitingKeyFrame = false;
      this.log('AirPlay video queue recovered with a key frame');
    }
    const generation = this.frameGeneration;
    const enqueuedAt = Date.now();
    if (isFrame) {
      this.queuedFrames++;
      this.queuedBytes += byteLength;
    }
    const operation = this.sendQueue.then((): Promise<void> => {
      if (this.failed) {
        throw new Error('AirPlay screen stream failed; queued media discarded');
      }
      if (isFrame && generation !== this.frameGeneration) {
        return Promise.resolve();
      }
      if (isFrame && Date.now() - enqueuedAt > MAX_FRAME_QUEUE_AGE_MS) {
        this.beginFrameRecovery('frame queue age exceeded');
        return Promise.resolve();
      }
      return this.processEvent(event);
    }).catch((error: Error): void => {
      this.failed = true;
      throw error;
    });
    this.sendQueue = operation.then(
      (): void => this.finishQueuedEvent(isFrame, byteLength),
      (): void => this.finishQueuedEvent(isFrame, byteLength)
    );
    return operation;
  }

  async flush(): Promise<void> {
    await this.sendQueue;
  }

  private beginFrameRecovery(reason: string): void {
    if (this.awaitingKeyFrame) {
      return;
    }
    this.frameGeneration++;
    this.awaitingKeyFrame = true;
    this.log(`WARN: AirPlay video ${reason}; queuedFrames=${this.queuedFrames}, ` +
      `queuedBytes=${this.queuedBytes}; awaiting a new key frame`);
    this.requestRecoveryKeyFrame();
  }

  private requestRecoveryKeyFrame(): void {
    try {
      this.requestKeyFrame();
    } catch (error) {
      this.log(`WARN: Could not request video recovery key frame: ${error instanceof Error ? error.message : String(error)}`);
    }
  }

  private finishQueuedEvent(isFrame: boolean, byteLength: number): void {
    if (!isFrame) {
      return;
    }
    this.queuedFrames--;
    this.queuedBytes -= byteLength;
    if (this.queuedFrames === 0 && this.awaitingKeyFrame) {
      this.requestRecoveryKeyFrame();
    }
  }

  private async processEvent(event: EncodedH264Event): Promise<void> {
    if (event.type === 'error' || event.type === 'overflow') {
      throw new Error(event.message || `Native H.264 encoder reported ${event.type}`);
    }
    if (event.type === 'streamChanged') {
      this.log('H.264 encoder output format changed; awaiting codec configuration');
      this.configSent = false;
      this.pendingSps = undefined;
      this.pendingPps = undefined;
      this.awaitingConfigKeyFrame = true;
      this.requestRecoveryKeyFrame();
      return;
    }
    const data = event.data;
    if (!data || data.length === 0) {
      return;
    }
    const units = splitH264NalUnits(data);
    if (event.type === 'codecConfig') {
      await this.collectCodecConfiguration(units);
      if (!units.some((unit: Uint8Array): boolean =>
        unit.length > 0 && (unit[0] & 0x1f) >= 1 && (unit[0] & 0x1f) <= 5)) {
        return;
      }
    }
    if (!this.configSent || units.some((unit: Uint8Array): boolean =>
      unit.length > 0 && ((unit[0] & 0x1f) === 7 || (unit[0] & 0x1f) === 8))) {
      await this.collectCodecConfiguration(units);
      if (!this.configSent) {
        return;
      }
    }
    if (this.awaitingConfigKeyFrame) {
      if ((event.flags & H264_SYNC_FRAME_FLAG) === 0 && !containsH264Idr(units)) {
        return;
      }
      this.awaitingConfigKeyFrame = false;
    }
    await this.sendFrame(units);
  }

  private async collectCodecConfiguration(units: Uint8Array[]): Promise<void> {
    let changed = false;
    for (const unit of units) {
      if (unit.length === 0) {
        continue;
      }
      const type = unit[0] & 0x1f;
      if (type === 7) {
        changed ||= !sameNalUnit(this.pendingSps, unit);
        this.pendingSps = unit.slice();
      } else if (type === 8) {
        changed ||= !sameNalUnit(this.pendingPps, unit);
        this.pendingPps = unit.slice();
      }
    }
    if (changed && this.configSent) {
      this.configSent = false;
      this.awaitingConfigKeyFrame = true;
      this.requestRecoveryKeyFrame();
    }
    if (!this.pendingSps || !this.pendingPps || this.configSent) {
      return;
    }
    const record = buildAvcConfigurationRecord([patchH264SpsLevel(this.pendingSps), this.pendingPps]);
    const header = buildAirPlayVideoConfigHeader(record.length, this.width, this.height);
    const packet = concatBytes(header, record);
    await this.sendBytes(packet);
    this.configSent = true;
    this.log(formatProtocolEvent('airplay.video.codec_config.tx',
      'width', this.width,
      'height', this.height,
      'configurationBytes', record.length,
      'wireBytes', packet.length,
      'levelIdc', record[3] ?? 0
    ));
    this.log(formatProtocolEvent('protocol.interpretation',
      'transport', 'AirPlay video/TCP',
      'meaning', '发送 H.264 SPS/PPS 配置记录；接收端用它初始化解码器，未记录媒体内容'
    ));
  }

  private async sendFrame(units: Uint8Array[]): Promise<void> {
    const filtered = units.filter((unit: Uint8Array): boolean => unit.length > 0)
      .map((unit: Uint8Array): Uint8Array => (unit[0] & 0x1f) === 7 ? patchH264SpsLevel(unit) : unit);
    if (filtered.length === 0) {
      return;
    }
    const plain = packH264Nals(filtered);
    const plainLength = plain.length;
    const timestampMs = Date.now();
    const header = buildAirPlayVideoFrameHeader(plainLength + CHACHA_TAG_SIZE, timestampMs);
    const frameCounter = this.frameCounter;
    const frameNumber = this.framesSent + 1;
    const nalTypes = filtered.map((unit: Uint8Array): string => String(unit[0] & 0x1f));
    const hasIdr = containsH264Idr(filtered);
    const nonce = buildVideoFrameNonce(frameCounter);
    this.frameCounter++;
    const encrypted = await this.cipher.seal(
      nonce,
      plain,
      header
    );
    await this.sendBytes(concatBytes(header, encrypted));
    this.framesSent = frameNumber;
    this.log(formatProtocolEvent('airplay.video.frame.tx',
      'frame', frameNumber,
      'nonceCounter', frameCounter.toString(),
      'timestampMs', timestampMs,
      'width', this.width,
      'height', this.height,
      'nalTypes', nalTypes,
      'keyFrame', hasIdr,
      'mediaBytes', plainLength,
      'encryptedBytes', encrypted.length,
      'wireBytes', header.length + encrypted.length
    ));
    this.log(formatProtocolEvent('protocol.interpretation',
      'transport', 'AirPlay video/TCP',
      'meaning', `发送 H.264 ${hasIdr ? '关键帧' : '视频帧'}；NAL 类型和帧计数用于诊断解码/丢帧，载荷未写入日志`
    ));
  }
}

function containsH264Idr(units: Uint8Array[]): boolean {
  return units.some((unit: Uint8Array): boolean => unit.length > 0 && (unit[0] & 0x1f) === 5);
}

function sameNalUnit(previous: Uint8Array | undefined, current: Uint8Array): boolean {
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

function validateVideoShape(width: number, height: number): void {
  if (!Number.isInteger(width) || !Number.isInteger(height) ||
    width < 320 || height < 240 || width > 1920 || height > 1200 ||
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
