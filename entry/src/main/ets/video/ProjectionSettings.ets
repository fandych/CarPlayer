export interface ProjectionRates {
  capture: number;
  encode: number;
}

export interface ProjectionDisplayMode {
  id: string;
  label: string;
  width: number;
  height: number;
  isNative: boolean;
}

export interface VerifiedProjectionDisplayMode {
  displayUuid: string;
  nativeWidth: number;
  nativeHeight: number;
  id: string;
  width: number;
  height: number;
  encoder: 'video/avc';
}

export interface ProjectionDisplayModeResolution {
  mode: ProjectionDisplayMode;
  usedNativeFallback: boolean;
}

export interface ProjectionContentCalibration {
  scale: number;
  offsetX: number;
  offsetY: number;
}

export type ProjectionCalibrationControl = 'scale' | 'offsetX' | 'offsetY';

export interface ProjectionTheme {
  id: string;
  label: string;
  background: string;
  surface: string;
  panel: string;
}

export type ProjectionDockPosition = 'left' | 'bottom';
export type ProjectionDayNightMode = 'AUTO' | 'DAY' | 'NIGHT';
export type ProjectionSafeInsetEdge = 'top' | 'right' | 'bottom' | 'left';

export const RECEIVER_NATIVE_MODE_ID: string = 'receiver-native';
export const PROJECTION_ENCODER_MAX_WIDTH: number = 4096;
export const PROJECTION_ENCODER_MAX_HEIGHT: number = 2160;

export const VERIFIED_PROJECTION_DISPLAY_MODES: VerifiedProjectionDisplayMode[] = [];

export const PROJECTION_THEMES: ProjectionTheme[] = [
  { id: 'forest', label: '森林', background: '#101713', surface: '#202A25', panel: '#26332D' },
  { id: 'graphite', label: '石墨', background: '#161616', surface: '#242424', panel: '#323232' },
  { id: 'ocean', label: '深海', background: '#101B21', surface: '#1D3038', panel: '#2A4249' }
];

export const PROJECTION_ACCENTS: string[] = ['#41C99A', '#E6B94C', '#61B9E8', '#EB8383'];

let settingsInitialized: boolean = false;

export function initializeProjectionSettings(): void {
  if (settingsInitialized) {
    return;
  }
  PersistentStorage.persistProp('carplayTheme', 'forest');
  PersistentStorage.persistProp('carplayAccent', '#41C99A');
  PersistentStorage.persistProp('carplayEncoderFps', 30);
  PersistentStorage.persistProp('carplayCaptureFps', 60);
  PersistentStorage.persistProp('carplayUseBluetoothAudio', false);
  PersistentStorage.persistProp('carplayDockPosition', 'left');
  PersistentStorage.persistProp('carplayDayNightMode', 'AUTO');
  settingsInitialized = true;
}

export function projectionTheme(id: string): ProjectionTheme {
  return PROJECTION_THEMES.find((theme: ProjectionTheme): boolean => theme.id === id) ?? PROJECTION_THEMES[0];
}

export function resolveNightMode(mode: string, vehicleNightMode: boolean): boolean {
  if (mode === 'NIGHT') {
    return true;
  }
  if (mode === 'DAY') {
    return false;
  }
  return vehicleNightMode;
}

export function normalizeSafeInset(value: number): number {
  if (!Number.isFinite(value)) {
    return 0;
  }
  return Math.max(0, Math.min(30, Math.round(value)));
}

export function projectionSafeInsetKey(displayUuid: string, edge: ProjectionSafeInsetEdge): string {
  const profile = displayUuid.trim().toLowerCase().replace(/[^a-z0-9_-]/g, '_') || 'default';
  return `carplayDisplayProfile_${profile}_inset_${edge}`;
}

export function projectionResolutionKey(displayUuid: string): string {
  const profile = displayUuid.trim().toLowerCase().replace(/[^a-z0-9_-]/g, '_') || 'default';
  return `carplayDisplayProfile_${profile}_resolution`;
}

