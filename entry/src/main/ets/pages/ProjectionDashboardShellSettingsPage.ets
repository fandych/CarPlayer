import { ProjectionCalibrationControl, ProjectionDisplayMode, ProjectionSafeInsetEdge, ProjectionSplitPane } from '../video/ProjectionSettings';
import { ProjectionConnectionSettingsPane } from './ProjectionConnectionSettingsPane';
import { ProjectionDisplaySettingsPane } from './ProjectionDisplaySettingsPane';

@Component
export struct ProjectionDashboardShellSettingsPage {
  @Prop settingsTab: string = 'display';
  @Prop dayNightMode: string = 'NIGHT';
  @Prop nightMode: boolean = false;
  @Prop displayBrightness: number = 80;
  @Prop splitMapRatio: number = 3;
  @Prop splitMusicRatio: number = 2;
  @Prop splitMapRatioInput: string = '3';
  @Prop splitMusicRatioInput: string = '2';
  @Prop splitRatioMessage: string = '';
  @Prop dockPosition: string = 'left';
  @Prop deviceDisplayUuid: string = '';
  @Prop safeInsetTop: number = 0;
  @Prop safeInsetRight: number = 0;
  @Prop safeInsetBottom: number = 0;
  @Prop safeInsetLeft: number = 0;
  @Prop contentScalePercent: number = 100;
  @Prop contentOffsetXPercent: number = 0;
  @Prop contentOffsetYPercent: number = 0;
  @Prop calibrationMessage: string = '';
  @Prop projectionModeOptions: ProjectionDisplayMode[] = [];
  @Prop selectedProjectionModeId: string = 'receiver-native';
  @Prop activeProjectionModeId: string = '';
  @Prop projectionResolutionMessage: string = '';
  @Prop resolutionSelectionMessage: string = '';
  @Prop projectionNativeWidth: number = 0;
  @Prop projectionNativeHeight: number = 0;
  @Prop activeSettingsDropdown: string = '';
  @Prop accent: string = '#0A84FF';
  @Prop primaryTextColor: string = '#FFFFFF';
  @Prop secondaryTextColor: string = '#9EFFFFFF';
  @Prop mutedTextColor: string = '#80FFFFFF';
  @Prop mapBackgroundColor: string = '#1D2230';
  @Prop glassSecondaryColor: string = '#14FFFFFF';
  @Prop glassPanelColor: string = '#75262630';
  @Prop settingsPanelColor: string = '#75262630';
  @Prop settingsGroupColor: string = '#14FFFFFF';
  @Prop glassStrokeColor: string = '#38FFFFFF';
  @Prop settingsSeparatorColor: string = '#1FFFFFFF';
  @Prop useBluetoothAudio: boolean = false;
  @Prop networkLabel: string = '网络';
  @Prop signalLevel: number = 0;
  @Prop batteryPercent: number = 0;
  @Prop encoderFps: number = 30;
  @Prop captureFps: number = 60;
  @Prop receiverHomeMessage: string = '';
  @Prop launchMessage: string = '';
  settingsIconResource: (lightIcon: string, darkIcon: string, selected?: boolean) => Resource =
    (_lightIcon: string, _darkIcon: string, _selected?: boolean): Resource => $r('app.media.ic_car_front');
  onSettingsTabChange: (tab: string) => void = (_tab: string): void => {};
  onDayNightModeChange: (mode: 'AUTO' | 'DAY' | 'NIGHT') => void =
    (_mode: 'AUTO' | 'DAY' | 'NIGHT'): void => {};
  onBrightnessChange: (value: number) => void = (_value: number): void => {};
  onBrightnessTouch: (pointX: number, area: Area) => void =
    (_pointX: number, _area: Area): void => {};
  onSplitRatioAdjust: (pane: ProjectionSplitPane, delta: number) => void =
    (_pane: ProjectionSplitPane, _delta: number): void => {};
  onSplitRatioInputChange: (pane: ProjectionSplitPane, value: string) => void =
    (_pane: ProjectionSplitPane, _value: string): void => {};
  onSplitRatioRestore: (pane: ProjectionSplitPane) => void = (_pane: ProjectionSplitPane): void => {};
  onSplitRatioFocus: (pane: ProjectionSplitPane) => void = (_pane: ProjectionSplitPane): void => {};
  onDockPositionToggle: () => void = (): void => {};
  onSafeInsetAdjust: (edge: ProjectionSafeInsetEdge, delta: number) => void =
    (_edge: ProjectionSafeInsetEdge, _delta: number): void => {};
  onContentCalibrationAdjust: (control: ProjectionCalibrationControl, delta: number) => void =
    (_control: ProjectionCalibrationControl, _delta: number): void => {};
  onDropdownToggle: (key: string) => void = (_key: string): void => {};
  onDropdownSelect: (key: string, index: number) => void = (_key: string, _index: number): void => {};
  onBluetoothAudioChange: (enabled: boolean) => void = (_enabled: boolean): void => {};
  onEncoderFpsSelect: (index: number) => void = (_index: number): void => {};
  onCaptureFpsSelect: (index: number) => void = (_index: number): void => {};
  onTouchAreaChange: (
    group: string, key: string, area: Area, action: () => void, longPress?: () => void,
    drag?: (pointX: number) => void
  ) => void = (_group: string, _key: string, _area: Area, _action: () => void,
    _longPress?: () => void, _drag?: (pointX: number) => void): void => {};
  onProjectionContentAreaChange: (area: Area) => void = (_area: Area): void => {};
  onSettingsScrollerReady: (scroller: Scroller) => void = (_scroller: Scroller): void => {};
  onTouchBoundsChange: (group: string, area: Area) => void =
    (_group: string, _area: Area): void => {};

