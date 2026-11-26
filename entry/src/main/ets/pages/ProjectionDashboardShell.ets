import { ProjectionApp, isProjectionAppLaunchable, PROJECTION_VEHICLE_APPS } from './ProjectionAppCatalog';
import { ProjectionDockItem } from './ProjectionDock';
import { ProjectionDashboardShellContent } from './ProjectionDashboardShellContent';
import { ProjectionDashboardShellSettingsPage } from './ProjectionDashboardShellSettingsPage';
import { ProjectionDashboardShellLayout } from './ProjectionDashboardShellLayout';
import { ProjectionCalibrationControl, ProjectionDisplayMode, ProjectionSafeInsetEdge, ProjectionSplitPane } from '../video/ProjectionSettings';
import { ProjectionMediaCommand, ProjectionMediaSnapshot } from '../session/MediaSessionBridge';
@Component
export struct ProjectionDashboardShell {
  @Prop theme: string = 'aurora';
  @Prop accent: string = '#0A84FF';
  @Prop dayNightMode: string = 'NIGHT';
  @Prop nightMode: boolean = false;
  @Prop dockPosition: string = 'left';
  @Prop dashboardView: string = 'home';
  @Prop preserveSplitSurfaceForOverlays: boolean = false;
  @Prop settingsTab: string = 'display';
  @Prop activeSettingsDropdown: string = '';
  @Prop displayBrightness: number = 80;
  @Prop splitMapRatio: number = 3;
  @Prop splitMusicRatio: number = 2;
  @Prop splitMapRatioInput: string = '3';
  @Prop splitMusicRatioInput: string = '2';
  @Prop splitRatioMessage: string = '';
  @Prop selectedMapUri: string = '';
  @Prop selectedMusicUri: string = '';
  @Prop apps: ProjectionApp[] = [];
  @Prop appsGridColumns: number = 4;
  @Prop appsGridTemplate: string = '1fr 1fr 1fr 1fr';
  @Prop activeAppLabel: string = '';
  @Prop activeAppUri: string = '';
  @Prop appOnPhone: boolean = false;
  @Prop mapAppLabel: string = '';
  @Prop mapAppUri: string = '';
  @Prop mapOnPhone: boolean = false;
  @Prop navigationPreview: boolean = false;
  @Prop launchMessage: string = '';
  @Prop mapMessage: string = '';
  @Prop mediaState: ProjectionMediaSnapshot = {
    title: '', artist: '', lyric: '', positionMs: 0, durationMs: 0, isPlaying: false, commands: [], queue: [], message: ''
  };
  @Prop dockActionMessage: string = '';
  @Prop dockHint: string = '';
  @Prop batteryPercent: number = 0;
  @Prop signalLevel: number = 0;
  @Prop networkLabel: string = '网络';
  @Prop dockIconSize: number = 30;
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
  @Prop useBluetoothAudio: boolean = false;
  @Prop encoderFps: number = 30;
  @Prop captureFps: number = 60;
  @Prop activeEncoderFps: number = 0;
  @Prop activeCaptureFps: number = 0;
  @Prop receiverHomeMessage: string = '';
  @Prop viewAreaOriginX: number = 0;
  @Prop viewAreaOriginY: number = 0;
  @Prop primaryTextColor: string = '#FFFFFF';
  @Prop secondaryTextColor: string = '#9EFFFFFF';
  @Prop mutedTextColor: string = '#80FFFFFF';
  @Prop mapBackgroundColor: string = '#1D2230';
  @Prop glassStrokeColor: string = '#38FFFFFF';
  @Prop cardStrokeColor: string = '#20FFFFFF';
  @Prop glassSecondaryColor: string = '#14FFFFFF';
  @Prop glassPanelColor: string = '#75262630';
  @Prop glassSurfaceColor: string = '#9E1E1E26';
  @Prop settingsPanelColor: string = '#75262630';
  @Prop settingsGroupColor: string = '#14FFFFFF';
  @Prop settingsSeparatorColor: string = '#1FFFFFFF';
  @Prop lightAppearance: boolean = false;
  @Prop themeBackgroundColor: string = '#10101C';
  @Prop dockItems: ProjectionDockItem[] = [];
  @Prop verticalDock: boolean = false;
  wallpaperResource: (themeId: string) => Resource = (_themeId: string): Resource => $r('app.media.projection_aurora');
  mapPreviewResource: () => Resource = (): Resource => $r('app.media.projection_map_preview');
  dockIconResource: (icon: string, selected: boolean) => Resource = (_icon: string, _selected: boolean): Resource => $r('app.media.ic_house');
  settingsIconResource: (lightIcon: string, darkIcon: string, selected?: boolean) => Resource = (_lightIcon: string, _darkIcon: string, _selected?: boolean): Resource => $r('app.media.ic_car_front');
  onSettingsTabChange: (tab: string) => void = (_tab: string): void => {};
  onDockAction: (id: string, longPress: boolean) => void = (_id: string, _longPress: boolean): void => {};
  onDockHintChange: (hint: string) => void = (_hint: string): void => {};
  onThemeChange: (themeId: string) => void = (_themeId: string): void => {};
  onAccentChange: (color: string) => void = (_color: string): void => {};
  onDockMenuBoundsChange: (area: Area) => void = (_area: Area): void => {};
  onSelectApp: (app: ProjectionApp) => void = (_app: ProjectionApp): void => {};
  onAppSurfaceChange: (surfaceId: string, area: Area | undefined, attached: boolean) => void = (_surfaceId: string, _area: Area | undefined, _attached: boolean): void => {};
  onMapSurfaceChange: (surfaceId: string, area: Area | undefined, attached: boolean) => void = (_surfaceId: string, _area: Area | undefined, _attached: boolean): void => {};
  onTouchAreaChange: (group: string, key: string, area: Area, action: () => void, longPress?: () => void, drag?: (pointX: number) => void) => void = (_group: string, _key: string, _area: Area, _action: () => void, _longPress?: () => void, _drag?: (pointX: number) => void): void => {};
  onTouchBoundsChange: (group: string, area: Area) => void = (_group: string, _area: Area): void => {};
  onToggleAppDisplay: () => void = (): void => {};
  onToggleMapDisplay: () => void = (): void => {};
  onHomeClick: () => void = (): void => {};
  onOpenMediaApp: () => void = (): void => {};
  onOpenMapApp: () => void = (): void => {};
  onSendMediaCommand: (command: ProjectionMediaCommand) => void = (_command: ProjectionMediaCommand): void => {};
  onDayNightModeChange: (mode: 'AUTO' | 'DAY' | 'NIGHT') => void = (_mode: 'AUTO' | 'DAY' | 'NIGHT'): void => {};
  onBrightnessChange: (value: number) => void = (_value: number): void => {};
  onBrightnessTouch: (pointX: number, area: Area) => void = (_pointX: number, _area: Area): void => {};
  onSplitRatioAdjust: (pane: ProjectionSplitPane, delta: number) => void = (_pane: ProjectionSplitPane, _delta: number): void => {};
  onSplitRatioInputChange: (pane: ProjectionSplitPane, value: string) => void = (_pane: ProjectionSplitPane, _value: string): void => {};
  onSplitRatioRestore: (pane: ProjectionSplitPane) => void = (_pane: ProjectionSplitPane): void => {};
  onSplitRatioFocus: (pane: ProjectionSplitPane) => void = (_pane: ProjectionSplitPane): void => {};
  onDockPositionToggle: () => void = (): void => {};
  onSafeInsetAdjust: (edge: ProjectionSafeInsetEdge, delta: number) => void = (_edge: ProjectionSafeInsetEdge, _delta: number): void => {};
  onContentCalibrationAdjust: (control: ProjectionCalibrationControl, delta: number) => void = (_control: ProjectionCalibrationControl, _delta: number): void => {};
  onDropdownToggle: (key: string) => void = (_key: string): void => {};
  onDropdownSelect: (key: string, index: number) => void = (_key: string, _index: number): void => {};
  onProjectionContentAreaChange: (area: Area) => void = (_area: Area): void => {};
  onDockScrollerReady: (scroller: Scroller) => void = (_scroller: Scroller): void => {};
  onAppsScrollerReady: (scroller: Scroller) => void = (_scroller: Scroller): void => {};
  onDockMenuScrollerReady: (scroller: Scroller) => void = (_scroller: Scroller): void => {};
  onSettingsScrollerReady: (scroller: Scroller) => void = (_scroller: Scroller): void => {};
  onThemesScrollerReady: (scroller: Scroller) => void = (_scroller: Scroller): void => {};
  onGridAreaChange: (area: Area) => void = (_area: Area): void => {};
  onViewportAreaChange: (area: Area) => void = (_area: Area): void => {};
  onEncoderFpsSelect: (index: number) => void = (_index: number): void => {};
  onCaptureFpsSelect: (index: number) => void = (_index: number): void => {};
  onBluetoothAudioChange: (enabled: boolean) => void = (_enabled: boolean): void => {};