export function projectionContentCalibrationKey(
  displayUuid: string,
  control: ProjectionCalibrationControl
): string {
  const profile = displayUuid.trim().toLowerCase().replace(/[^a-z0-9_-]/g, '_') || 'default';
  return `carplayDisplayProfile_${profile}_content_${control}`;
}

export function normalizeProjectionContentScale(value: number): number {
  if (!Number.isFinite(value)) {
    return 100;
  }
  return Math.max(70, Math.min(100, Math.round(value)));
}

export function normalizeProjectionContentOffset(value: number): number {
  if (!Number.isFinite(value)) {
    return 0;
  }
  return Math.max(-15, Math.min(15, Math.round(value)));
}

export function readProjectionContentCalibration(displayUuid: string): ProjectionContentCalibration {
  const scaleKey = projectionContentCalibrationKey(displayUuid, 'scale');
  const offsetXKey = projectionContentCalibrationKey(displayUuid, 'offsetX');
  const offsetYKey = projectionContentCalibrationKey(displayUuid, 'offsetY');
  PersistentStorage.persistProp(scaleKey, 100);
  PersistentStorage.persistProp(offsetXKey, 0);
  PersistentStorage.persistProp(offsetYKey, 0);
  const calibration: ProjectionContentCalibration = {
    scale: normalizeProjectionContentScale(AppStorage.get<number>(scaleKey) ?? 100),
    offsetX: normalizeProjectionContentOffset(AppStorage.get<number>(offsetXKey) ?? 0),
    offsetY: normalizeProjectionContentOffset(AppStorage.get<number>(offsetYKey) ?? 0)
  };
  return calibration;
}

export function saveProjectionContentCalibration(
  displayUuid: string,
  control: ProjectionCalibrationControl,
  value: number
): number {
  if (!displayUuid.trim()) {
    throw new Error('屏幕校准缺少显示 UUID');
  }
  const normalized = control === 'scale'
    ? normalizeProjectionContentScale(value) : normalizeProjectionContentOffset(value);
  const defaultValue = control === 'scale' ? 100 : 0;
  const key = projectionContentCalibrationKey(displayUuid, control);
  PersistentStorage.persistProp(key, defaultValue);
  AppStorage.setOrCreate(key, normalized);
  return normalized;
}

export function isSupportedProjectionSize(width: number, height: number): boolean {
  return Number.isInteger(width) && Number.isInteger(height) &&
    width >= 320 && height >= 240 &&
    width <= PROJECTION_ENCODER_MAX_WIDTH && height <= PROJECTION_ENCODER_MAX_HEIGHT &&
    width % 2 === 0 && height % 2 === 0;
}

function sameAspectRatio(width: number, height: number, referenceWidth: number, referenceHeight: number): boolean {
  return width * referenceHeight === height * referenceWidth;
}

export function projectionDisplayModes(
  displayUuid: string,
  nativeWidth: number,
  nativeHeight: number,
  verifiedModes: VerifiedProjectionDisplayMode[] = VERIFIED_PROJECTION_DISPLAY_MODES,
  supportsVideoSize: (width: number, height: number) => boolean = isSupportedProjectionSize
): ProjectionDisplayMode[] {
  if (!displayUuid || !isSupportedProjectionSize(nativeWidth, nativeHeight)) {
    return [];
  }
  const nativeSupported = supportsVideoSize(nativeWidth, nativeHeight);
  const modes: ProjectionDisplayMode[] = [];
  if (nativeSupported) {
    modes.push({
      id: RECEIVER_NATIVE_MODE_ID,
      label: `车机原生 ${nativeWidth}×${nativeHeight}`,
      width: nativeWidth,
      height: nativeHeight,
      isNative: true
    });
  } else {
    const fallback = findEncoderFallbackMode(nativeWidth, nativeHeight, supportsVideoSize);
    if (fallback) {
      modes.push(fallback);
    }
  }
  const normalizedUuid = displayUuid.trim().toLowerCase();
  for (const verified of verifiedModes) {
    if (verified.displayUuid.trim().toLowerCase() !== normalizedUuid ||
      verified.nativeWidth !== nativeWidth || verified.nativeHeight !== nativeHeight ||
      verified.encoder !== 'video/avc' || !verified.id || verified.id === RECEIVER_NATIVE_MODE_ID ||
      !isSupportedProjectionSize(verified.width, verified.height) ||
      !supportsVideoSize(verified.width, verified.height) ||
      !sameAspectRatio(verified.width, verified.height, nativeWidth, nativeHeight) ||
      modes.some((mode: ProjectionDisplayMode): boolean =>
        mode.id === verified.id || (mode.width === verified.width && mode.height === verified.height))) {
      continue;
    }
    modes.push({
      id: verified.id,
      label: `${verified.width}×${verified.height}`,
      width: verified.width,
      height: verified.height,
      isNative: false
    });
  }
  return modes;
}

