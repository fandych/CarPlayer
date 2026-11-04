import { ProjectionApp, isProjectionAppLaunchable, PROJECTION_VEHICLE_APPS } from './ProjectionAppCatalog';
import { ProjectionAppIcon, ProjectionAppsPage } from './ProjectionAppsPage';
import { ProjectionBatteryIndicator, ProjectionDock, ProjectionDockItem, ProjectionSignalIndicator } from './ProjectionDock';
import { ProjectionDashboardContent } from './ProjectionDashboardContent';
import { ProjectionDockMenu } from './ProjectionDockMenu';
import { ProjectionThemesPage } from './ProjectionThemesPage';
import { ProjectionDisplaySettingsPane } from './ProjectionDisplaySettingsPane';
import { ProjectionConnectionSettingsPane } from './ProjectionConnectionSettingsPane';
import {
  ProjectionCalibrationControl,
  ProjectionDisplayMode,
  ProjectionSafeInsetEdge,
  ProjectionSplitPane
} from '../video/ProjectionSettings';
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
    title: '',
    artist: '',
    lyric: '',
    positionMs: 0,
    durationMs: 0,
    isPlaying: false,
    commands: [],
    queue: [],
    message: ''
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
  wallpaperResource: (themeId: string) => Resource = (_themeId: string): Resource =>
    $r('app.media.projection_aurora');
  mapPreviewResource: () => Resource = (): Resource => $r('app.media.projection_map_preview');
  dockIconResource: (icon: string, selected: boolean) => Resource =
    (_icon: string, _selected: boolean): Resource => $r('app.media.ic_house');
  settingsIconResource: (lightIcon: string, darkIcon: string, selected?: boolean) => Resource =
    (_lightIcon: string, _darkIcon: string, _selected?: boolean): Resource => $r('app.media.ic_car_front');
  onSettingsTabChange: (tab: string) => void = (_tab: string): void => {};
  onDockAction: (id: string, longPress: boolean) => void = (_id: string, _longPress: boolean): void => {};
  onDockHintChange: (hint: string) => void = (_hint: string): void => {};
  onThemeChange: (themeId: string) => void = (_themeId: string): void => {};
  onAccentChange: (color: string) => void = (_color: string): void => {};
  onDockMenuBoundsChange: (area: Area) => void = (_area: Area): void => {};
  onSelectApp: (app: ProjectionApp) => void = (_app: ProjectionApp): void => {};
  onAppSurfaceChange: (surfaceId: string, area: Area | undefined, attached: boolean) => void =
    (_surfaceId: string, _area: Area | undefined, _attached: boolean): void => {};
  onMapSurfaceChange: (surfaceId: string, area: Area | undefined, attached: boolean) => void =
    (_surfaceId: string, _area: Area | undefined, _attached: boolean): void => {};
  onTouchAreaChange: (
    group: string, key: string, area: Area, action: () => void, longPress?: () => void,
    drag?: (pointX: number) => void
  ) => void = (_group: string, _key: string, _area: Area, _action: () => void,
    _longPress?: () => void, _drag?: (pointX: number) => void): void => {};
  onTouchBoundsChange: (group: string, area: Area) => void =
    (_group: string, _area: Area): void => {};
  onToggleAppDisplay: () => void = (): void => {};
  onToggleMapDisplay: () => void = (): void => {};
  onHomeClick: () => void = (): void => {};
  onOpenMediaApp: () => void = (): void => {};
  onOpenMapApp: () => void = (): void => {};
  onSendMediaCommand: (command: ProjectionMediaCommand) => void = (_command: ProjectionMediaCommand): void => {};
  onDayNightModeChange: (mode: 'AUTO' | 'DAY' | 'NIGHT') => void = (_mode: 'AUTO' | 'DAY' | 'NIGHT'): void => {};
  onBrightnessChange: (value: number) => void = (_value: number): void => {};
  onBrightnessTouch: (pointX: number, area: Area) => void = (_pointX: number, _area: Area): void => {};
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
  private DockPanel(vertical: boolean) {
    ProjectionDock({
      vertical: vertical,
      items: this.dockItems,
      signalLevel: this.signalLevel,
      networkLabel: this.networkLabel,
      batteryPercent: this.batteryPercent,
      accent: this.accent,
      dockIconSize: this.dockIconSize,
      dockHint: this.dockHint,
      primaryTextColor: this.primaryTextColor,
      secondaryTextColor: this.secondaryTextColor,
      mutedTextColor: this.mutedTextColor,
      surfaceColor: this.glassSurfaceColor,
      strokeColor: this.glassStrokeColor,
      onAction: (id: string, longPress: boolean): void => this.onDockAction(id, longPress),
      onHintChange: (hint: string): void => this.onDockHintChange(hint),
      iconResource: (icon: string, selected: boolean): Resource => this.dockIconResource(icon, selected),
      onTouchAreaChange: (
        key: string, area: Area, action: () => void, longPress?: () => void
      ): void => this.onTouchAreaChange('dock', key, area, action, longPress),
      onScrollerReady: (scroller: Scroller): void => this.onDockScrollerReady(scroller),
      onBoundsChange: (area: Area): void => this.onTouchBoundsChange('dock', area)
    })
  }

  @Builder
  private SettingsPage() {
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

  @Builder
  private Content() {
    Stack({ alignContent: Alignment.TopStart }) {
      ProjectionDashboardContent({
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
        verticalDock: this.verticalDock,
        wallpaperResource: (themeId: string): Resource => this.wallpaperResource(themeId),
        mapPreviewResource: (): Resource => this.mapPreviewResource(),
        onAppSurfaceChange: (surfaceId: string, area: Area | undefined, attached: boolean): void =>
          this.onAppSurfaceChange(surfaceId, area, attached),
        onMapSurfaceChange: (surfaceId: string, area: Area | undefined, attached: boolean): void =>
          this.onMapSurfaceChange(surfaceId, area, attached),
        onTouchAreaChange: (
          group: string, key: string, area: Area, action: () => void, longPress?: () => void,
          drag?: (pointX: number) => void
        ): void => this.onTouchAreaChange(group, key, area, action, longPress, drag),
        onTouchBoundsChange: (group: string, area: Area): void => this.onTouchBoundsChange(group, area),
        onToggleAppDisplay: (): void => this.onToggleAppDisplay(),
        onToggleMapDisplay: (): void => this.onToggleMapDisplay(),
        onOpenMediaApp: (): void => this.onOpenMediaApp(),
        onOpenMapApp: (): void => this.onOpenMapApp(),
        onSendMediaCommand: (command: ProjectionMediaCommand): void => this.onSendMediaCommand(command)
      })
      if (this.dashboardView === 'apps') {
        ProjectionAppsPage({
          apps: this.visibleApps(),
          gridColumns: this.appsGridColumns,
          gridTemplate: this.appsGridTemplate,
          panelColor: this.glassPanelColor,
          panelStrokeColor: this.glassStrokeColor,
          primaryTextColor: this.primaryTextColor,
          secondaryTextColor: this.secondaryTextColor,
          accent: this.accent,
          onAppClick: (app: ProjectionApp): void => this.onSelectApp(app),
          onTouchAreaChange: (key: string, area: Area, action: () => void): void =>
            this.onTouchAreaChange('grid', key, area, action),
          onGridAreaChange: (area: Area): void => this.onGridAreaChange(area),
          onScrollerReady: (scroller: Scroller): void => this.onAppsScrollerReady(scroller)
        })
      } else if (this.dashboardView === 'settings') {
        this.SettingsPage()
      } else if (this.dashboardView === 'themes') {
        ProjectionThemesPage({
          theme: this.theme,
          accent: this.accent,
          primaryTextColor: this.primaryTextColor,
          secondaryTextColor: this.secondaryTextColor,
          mapBackgroundColor: this.mapBackgroundColor,
          panelColor: this.glassPanelColor,
          strokeColor: this.glassStrokeColor,
          wallpaperResource: (themeId: string): Resource => this.wallpaperResource(themeId),
          onThemeChange: (themeId: string): void => this.onThemeChange(themeId),
          onAccentChange: (color: string): void => this.onAccentChange(color),
          onTouchAreaChange: (key: string, area: Area, action: () => void): void =>
            this.onTouchAreaChange('themes', key, area, action),
          onScrollerReady: (scroller: Scroller): void => this.onThemesScrollerReady(scroller),
          onBoundsChange: (area: Area): void => this.onTouchBoundsChange('themes', area)
        })
      } else if (this.dashboardView === 'maps' || this.dashboardView === 'music') {
        ProjectionDockMenu({
          dashboardView: this.dashboardView,
          apps: this.apps,
          selectedMapUri: this.selectedMapUri,
          selectedMusicUri: this.selectedMusicUri,
          mediaBundleName: this.mediaState.bundleName ?? '',
          activeAppLabel: this.activeAppLabel,
          activeAppUri: this.activeAppUri,
          activeAppOnPhone: this.appOnPhone,
          mapAppLabel: this.mapAppLabel,
          mapAppUri: this.mapAppUri,
          mapOnPhone: this.mapOnPhone,
          dockActionMessage: this.dockActionMessage,
          accent: this.accent,
          primaryTextColor: this.primaryTextColor,
          secondaryTextColor: this.secondaryTextColor,
          glassSecondaryColor: this.glassSecondaryColor,
          glassPanelColor: this.glassPanelColor,
          glassStrokeColor: this.glassStrokeColor,
          cardStrokeColor: this.cardStrokeColor,
          onHome: (): void => this.onHomeClick(),
          onSelectApp: (app: ProjectionApp): void => this.onSelectApp(app),
          onToggleAppDisplay: (): void => this.onToggleAppDisplay(),
          onToggleMapDisplay: (): void => this.onToggleMapDisplay(),
          onTouchAreaChange: (group: string, key: string, area: Area, action: () => void): void =>
            this.onTouchAreaChange(group, key, area, action),
          onBoundsChange: (area: Area): void => this.onDockMenuBoundsChange(area),
          onScrollerReady: (scroller: Scroller): void => this.onDockMenuScrollerReady(scroller)
        })
      }
    }
    .layoutWeight(1)
    .width(this.verticalDock ? '0%' : '100%')
    .height(this.verticalDock ? '100%' : '0%')
  }

  private visibleApps(): ProjectionApp[] {
    const visible: ProjectionApp[] = [...PROJECTION_VEHICLE_APPS];
    for (const app of this.apps) {
      if (isProjectionAppLaunchable(app)) {
        visible.push(app);
      }
    }
    return visible;
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Image(this.wallpaperResource(this.theme))
        .width('100%').height('100%').objectFit(ImageFit.Cover)
      if (this.lightAppearance) {
        Column().width('100%').height('100%').backgroundColor('#6BFFFFFF')
      }
      if (this.dockPosition === 'bottom') {
        Column({ space: 8 }) {
          this.Content()
          this.DockPanel(false)
        }
        .width('100%').height('100%')
        .padding({
          top: `${this.safeInsetTop}%`, right: `${this.safeInsetRight}%`,
          bottom: `${this.safeInsetBottom}%`, left: `${this.safeInsetLeft}%`
        })
        .scale({ x: this.contentScalePercent / 100, y: this.contentScalePercent / 100 })
        .translate({ x: `${this.contentOffsetXPercent}%`, y: `${this.contentOffsetYPercent}%` })
      } else {
        Row({ space: 8 }) {
          this.DockPanel(true)
          this.Content()
        }
        .width('100%').height('100%')
        .padding({
          top: `${this.safeInsetTop}%`, right: `${this.safeInsetRight}%`,
          bottom: `${this.safeInsetBottom}%`, left: `${this.safeInsetLeft}%`
        })
        .scale({ x: this.contentScalePercent / 100, y: this.contentScalePercent / 100 })
        .translate({ x: `${this.contentOffsetXPercent}%`, y: `${this.contentOffsetYPercent}%` })
      }
    }
    .width('100%').height('100%').padding(8).clip(true)
    .backgroundColor(this.themeBackgroundColor)
    .brightness(0.5 + this.displayBrightness / 200)
    .onAreaChange((_oldArea, newArea) => this.onViewportAreaChange(newArea))
  }
}
