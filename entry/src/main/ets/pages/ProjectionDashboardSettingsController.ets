import {
  ProjectionCalibrationControl,
  ProjectionContentCalibration,
  ProjectionDisplayMode,
  ProjectionSafeInsetEdge,
  ProjectionSplitPane,
  normalizeSafeInset,
  projectionSafeInsetKey,
  readProjectionContentCalibration,
  readProjectionResolutionPreference,
  readProjectionSplitRatio,
  resolveProjectionDisplayMode,
  saveProjectionContentCalibration,
  saveProjectionResolutionPreference,
  saveProjectionSplitRatio,
  RECEIVER_NATIVE_MODE_ID
} from '../video/ProjectionSettings';

export interface ProjectionDashboardSettingsState {
  encoderFps: number;
  captureFps: number;
  dayNightMode: string;
  displayBrightness: number;
  splitMapRatio: number;
  splitMusicRatio: number;
  splitMapRatioInput: string;
  splitMusicRatioInput: string;
  splitRatioMessage: string;
  vehicleDisplayUuid: string;
  safeInsetTop: number;
  safeInsetRight: number;
  safeInsetBottom: number;
  safeInsetLeft: number;
  contentScalePercent: number;
  contentOffsetXPercent: number;
  contentOffsetYPercent: number;
  calibrationMessage: string;
  projectionModeOptions: ProjectionDisplayMode[];
  selectedProjectionModeId: string;
  activeProjectionModeId: string;
  resolutionSelectionMessage: string;
}

export class ProjectionDashboardSettingsController {
  selectEncoderFps(state: ProjectionDashboardSettingsState, index: number): void {
    const fps = [30, 60][index];
    if (fps !== undefined) {
      state.encoderFps = fps;
      if (fps > state.captureFps) {
        state.captureFps = fps;
      }
    }
  }

  normalizeEncoderFps(state: ProjectionDashboardSettingsState): void {
    if (![30, 60].includes(state.encoderFps)) {
      state.encoderFps = 30;
    }
  }

  selectCaptureFps(state: ProjectionDashboardSettingsState, index: number): void {
    const fps = [30, 60][index];
    if (fps !== undefined) {
      state.captureFps = fps;
    }
  }

  selectDayNightMode(state: ProjectionDashboardSettingsState, mode: 'AUTO' | 'DAY' | 'NIGHT'): void {
    state.dayNightMode = mode;
  }

  updateDisplayBrightness(state: ProjectionDashboardSettingsState, value: number): void {
    state.displayBrightness = Math.round(Math.max(20, Math.min(100, value)));
  }

  loadSplitRatios(state: ProjectionDashboardSettingsState): void {
    state.splitMapRatio = readProjectionSplitRatio('map');
    state.splitMusicRatio = readProjectionSplitRatio('music');
    state.splitMapRatioInput = `${state.splitMapRatio}`;
    state.splitMusicRatioInput = `${state.splitMusicRatio}`;
  }

  updateSplitRatio(state: ProjectionDashboardSettingsState, pane: ProjectionSplitPane, value: number): void {
    const ratio = saveProjectionSplitRatio(pane, value);
    if (pane === 'map') {
      state.splitMapRatio = ratio;
      state.splitMapRatioInput = `${ratio}`;
    } else {
      state.splitMusicRatio = ratio;
      state.splitMusicRatioInput = `${ratio}`;
    }
    const otherInput = pane === 'map' ? state.splitMusicRatioInput : state.splitMapRatioInput;
    state.splitRatioMessage = otherInput.length > 0 && !/^(?:[1-9]|10)$/.test(otherInput)
      ? '每个比例值必须是 1–10 的整数' : '';
  }

  adjustSplitRatio(state: ProjectionDashboardSettingsState, pane: ProjectionSplitPane, delta: number): void {
    this.updateSplitRatio(state, pane, (pane === 'map' ? state.splitMapRatio : state.splitMusicRatio) + delta);
  }

  updateSplitRatioInput(
    state: ProjectionDashboardSettingsState, pane: ProjectionSplitPane, value: string
  ): void {
    const input = value.replace(/[^0-9]/g, '').slice(0, 2);
    if (pane === 'map') {
      state.splitMapRatioInput = input;
    } else {
      state.splitMusicRatioInput = input;
    }
    if (input.length === 0) {
      const otherInput = pane === 'map' ? state.splitMusicRatioInput : state.splitMapRatioInput;
      state.splitRatioMessage = otherInput.length > 0 && !/^(?:[1-9]|10)$/.test(otherInput)
        ? '每个比例值必须是 1–10 的整数' : '';
      return;
    }
    const ratio = Number.parseInt(input, 10);
    if (ratio >= 1 && ratio <= 10) {
      this.updateSplitRatio(state, pane, ratio);
    } else {
      state.splitRatioMessage = '每个比例值必须是 1–10 的整数';
    }
  }

  restoreSplitRatioInput(state: ProjectionDashboardSettingsState, pane: ProjectionSplitPane): void {
    const input = pane === 'map' ? state.splitMapRatioInput : state.splitMusicRatioInput;
    const valid = /^(?:[1-9]|10)$/.test(input);
    if (pane === 'map') {
      state.splitMapRatioInput = `${state.splitMapRatio}`;
    } else {
      state.splitMusicRatioInput = `${state.splitMusicRatio}`;
    }
    const otherInput = pane === 'map' ? state.splitMusicRatioInput : state.splitMapRatioInput;
    state.splitRatioMessage = !valid || (otherInput.length > 0 && !/^(?:[1-9]|10)$/.test(otherInput))
      ? '每个比例值必须是 1–10 的整数' : '';
  }