function findEncoderFallbackMode(
  nativeWidth: number,
  nativeHeight: number,
  supportsVideoSize: (width: number, height: number) => boolean
): ProjectionDisplayMode | undefined {
  const maxScale = Math.min(
    1,
    PROJECTION_ENCODER_MAX_WIDTH / nativeWidth,
    PROJECTION_ENCODER_MAX_HEIGHT / nativeHeight
  );
  for (let step = 0; step < 20; step++) {
    const scale = maxScale * (1 - step * 0.05);
    const width = Math.floor(nativeWidth * scale / 2) * 2;
    const height = Math.floor(nativeHeight * scale / 2) * 2;
    if ((width === nativeWidth && height === nativeHeight) || !isSupportedProjectionSize(width, height) ||
      !supportsVideoSize(width, height)) {
      continue;
    }
    return {
      id: `encoder-fallback-${width}x${height}`,
      label: `H.264 兼容 ${width}×${height}`,
      width,
      height,
      isNative: false
    };
  }
  return undefined;
}

export function resolveProjectionDisplayMode(
  modes: ProjectionDisplayMode[],
  selectedModeId: string
): ProjectionDisplayModeResolution {
  const nativeMode = modes.find((mode: ProjectionDisplayMode): boolean => mode.isNative);
  const selectedMode = modes.find((mode: ProjectionDisplayMode): boolean => mode.id === selectedModeId);
  if (!nativeMode) {
    const fallbackMode = selectedMode ?? modes[0];
    if (!fallbackMode) {
      throw new Error('车机原生分辨率不受 H.264 编码器支持，且没有可用的下采样档位');
    }
    return { mode: fallbackMode, usedNativeFallback: true };
  }
  return {
    mode: selectedMode ?? nativeMode,
    usedNativeFallback: selectedMode === undefined
  };
}

export function readProjectionResolutionPreference(displayUuid: string): string {
  const key = projectionResolutionKey(displayUuid);
  PersistentStorage.persistProp(key, RECEIVER_NATIVE_MODE_ID);
  return AppStorage.get<string>(key) ?? RECEIVER_NATIVE_MODE_ID;
}

export function saveProjectionResolutionPreference(displayUuid: string, modeId: string): void {
  if (!displayUuid.trim() || !modeId.trim()) {
    throw new Error('投屏分辨率设置缺少显示 UUID 或档位 ID');
  }
  const key = projectionResolutionKey(displayUuid);
  PersistentStorage.persistProp(key, RECEIVER_NATIVE_MODE_ID);
  AppStorage.setOrCreate(key, modeId);
}

export function resolveProjectionRates(maximum: number, encode: number, capture: number): ProjectionRates {
  const limit = Number.isFinite(maximum) && maximum > 0 ? Math.min(60, Math.floor(maximum)) : 30;
  const captureRate = Math.min(limit, [30, 60].includes(capture) ? capture : 60);
  return {
    capture: captureRate,
    encode: Math.min(captureRate, [15, 24, 30, 60].includes(encode) ? encode : 30)
  };
}