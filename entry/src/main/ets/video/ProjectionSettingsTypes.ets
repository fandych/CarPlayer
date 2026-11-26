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
export type ProjectionSplitPane = 'map' | 'music';

export const RECEIVER_NATIVE_MODE_ID: string = 'receiver-native';
export const PROJECTION_ENCODER_MAX_WIDTH: number = 4096;
export const PROJECTION_ENCODER_MAX_HEIGHT: number = 2160;
export const PROJECTION_SPLIT_RATIO_MIN: number = 1;
export const PROJECTION_SPLIT_RATIO_MAX: number = 10;

export const VERIFIED_PROJECTION_DISPLAY_MODES: VerifiedProjectionDisplayMode[] = [];

export const PROJECTION_THEMES: ProjectionTheme[] = [
  { id: 'aurora', label: '极光', background: '#10101C', surface: '#262630', panel: '#1E1E26' },
  { id: 'sunset', label: '日落', background: '#2B1033', surface: '#262630', panel: '#1E1E26' },
  { id: 'forest', label: '森林', background: '#0B1F1A', surface: '#262630', panel: '#1E1E26' },
  { id: 'ocean', label: '深海', background: '#06102A', surface: '#262630', panel: '#1E1E26' },
  { id: 'graphite', label: '石墨', background: '#16161A', surface: '#262630', panel: '#1E1E26' }
];

export const PROJECTION_ACCENTS: string[] = [
  '#0A84FF', '#30D158', '#FF9F0A', '#FF375F', '#BF5AF2', '#64D2FF'
];