  adjustSafeInset(
    state: ProjectionDashboardSettingsState, edge: ProjectionSafeInsetEdge, delta: number
  ): void {
    if (edge === 'top') {
      state.safeInsetTop = normalizeSafeInset(state.safeInsetTop + delta);
      AppStorage.setOrCreate(projectionSafeInsetKey(state.vehicleDisplayUuid, edge), state.safeInsetTop);
    } else if (edge === 'right') {
      state.safeInsetRight = normalizeSafeInset(state.safeInsetRight + delta);
      AppStorage.setOrCreate(projectionSafeInsetKey(state.vehicleDisplayUuid, edge), state.safeInsetRight);
    } else if (edge === 'bottom') {
      state.safeInsetBottom = normalizeSafeInset(state.safeInsetBottom + delta);
      AppStorage.setOrCreate(projectionSafeInsetKey(state.vehicleDisplayUuid, edge), state.safeInsetBottom);
    } else {
      state.safeInsetLeft = normalizeSafeInset(state.safeInsetLeft + delta);
      AppStorage.setOrCreate(projectionSafeInsetKey(state.vehicleDisplayUuid, edge), state.safeInsetLeft);
    }
  }

  loadSafeInsets(state: ProjectionDashboardSettingsState): void {
    state.safeInsetTop = this.readSafeInset(state, 'top');
    state.safeInsetRight = this.readSafeInset(state, 'right');
    state.safeInsetBottom = this.readSafeInset(state, 'bottom');
    state.safeInsetLeft = this.readSafeInset(state, 'left');
  }

  private readSafeInset(state: ProjectionDashboardSettingsState, edge: ProjectionSafeInsetEdge): number {
    const key = projectionSafeInsetKey(state.vehicleDisplayUuid, edge);
    PersistentStorage.persistProp(key, 0);
    return normalizeSafeInset(AppStorage.get<number>(key) ?? 0);
  }

  loadContentCalibration(state: ProjectionDashboardSettingsState): void {
    const calibration: ProjectionContentCalibration = readProjectionContentCalibration(state.vehicleDisplayUuid);
    state.contentScalePercent = calibration.scale;
    state.contentOffsetXPercent = calibration.offsetX;
    state.contentOffsetYPercent = calibration.offsetY;
  }

  adjustContentCalibration(
    state: ProjectionDashboardSettingsState, control: ProjectionCalibrationControl, delta: number
  ): void {
    if (!state.vehicleDisplayUuid) {
      state.calibrationMessage = '缺少车机显示 UUID，无法保存屏幕校准';
      return;
    }
    const currentValue = control === 'scale'
      ? state.contentScalePercent
      : control === 'offsetX' ? state.contentOffsetXPercent : state.contentOffsetYPercent;
    try {
      const value = saveProjectionContentCalibration(state.vehicleDisplayUuid, control, currentValue + delta);
      if (control === 'scale') {
        state.contentScalePercent = value;
      } else if (control === 'offsetX') {
        state.contentOffsetXPercent = value;
      } else {
        state.contentOffsetYPercent = value;
      }
      state.calibrationMessage = '校准已保存；输出分辨率保持不变';
    } catch (error) {
      state.calibrationMessage =
        `屏幕校准保存失败：${error instanceof Error ? error.message : String(error)}`;
    }
  }

  loadProjectionResolution(state: ProjectionDashboardSettingsState): void {
    if (!state.vehicleDisplayUuid || state.projectionModeOptions.length === 0) {
      state.resolutionSelectionMessage = '建立车机连接后，才能按 /info 显示档案设置分辨率';
      return;
    }
    const savedModeId = readProjectionResolutionPreference(state.vehicleDisplayUuid);
    const selection = resolveProjectionDisplayMode(state.projectionModeOptions, savedModeId);
    state.selectedProjectionModeId = selection.mode.id;
    if (selection.usedNativeFallback) {
      state.resolutionSelectionMessage = `已保存档位 ${savedModeId} 未通过当前 Profile 校验，已恢复原生尺寸`;
      saveProjectionResolutionPreference(state.vehicleDisplayUuid, RECEIVER_NATIVE_MODE_ID);
    } else {
      state.resolutionSelectionMessage = '';
    }
  }

  selectProjectionResolution(state: ProjectionDashboardSettingsState, modeId: string): void {
    const mode = state.projectionModeOptions.find((item: ProjectionDisplayMode): boolean => item.id === modeId);
    if (!mode || !state.vehicleDisplayUuid) {
      state.resolutionSelectionMessage = '该分辨率未在当前车机档案中验证';
      return;
    }
    try {
      saveProjectionResolutionPreference(state.vehicleDisplayUuid, mode.id);
      state.selectedProjectionModeId = mode.id;
      state.resolutionSelectionMessage = mode.id === state.activeProjectionModeId
        ? '所选档位已保存'
        : '所选档位将在下次连接时应用；当前视频流不会被静默改尺寸';
    } catch (error) {
      state.resolutionSelectionMessage =
        `保存分辨率档位失败：${error instanceof Error ? error.message : String(error)}`;
    }
  }
}
