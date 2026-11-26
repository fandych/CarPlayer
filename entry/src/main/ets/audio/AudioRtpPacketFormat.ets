export const SAMPLES_PER_PACKET: number = 352;

export function advanceAudioRtpTimestamp(timestamp: number, packets: number): number {
  return (timestamp + packets * SAMPLES_PER_PACKET) >>> 0;
}

export function buildAudioRtpHeader(sequence: number, timestamp: number, marker: boolean): Uint8Array {
  const header = new Uint8Array(12);
  header[0] = 0x80;
  header[1] = (marker ? 0x80 : 0) | 100;
  writeBe16(header, 2, sequence);
  writeBe32(header, 4, timestamp);
  writeBe32(header, 8, 0);
  return header;
}

export function buildAudioRtpSyncPacket(
  sequence: number,
  rtpTimestamp: number,
  nowMillis: number,
  first: boolean
): Uint8Array {
  if (!Number.isInteger(sequence) || sequence < 0 || sequence > 0xffff ||
    !Number.isInteger(rtpTimestamp) || rtpTimestamp < 0 || rtpTimestamp > 0xffffffff ||
    !Number.isFinite(nowMillis) || nowMillis < 0) {
    throw new Error('Invalid AirPlay audio sync time');
  }
  const packet = new Uint8Array(20);
  packet[0] = first ? 0x90 : 0x80;
  packet[1] = 0xd4;
  writeBe16(packet, 2, sequence);
  writeBe32(packet, 4, rtpTimestamp);
  packet.set(createNtpTimestamp(nowMillis), 8);
  writeBe32(packet, 16, advanceAudioRtpTimestamp(rtpTimestamp, 1));
  return packet;
}

export function nonce64(counter: number): Uint8Array {
  const nonce = new Uint8Array(12);
  let remaining = counter;
  for (let index = 4; index < 12; index++) {
    nonce[index] = remaining & 0xff;
    remaining = Math.floor(remaining / 256);
  }
  return nonce;
}

function createNtpTimestamp(nowMillis: number): Uint8Array {
  const seconds = Math.floor(nowMillis / 1000) + 2208988800;
  const fraction = Math.floor(((nowMillis % 1000) * 0x100000000) / 1000);
  const result = new Uint8Array(8);
  writeBe32(result, 0, seconds);
  writeBe32(result, 4, fraction);
  return result;
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