  @Builder
  private SettingsPage() {
    ProjectionDashboardShellSettingsPage({
      settingsTab: this.settingsTab,
      dayNightMode: this.dayNightMode,
      nightMode: this.nightMode,
      displayBrightness: this.displayBrightness,
      splitMapRatio: this.splitMapRatio,
      splitMusicRatio: this.splitMusicRatio,
      splitMapRatioInput: this.splitMapRatioInput,
      splitMusicRatioInput: this.splitMusicRatioInput,
      splitRatioMessage: this.splitRatioMessage,
      dockPosition: this.dockPosition,
      deviceDisplayUuid: this.deviceDisplayUuid,
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
      settingsPanelColor: this.settingsPanelColor,
      settingsGroupColor: this.settingsGroupColor,
      glassStrokeColor: this.glassStrokeColor,
      settingsSeparatorColor: this.settingsSeparatorColor,
      useBluetoothAudio: this.useBluetoothAudio,
      networkLabel: this.networkLabel,
      signalLevel: this.signalLevel,
      batteryPercent: this.batteryPercent,
      encoderFps: this.encoderFps,
      captureFps: this.captureFps,
      receiverHomeMessage: this.receiverHomeMessage,
      launchMessage: this.launchMessage,
      settingsIconResource: this.settingsIconResource,
      onSettingsTabChange: this.onSettingsTabChange,
      onDayNightModeChange: this.onDayNightModeChange,
      onBrightnessChange: this.onBrightnessChange,
      onBrightnessTouch: this.onBrightnessTouch,
      onSplitRatioAdjust: this.onSplitRatioAdjust,
      onSplitRatioInputChange: this.onSplitRatioInputChange,
      onSplitRatioRestore: this.onSplitRatioRestore,
      onSplitRatioFocus: this.onSplitRatioFocus,
      onDockPositionToggle: this.onDockPositionToggle,
      onSafeInsetAdjust: this.onSafeInsetAdjust,
      onContentCalibrationAdjust: this.onContentCalibrationAdjust,
      onDropdownToggle: this.onDropdownToggle,
      onDropdownSelect: this.onDropdownSelect,
      onBluetoothAudioChange: this.onBluetoothAudioChange,
      onEncoderFpsSelect: this.onEncoderFpsSelect,
      onCaptureFpsSelect: this.onCaptureFpsSelect,
      onTouchAreaChange: this.onTouchAreaChange,
      onProjectionContentAreaChange: this.onProjectionContentAreaChange,
      onSettingsScrollerReady: this.onSettingsScrollerReady,
      onTouchBoundsChange: this.onTouchBoundsChange
    })
  }
  @Builder
  private Content() {
    ProjectionDashboardShellContent({
      dashboardView: this.dashboardView,
      preserveSplitSurfaceForOverlays: this.preserveSplitSurfaceForOverlays,
      activeAppLabel: this.activeAppLabel,
      activeAppUri: this.activeAppUri,
      appOnPhone: this.appOnPhone,
      mapAppLabel: this.mapAppLabel,
      mapAppUri: this.mapAppUri,
      mapOnPhone: this.mapOnPhone,
      navigationPreview: this.navigationPreview,
      launchMessage: this.launchMessage,
      mapMessage: this.mapMessage,
      splitMapRatio: this.splitMapRatio,
      splitMusicRatio: this.splitMusicRatio,
      apps: this.apps,
      selectedMapUri: this.selectedMapUri,
      selectedMusicUri: this.selectedMusicUri,
      mediaState: this.mediaState,
      accent: this.accent,
      primaryTextColor: this.primaryTextColor,
      secondaryTextColor: this.secondaryTextColor,
      glassSecondaryColor: this.glassSecondaryColor,
      glassPanelColor: this.glassPanelColor,
      glassStrokeColor: this.glassStrokeColor,
      cardStrokeColor: this.cardStrokeColor,
      theme: this.theme,
      lightAppearance: this.lightAppearance,
      wallpaperResource: this.wallpaperResource,
      mapPreviewResource: this.mapPreviewResource,
      appsGridColumns: this.appsGridColumns,
      appsGridTemplate: this.appsGridTemplate,
      dockActionMessage: this.dockActionMessage,
      onAppSurfaceChange: this.onAppSurfaceChange,
      onMapSurfaceChange: this.onMapSurfaceChange,
      onTouchAreaChange: this.onTouchAreaChange,
      onTouchBoundsChange: this.onTouchBoundsChange,
      onToggleAppDisplay: this.onToggleAppDisplay,
      onToggleMapDisplay: this.onToggleMapDisplay,
      onOpenMediaApp: this.onOpenMediaApp,
      onOpenMapApp: this.onOpenMapApp,
      onSendMediaCommand: this.onSendMediaCommand,
      onSelectApp: this.onSelectApp,
      onGridAreaChange: this.onGridAreaChange,
      onAppsScrollerReady: this.onAppsScrollerReady,
      settingsPage: this.SettingsPage,
      onThemeChange: this.onThemeChange,
      onAccentChange: this.onAccentChange,
      onThemesScrollerReady: this.onThemesScrollerReady,
      onDockMenuBoundsChange: this.onDockMenuBoundsChange,
      onDockMenuScrollerReady: this.onDockMenuScrollerReady,
      onHomeClick: this.onHomeClick,
      mapBackgroundColor: this.mapBackgroundColor,
      verticalDock: this.verticalDock
    })
  }
  build() {
    ProjectionDashboardShellLayout({
      theme: this.theme,
      wallpaperResource: this.wallpaperResource,
      lightAppearance: this.lightAppearance,
      dockPosition: this.dockPosition,
      safeInsetTop: this.safeInsetTop,
      safeInsetRight: this.safeInsetRight,
      safeInsetBottom: this.safeInsetBottom,
      safeInsetLeft: this.safeInsetLeft,
      contentScalePercent: this.contentScalePercent,
      contentOffsetXPercent: this.contentOffsetXPercent,
      contentOffsetYPercent: this.contentOffsetYPercent,
      themeBackgroundColor: this.themeBackgroundColor,
      displayBrightness: this.displayBrightness,
      dockItems: this.dockItems,
      signalLevel: this.signalLevel,
      networkLabel: this.networkLabel,
      batteryPercent: this.batteryPercent,
      accent: this.accent,
      dockIconSize: this.dockIconSize,
      dockHint: this.dockHint,
      primaryTextColor: this.primaryTextColor,
      secondaryTextColor: this.secondaryTextColor,
      mutedTextColor: this.mutedTextColor,
      glassSurfaceColor: this.glassSurfaceColor,
      glassStrokeColor: this.glassStrokeColor,
      dockIconResource: this.dockIconResource,
      onDockAction: this.onDockAction,
      onDockHintChange: this.onDockHintChange,
      onTouchAreaChange: this.onTouchAreaChange,
      onDockScrollerReady: this.onDockScrollerReady,
      onTouchBoundsChange: this.onTouchBoundsChange,
      onViewportAreaChange: this.onViewportAreaChange,
      content: this.Content
    })
  }
}