  build() {
    Row({ space: 12 }) {
      Column({ space: 10 }) {
        Text('设置').fontSize(30).fontWeight(FontWeight.Bold).fontColor(this.primaryTextColor)
          .width('100%').padding({ left: 10, bottom: 8 })
        Button({ type: ButtonType.Normal }) {
          Row({ space: 12 }) {
            Image(this.settingsIconResource(
              'app.media.ic_day_night_light', 'app.media.ic_day_night', this.settingsTab === 'display'
            )).width(30).height(30).objectFit(ImageFit.Contain)
            Text('显示').fontSize(16)
              .fontColor(this.settingsTab === 'display' ? '#FFFFFF' : this.primaryTextColor)
              .layoutWeight(1)
          }
          .width('100%')
        }
        .width('100%').height(58).padding({ left: 12, right: 12 }).borderRadius(14)
        .backgroundColor(this.settingsTab === 'display' ? `#D9${this.accent.slice(1)}` : Color.Transparent)
        .onClick((): void => this.onSettingsTabChange('display'))
        .accessibilityText('显示设置')
        .onAreaChange((_oldArea, newArea) => this.onTouchAreaChange(
          'settings', 'tab-display', newArea, (): void => this.onSettingsTabChange('display')))
        Button({ type: ButtonType.Normal }) {
          Row({ space: 12 }) {
            Image(this.settingsIconResource(
              'app.media.ic_car_front_light', 'app.media.ic_car_front', this.settingsTab === 'connect'
            )).width(30).height(30).objectFit(ImageFit.Contain)
            Text('连接').fontSize(16)
              .fontColor(this.settingsTab === 'connect' ? '#FFFFFF' : this.primaryTextColor)
              .layoutWeight(1)
          }
          .width('100%')
        }
        .width('100%').height(58).padding({ left: 12, right: 12 }).borderRadius(14)
        .backgroundColor(this.settingsTab === 'connect' ? `#D9${this.accent.slice(1)}` : Color.Transparent)
        .onClick((): void => this.onSettingsTabChange('connect'))
        .accessibilityText('连接设置')
        .onAreaChange((_oldArea, newArea) => this.onTouchAreaChange(
          'settings', 'tab-connect', newArea, (): void => this.onSettingsTabChange('connect')))
      }
      .width('25%').constraintSize({ minWidth: 180, maxWidth: 270 }).height('100%')
      .padding(16).borderRadius(22)
      .backgroundColor(this.settingsGroupColor)
      .border({ width: { right: 1 }, color: this.settingsSeparatorColor })
      if (this.settingsTab === 'display') {
        ProjectionDisplaySettingsPane({
          dayNightMode: this.dayNightMode,
          nightMode: this.nightMode,
          displayBrightness: this.displayBrightness,
          splitMapRatio: this.splitMapRatio,
          splitMusicRatio: this.splitMusicRatio,
          splitMapRatioInput: this.splitMapRatioInput,
          splitMusicRatioInput: this.splitMusicRatioInput,
          splitRatioMessage: this.splitRatioMessage,
          dockPosition: this.dockPosition,
          vehicleDisplayUuid: this.deviceDisplayUuid,
          safeInsetTop: this.safeInsetTop,
          safeInsetRight: this.safeInsetRight,
          safeInsetBottom: this.safeInsetBottom,
          safeInsetLeft: this.safeInsetLeft,
          contentScalePercent: this.contentScalePercent,
          contentOffsetXPercent: this.contentOffsetXPercent,
          contentOffsetYPercent: this.contentOffsetYPercent,
          calibrationMessage: this.calibrationMessage,
          projectionModeOptions: this.projectionModeOptions,
          selectedProjectionModeId: this.selectedProjectionModeId,
          activeProjectionModeId: this.activeProjectionModeId,
          projectionResolutionMessage: this.projectionResolutionMessage,
          resolutionSelectionMessage: this.resolutionSelectionMessage,
          projectionNativeWidth: this.projectionNativeWidth,
          projectionNativeHeight: this.projectionNativeHeight,
          activeSettingsDropdown: this.activeSettingsDropdown,
          accent: this.accent,
          primaryTextColor: this.primaryTextColor,
          secondaryTextColor: this.secondaryTextColor,
          mutedTextColor: this.mutedTextColor,
          mapBackgroundColor: this.mapBackgroundColor,
          glassSecondaryColor: this.glassSecondaryColor,
          glassPanelColor: this.glassPanelColor,
          glassGroupColor: this.settingsGroupColor,
          glassStrokeColor: this.glassStrokeColor,
          settingsSeparatorColor: this.settingsSeparatorColor,
          onDayNightModeChange: (mode: 'AUTO' | 'DAY' | 'NIGHT'): void => this.onDayNightModeChange(mode),
          onBrightnessChange: (value: number): void => this.onBrightnessChange(value),
          onBrightnessTouch: (pointX: number, area: Area): void => this.onBrightnessTouch(pointX, area),
          onSplitRatioAdjust: (pane: ProjectionSplitPane, delta: number): void =>
            this.onSplitRatioAdjust(pane, delta),
          onSplitRatioInputChange: (pane: ProjectionSplitPane, value: string): void =>
            this.onSplitRatioInputChange(pane, value),
          onSplitRatioRestore: (pane: ProjectionSplitPane): void => this.onSplitRatioRestore(pane),
          onSplitRatioFocus: (pane: ProjectionSplitPane): void => this.onSplitRatioFocus(pane),
          onDockPositionToggle: (): void => this.onDockPositionToggle(),
          onSafeInsetAdjust: (edge: ProjectionSafeInsetEdge, delta: number): void =>
            this.onSafeInsetAdjust(edge, delta),
          onContentCalibrationAdjust: (control: ProjectionCalibrationControl, delta: number): void =>
            this.onContentCalibrationAdjust(control, delta),
          onDropdownToggle: (key: string): void => this.onDropdownToggle(key),
          onDropdownSelect: (key: string, index: number): void => this.onDropdownSelect(key, index),
          onTouchAreaChange: (
            key: string, area: Area, action: () => void, longPress?: () => void, drag?: (pointX: number) => void
          ): void => this.onTouchAreaChange('settings', key, area, action, longPress, drag),
          onContentAreaChange: (area: Area): void => this.onProjectionContentAreaChange(area),
          onScrollerReady: (scroller: Scroller): void => this.onSettingsScrollerReady(scroller)
        })
      } else {
        ProjectionConnectionSettingsPane({
          useBluetoothAudio: this.useBluetoothAudio,
          networkLabel: this.networkLabel,
          signalLevel: this.signalLevel,
          batteryPercent: this.batteryPercent,
          encoderFps: this.encoderFps,
          captureFps: this.captureFps,
          activeSettingsDropdown: this.activeSettingsDropdown,
          receiverHomeMessage: this.receiverHomeMessage,
          launchMessage: this.launchMessage,
          accent: this.accent,
          primaryTextColor: this.primaryTextColor,
          secondaryTextColor: this.secondaryTextColor,
          mutedTextColor: this.mutedTextColor,
          glassSecondaryColor: this.glassSecondaryColor,
          glassPanelColor: this.glassPanelColor,
          glassGroupColor: this.settingsGroupColor,
          glassStrokeColor: this.glassStrokeColor,
          settingsSeparatorColor: this.settingsSeparatorColor,
          settingsIconResource: (lightIcon: string, darkIcon: string, selected: boolean = false): Resource =>
            this.settingsIconResource(lightIcon, darkIcon, selected),
          onBluetoothAudioChange: (enabled: boolean): void => this.onBluetoothAudioChange(enabled),
          onSelectEncoderFps: (index: number): void => this.onEncoderFpsSelect(index),
          onSelectCaptureFps: (index: number): void => this.onCaptureFpsSelect(index),
          onDropdownToggle: (key: string): void => this.onDropdownToggle(key),
          onDropdownSelect: (key: string, index: number): void => this.onDropdownSelect(key, index),
          onTouchAreaChange: (key: string, area: Area, action: () => void): void =>
            this.onTouchAreaChange('settings', key, area, action),
          onContentAreaChange: (area: Area): void => this.onProjectionContentAreaChange(area),
          onScrollerReady: (scroller: Scroller): void => this.onSettingsScrollerReady(scroller)
        })
      }
    }
    .width('100%').height('100%')
    .padding(10)
    .backgroundColor(this.settingsPanelColor)
    .border({ width: 1, color: this.glassStrokeColor })
    .borderRadius(28)
    .clip(true)
    .onAreaChange((_oldArea, newArea) => this.onTouchBoundsChange('settings', newArea))
  }
}
