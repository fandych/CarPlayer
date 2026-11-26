import { PlistNode } from '../BinaryPlist';
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
  const nativeWidth = readPositiveInteger(widthNode);
  const nativeHeight = readPositiveInteger(heightNode);
  const frameRate = readPositiveInteger(maxFpsNode);
  if (nativeWidth === undefined || nativeHeight === undefined) {
    throw new Error('AirPlay /info display is missing valid widthPixels/heightPixels; refusing to guess output size');
  }
  const viewArea = readActiveViewArea(display, nativeWidth, nativeHeight);
  const displayType = readPositiveInteger(display.get('type')) ?? 0;
  const availableModes = projectionDisplayModes(
    normalizedUuid, nativeWidth, nativeHeight, VERIFIED_PROJECTION_DISPLAY_MODES, isH264EncoderSizeSupported
  );
  const preferredModeId = readProjectionResolutionPreference(normalizedUuid);
  const selectedMode = resolveProjectionDisplayMode(availableModes, preferredModeId);
  const resolutionMessages: string[] = [];
  if (selectedMode.usedNativeFallback) {
    resolutionMessages.push(selectedMode.mode.isNative
      ? `保存的分辨率档位 ${preferredModeId} 未在当前显示 Profile 验证，已恢复车机原生 ${nativeWidth}×${nativeHeight}`
      : `H.264 编码器不支持车机原生 ${nativeWidth}×${nativeHeight}，已自动下采样到 ` +
        `${selectedMode.mode.width}×${selectedMode.mode.height}`);
    saveProjectionResolutionPreference(normalizedUuid, selectedMode.mode.id);
  }
  const scaleX = selectedMode.mode.width / nativeWidth;
  const scaleY = selectedMode.mode.height / nativeHeight;
  const viewAreaOriginX = Math.round(viewArea.originX * scaleX);
  const viewAreaOriginY = Math.round(viewArea.originY * scaleY);
  const scaledViewArea: AirPlayViewArea = {
    originX: viewAreaOriginX,
    originY: viewAreaOriginY,
    width: Math.max(1, Math.min(selectedMode.mode.width - viewAreaOriginX,
      Math.round(viewArea.width * scaleX))),
    height: Math.max(1, Math.min(selectedMode.mode.height - viewAreaOriginY,
      Math.round(viewArea.height * scaleY)))
  };
  if (scaledViewArea.width !== selectedMode.mode.width || scaledViewArea.height !== selectedMode.mode.height ||
    scaledViewArea.originX !== 0 || scaledViewArea.originY !== 0) {
    resolutionMessages.push(
      `DiPlay type=${displayType} 编码画布 ${selectedMode.mode.width}×${selectedMode.mode.height}，` +
        `当前 viewArea=${scaledViewArea.width}×${scaledViewArea.height}@${scaledViewArea.originX},${scaledViewArea.originY}`
    );
  }
  return {
    uuid: normalizedUuid,
    displayType,
    width: selectedMode.mode.width,
    height: selectedMode.mode.height,
    nativeWidth,
    nativeHeight,
    viewArea: scaledViewArea,
    sourceWidth: nativeWidth,
    sourceHeight: nativeHeight,
    maxFrameRate: Math.min(60, frameRate ?? 30),
    modeId: selectedMode.mode.id,
    availableModes,
    resolutionMessage: resolutionMessages.join('；')
  };
}
