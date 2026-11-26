import cryptoFramework from '@ohos.security.cryptoFramework';
import { AirPlayRtspResponse } from '../AirPlayRtspClient';
import { BinaryPlist, PlistNode } from '../BinaryPlist';
export {
  AirPlayDisplayDescriptor,
  AirPlayViewArea,
  readActiveViewArea,
  readDisplayInfo
} from './AirPlayDisplayInfo';

export interface PcmAudioFormat {
  formatBit: bigint;
  sampleRate: number;
}

interface AirPlayNetworkError extends Error {
  code?: string | number;
}

export class AirPlayMediaSessionStatusError extends Error {
  readonly statusCode: number;
  readonly stage: string;
  readonly statusLine: string;

  constructor(statusCode: number, statusLine: string, stage: string, message?: string) {
    super(message ?? `${stage} rejected: ${statusLine}`);
    this.statusCode = statusCode;
    this.stage = stage;
    this.statusLine = statusLine;
  }
}

export function requireDictionary(response: AirPlayRtspResponse, label: string): PlistNode {
  const value = BinaryPlist.decode(response.body);
  if (value.kind !== 'dictionary') {
    throw new Error(`${label} response is not a binary plist dictionary`);
  }
  return value;
}

export function requireSuccess(response: AirPlayRtspResponse, label: string): void {
  if (response.statusCode !== 200) {
    throw new AirPlayMediaSessionStatusError(response.statusCode, response.statusLine, label);
  }
}

export function readPort(node: PlistNode | undefined): number {
  if (!node || node.kind !== 'integer') {
    return 0;
  }
  const port = Number(node.integerValue);
  return Number.isSafeInteger(port) && port >= 0 && port <= 65535 ? port : 0;
}

export function isForceKeyFrameCommand(command: PlistNode): boolean {
  if (command.kind !== 'dictionary') {
    return false;
  }
  const type = command.get('type');
  const legacyCommand = command.get('command');
  return (type?.kind === 'string' && type.stringValue === 'forceKeyFrame') ||
    (legacyCommand?.kind === 'string' && legacyCommand.stringValue === 'forceKeyFrame');
}

export function parseIapSendMessagePayload(command: PlistNode): Uint8Array | undefined {
  if (command.kind !== 'dictionary' ||
    command.get('type')?.kind !== 'string' ||
    command.get('type')?.stringValue !== 'iAPSendMessage') {
    return undefined;
  }
  const params = command.get('params');
  if (!params || params.kind !== 'dictionary') {
    throw new Error('iAPSendMessage requires a params dictionary');
  }
  const data = params.get('data');
  if (!data || data.kind !== 'data' || data.dataValue.length === 0) {
    throw new Error('iAPSendMessage requires non-empty params.data');
  }
  return data.dataValue.slice();
}

export function selectPcmAudioFormat(info: PlistNode): PcmAudioFormat | undefined {
  const formats = info.get('audioFormats');
  if (!formats || formats.kind !== 'array') {
    return undefined;
  }
  let supports48k = false;
  let supports44k = false;
  for (const entry of formats.arrayValue) {
    if (entry.kind !== 'dictionary' || entry.get('type')?.integerValue !== BigInt(100) ||
      entry.get('audioType')?.stringValue !== 'media') {
      continue;
    }
    const output = entry.get('audioOutputFormats');
    if (!output || output.kind !== 'integer') {
      continue;
    }
    supports48k ||= (output.integerValue & (BigInt(1) << BigInt(15))) !== BigInt(0);
    supports44k ||= (output.integerValue & (BigInt(1) << BigInt(11))) !== BigInt(0);
  }
  if (supports48k) {
    return { formatBit: BigInt(1) << BigInt(15), sampleRate: 48000 };
  }
  if (supports44k) {
    return { formatBit: BigInt(1) << BigInt(11), sampleRate: 44100 };
  }
  return undefined;
}

export function readAudioLatency(info: PlistNode, sampleRate: number): number {
  const latencies = info.get('audioLatencies');
  if (!latencies || latencies.kind !== 'array') {
    return 250;
  }
  const selected = latencies.arrayValue.find((entry: PlistNode): boolean =>
    entry.kind === 'dictionary' &&
    entry.get('type')?.integerValue === BigInt(100) &&
    entry.get('audioType')?.stringValue === 'media'
  );
  const outputLatency = selected?.get('outputLatencyMicros');
  if (!outputLatency || outputLatency.kind !== 'integer') {
    return 250;
  }
  const milliseconds = Number(outputLatency.integerValue) / 1000;
  if (!Number.isFinite(milliseconds) || milliseconds < 0) {
    return 250;
  }
  return Math.max(32, Math.min(2000, Math.round(milliseconds + (sampleRate === 44100 ? 30 : 0))));
}

export function readStringArray(node: PlistNode | undefined): string[] {
  if (!node || node.kind !== 'array') {
    return [];
  }
  return node.arrayValue
    .filter((item: PlistNode): boolean => item.kind === 'string')
    .map((item: PlistNode): string => item.stringValue);
}

export function normalizeDeviceId(value: string): string {
  const normalized = value.trim().toUpperCase();
  if (!/^[0-9A-F]{2}(:[0-9A-F]{2}){5}$/.test(normalized) ||
    normalized === '02:00:00:00:00:00') {
    throw new Error('AirPlay session requires a real Bluetooth device address; replace the placeholder in Settings');
  }
  return normalized;
}

export async function randomPositiveInt64(): Promise<bigint> {
  const blob = await cryptoFramework.createRandom().generateRandom(8);
  const random = new Uint8Array(blob.data);
  let value = BigInt(0);
  for (const byte of random) {
    value = (value << BigInt(8)) | BigInt(byte);
  }
  value &= (BigInt(1) << BigInt(63)) - BigInt(1);
  return value === BigInt(0) ? BigInt(1) : value;
}

export function createUuid(): string {
  const digits: string[] = [];
  for (let index = 0; index < 32; index++) {
    digits.push(Math.floor(Math.random() * 16).toString(16));
  }
  digits[12] = '4';
  const variant = Number.parseInt(digits[16], 16);
  digits[16] = ((variant & 3) | 8).toString(16);
  const raw = digits.join('').toUpperCase();
  return `${raw.slice(0, 8)}-${raw.slice(8, 12)}-${raw.slice(12, 16)}-${raw.slice(16, 20)}-${raw.slice(20)}`;
}

export function createNtpTimestamp(nowMillis: number): Uint8Array {
  const seconds = Math.floor(nowMillis / 1000) + 2208988800;
  const fraction = Math.floor(((nowMillis % 1000) * 0x100000000) / 1000);
  const result = new Uint8Array(8);
  writeBe32(result, 0, seconds);
  writeBe32(result, 4, fraction);
  return result;
}

export function describeNetworkError(error: Error): string {
  const details = error as AirPlayNetworkError;
  const message = details.message || String(error);
  return details.code === undefined ? message : `${message} (code=${details.code})`;
}

function writeBe32(target: Uint8Array, offset: number, value: number): void {
  target[offset] = (value >>> 24) & 0xff;
  target[offset + 1] = (value >>> 16) & 0xff;
  target[offset + 2] = (value >>> 8) & 0xff;
  target[offset + 3] = value & 0xff;
}
