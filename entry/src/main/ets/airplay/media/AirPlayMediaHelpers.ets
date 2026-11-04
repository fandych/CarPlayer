import cryptoFramework from '@ohos.security.cryptoFramework';
import { AirPlayRtspResponse } from '../AirPlayRtspClient';
import { BinaryPlist, PlistNode } from '../BinaryPlist';
import {
  projectionDisplayModes, ProjectionDisplayMode, readProjectionResolutionPreference,
  resolveProjectionDisplayMode, saveProjectionResolutionPreference, VERIFIED_PROJECTION_DISPLAY_MODES
} from '../../video/ProjectionSettings';
import { isH264EncoderSizeSupported } from '../../video/H264EncoderCapabilities';

export interface AirPlayViewArea {
  originX: number;
  originY: number;
  width: number;
  height: number;
}

export interface PcmAudioFormat {
  formatBit: bigint;
  sampleRate: number;
}

export interface AirPlayDisplayDescriptor {
  uuid: string;
  displayType: number;
  width: number;
  height: number;
  nativeWidth: number;
  nativeHeight: number;
  viewArea: AirPlayViewArea;
  sourceWidth: number;
  sourceHeight: number;
  maxFrameRate: number;
  modeId: string;
  availableModes: ProjectionDisplayMode[];
  resolutionMessage: string;
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

export function readActiveViewArea(display: PlistNode, canvasWidth: number, canvasHeight: number): AirPlayViewArea {
  const fullCanvas: AirPlayViewArea = { originX: 0, originY: 0, width: canvasWidth, height: canvasHeight };
  const areas = display.get('viewAreas');
  if (!areas || areas.kind !== 'array' || areas.arrayValue.length === 0) {
    return fullCanvas;
  }
  const initialNode = display.get('initialViewArea');
  const initialIndex = initialNode?.kind === 'integer' ? Number(initialNode.integerValue) : 0;
  const selected = Number.isSafeInteger(initialIndex) && initialIndex >= 0 && initialIndex < areas.arrayValue.length
    ? areas.arrayValue[initialIndex] : areas.arrayValue[0];
  if (!selected || selected.kind !== 'dictionary') {
    return fullCanvas;
  }
  const view = selected.get('viewArea') ?? selected;
  if (view.kind !== 'dictionary') {
    return fullCanvas;
  }
  const readInteger = (primary: string, fallback: string, defaultValue: number): number => {
    const node = view.get(primary) ?? view.get(fallback);
    if (!node || node.kind !== 'integer') {
      return defaultValue;
    }
    const value = Number(node.integerValue);
    return Number.isSafeInteger(value) ? value : defaultValue;
  };
  const originX = readInteger('originXPixels', 'originX', 0);
  const originY = readInteger('originYPixels', 'originY', 0);
  const width = readInteger('widthPixels', 'width', canvasWidth);
  const height = readInteger('heightPixels', 'height', canvasHeight);
  if (originX < 0 || originY < 0 || width < 1 || height < 1 ||
    originX + width > canvasWidth || originY + height > canvasHeight) {
    return fullCanvas;
  }
  return { originX, originY, width, height };
}

export function readDisplayInfo(info: PlistNode): AirPlayDisplayDescriptor {
  const displays = info.get('displays');
  if (!displays || displays.kind !== 'array' || displays.arrayValue.length === 0) {
    throw new Error('AirPlay /info did not provide a display descriptor; refusing to invent a display UUID');
  }
  const display = displays.arrayValue[0];
  if (display.kind !== 'dictionary') {
    throw new Error('AirPlay /info displays[0] is not a dictionary');
  }
  const uuid = display.get('uuid') ?? display.get('UUID');
  if (!uuid) {
    throw new Error('AirPlay /info display descriptor has no UUID');
  }
  let normalizedUuid: string;
  if (uuid.kind === 'string' && uuid.stringValue.length > 0) {
    normalizedUuid = uuid.stringValue;
  } else if (uuid.kind === 'integer') {
    normalizedUuid = uuid.integerValue.toString();
  } else if (uuid.kind === 'data' && uuid.dataValue.length === 16) {
    const hex = Array.from(uuid.dataValue).map((value: number): string =>
      value.toString(16).padStart(2, '0')
    ).join('');
    normalizedUuid =
      `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`;
  } else {
    throw new Error('AirPlay /info display UUID has an unsupported type or length');
  }
  const widthNode = display.get('widthPixels') ?? display.get('width');
  const heightNode = display.get('heightPixels') ?? display.get('height');
  const maxFpsNode = display.get('maxFPS');
  const readPositiveInteger = (node: PlistNode | undefined): number | undefined => {
    if (!node || node.kind !== 'integer') {
      return undefined;
    }
    const value = Number(node.integerValue);
    return Number.isSafeInteger(value) && value > 0 ? value : undefined;
  };
  const rawWidth = readPositiveInteger(widthNode);
  const rawHeight = readPositiveInteger(heightNode);
  const frameRate = readPositiveInteger(maxFpsNode);
  if (rawWidth === undefined || rawHeight === undefined) {
    throw new Error('AirPlay /info display is missing valid widthPixels/heightPixels; refusing to guess output size');
  }
  const nativeWidth = rawWidth;
  const nativeHeight = rawHeight;
  const nativeViewArea = readActiveViewArea(display, nativeWidth, nativeHeight);
  const displayType = readPositiveInteger(display.get('type')) ?? 0;
  const availableModes = projectionDisplayModes(
    normalizedUuid,
    nativeWidth,
    nativeHeight,
    VERIFIED_PROJECTION_DISPLAY_MODES,
    isH264EncoderSizeSupported
  );
  const preferredModeId = readProjectionResolutionPreference(normalizedUuid);
  const selectedMode = resolveProjectionDisplayMode(availableModes, preferredModeId);
  const resolutionMessage = selectedMode.usedNativeFallback
    ? selectedMode.mode.isNative
      ? `保存的分辨率档位 ${preferredModeId} 未在当前显示 Profile 验证，已恢复车机原生 ${nativeWidth}×${nativeHeight}`
      : `H.264 编码器不支持车机原生 ${nativeWidth}×${nativeHeight}，已自动下采样到 ` +
        `${selectedMode.mode.width}×${selectedMode.mode.height}`
    : '';
  if (selectedMode.usedNativeFallback) {
    saveProjectionResolutionPreference(normalizedUuid, selectedMode.mode.id);
  }
  const scaleX = selectedMode.mode.width / nativeWidth;
  const scaleY = selectedMode.mode.height / nativeHeight;
  const viewAreaOriginX = Math.round(nativeViewArea.originX * scaleX);
  const viewAreaOriginY = Math.round(nativeViewArea.originY * scaleY);
  const viewArea: AirPlayViewArea = {
    originX: viewAreaOriginX,
    originY: viewAreaOriginY,
    width: Math.max(1, Math.min(selectedMode.mode.width - viewAreaOriginX,
      Math.round(nativeViewArea.width * scaleX))),
    height: Math.max(1, Math.min(selectedMode.mode.height - viewAreaOriginY,
      Math.round(nativeViewArea.height * scaleY)))
  };
  const resolutionMessages: string[] = [];
  if (selectedMode.usedNativeFallback) {
    resolutionMessages.push(selectedMode.mode.isNative
      ? `保存的分辨率档位 ${preferredModeId} 未在当前显示 Profile 验证，已恢复车机原生 ${nativeWidth}×${nativeHeight}`
      : `H.264 编码器不支持车机原生 ${nativeWidth}×${nativeHeight}，已自动下采样到 ` +
        `${selectedMode.mode.width}×${selectedMode.mode.height}`);
  }
  if (viewArea.width !== selectedMode.mode.width || viewArea.height !== selectedMode.mode.height ||
    viewArea.originX !== 0 || viewArea.originY !== 0) {
    resolutionMessages.push(
      `DiPlay type=${displayType} 编码画布 ${selectedMode.mode.width}×${selectedMode.mode.height}，` +
        `当前 viewArea=${viewArea.width}×${viewArea.height}@${viewArea.originX},${viewArea.originY}`
    );
  }
  return {
    uuid: normalizedUuid,
    displayType,
    width: selectedMode.mode.width,
    height: selectedMode.mode.height,
    nativeWidth,
    nativeHeight,
    viewArea,
    sourceWidth: nativeWidth,
    sourceHeight: nativeHeight,
    maxFrameRate: Math.min(60, frameRate ?? 30),
    modeId: selectedMode.mode.id,
    availableModes,
    resolutionMessage: resolutionMessages.join('；')
  };
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
