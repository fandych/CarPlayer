import batteryInfo from '@ohos.batteryInfo';
import { hilog } from '@kit.PerformanceAnalysisKit';
import bundleManager from '@ohos.bundle.bundleManager';
import promptAction from '@ohos.promptAction';
import radio from '@ohos.telephony.radio';
import emitter from '@ohos.events.emitter';
import common from '@ohos.app.ability.common';
import {
  CARPLAY_TOUCH_REPORT_EVENT, CARPLAY_TOUCH_TAP_EVENT, CarPlayTouchReport, CarPlayTouchTap
} from '../video/CarPlayTouchInput';
import {
  ProjectionApp,
  activeProjectionMusicApp,
  findLaunchableProjectionApp,
  isProjectionAppLaunchable,
  PROJECTION_MAP_URI,
  PROJECTION_VEHICLE_APPS,
  projectionAppCatalog,
  resolveProjectionApps
} from './ProjectionAppCatalog';
import { ProjectionDockItem } from './ProjectionDock';
import { ProjectionBounds, ProjectionPoint, ProjectionTouchRouter } from './ProjectionTouchRouter';
import { ProjectionMapSurface } from './ProjectionSurface';
import { ProjectionDashboardSettingsController } from './ProjectionDashboardSettingsController';
import {
  EMPTY_PROJECTION_MEDIA,
  ProjectionMediaCommand,
  ProjectionMediaSnapshot
} from '../session/MediaSessionBridge';
import { ProjectionMediaCoordinator } from './ProjectionMediaCoordinator';
import { ProjectionDashboardShell } from './ProjectionDashboardShell';
import {
  initializeProjectionSettings,
  projectionTheme,
  ProjectionCalibrationControl,
  ProjectionDisplayMode,
  ProjectionSafeInsetEdge,
  ProjectionSplitPane,
  resolveNightMode,
  RECEIVER_NATIVE_MODE_ID
} from '../video/ProjectionSettings';

export { ProjectionMapSurface } from './ProjectionSurface';

const DOMAIN: number = 0xCA22;
let projectionAppDiscovery: Promise<ProjectionApp[]> | undefined = undefined;

const HOME_APP: ProjectionApp = {
  appId: 'shell-home',
  uri: 'carplay-client://v1/shell/home',
  launchState: 'VERIFIED',
  label: '首页',
  mark: 'C',
  color: '#0A84FF',
  category: 'home'
};

export function discoverProjectionApps(refresh: boolean = false): Promise<ProjectionApp[]> {
  if (projectionAppDiscovery && !refresh) {
    return projectionAppDiscovery;
  }
  projectionAppDiscovery = resolveProjectionApps(
    (uri: string): boolean => bundleManager.canOpenLink(uri)
  ).catch((error: Error): never => {
    projectionAppDiscovery = undefined;
    throw error;
  });
  return projectionAppDiscovery;
}

@Component
export struct ProjectionDashboard {
  onAppClick: (app: ProjectionApp) => void = (_app: ProjectionApp): void => {};
  onHomeClick: () => void = (): void => {};
  onBackClick: () => void = (): void => {};
  onReceiverHomeClick: () => void = (): void => {};
  onMediaLog: (message: string) => void = (_message: string): void => {};
  onAppSurfaceChange: (surface: ProjectionMapSurface | undefined) => void =
    (_surface: ProjectionMapSurface | undefined): void => {};
  onMapSurfaceChange: (surface: ProjectionMapSurface | undefined) => void =
    (_surface: ProjectionMapSurface | undefined): void => {};
  @Prop activeAppLabel: string = '';
  @Prop activeAppUri: string = '';
  @Prop appOnPhone: boolean = false;
  @Prop mapAppLabel: string = '';
  @Prop mapAppUri: string = '';
  @Prop mapOnPhone: boolean = false;
  @Prop viewAreaOriginX: number = 0;
  @Prop viewAreaOriginY: number = 0;
  onToggleAppDisplay: () => void = (): void => {};
  @StorageLink('carplayNavigationPreview') navigationPreview: boolean = false;
  @Prop launchMessage: string = '';
  @Prop mapMessage: string = '正在准备地图画面';
  onToggleMapDisplay: () => void = (): void => {};
  @State apps: ProjectionApp[] = [];
  @State appsGridColumns: number = 4;
  @State dashboardView: string = 'home';
  @State settingsTab: string = 'display';
  @State activeSettingsDropdown: string = '';
  @State displayBrightness: number = 80;
  @State splitMapRatio: number = 3;
  @State splitMusicRatio: number = 2;
  @State splitMapRatioInput: string = '3';
  @State splitMusicRatioInput: string = '2';
  @State splitRatioMessage: string = '';
  @State private preserveSplitSurfaceForOverlays: boolean = false;
  @State selectedMapUri: string = '';
  @State selectedMusicUri: string = '';
  @State dockIconSize: number = 30;
  @StorageLink('carplayNightMode') nightMode: boolean = false;
  @StorageLink('carplayDayNightMode') dayNightMode: string = 'NIGHT';
  @StorageLink('carplayDockPosition') dockPosition: string = 'left';
  @StorageLink('carplayVehicleDisplayUuid') vehicleDisplayUuid: string = '';
  @StorageLink('carplayProjectionDisplayModes') projectionModeOptions: ProjectionDisplayMode[] = [];
  @StorageLink('carplayProjectionNativeWidth') projectionNativeWidth: number = 0;
  @StorageLink('carplayProjectionNativeHeight') projectionNativeHeight: number = 0;
  @StorageLink('carplayProjectionActiveModeId') activeProjectionModeId: string = '';
  @StorageLink('carplayProjectionResolutionMessage') projectionResolutionMessage: string = '';
  @State safeInsetTop: number = 0;
  @State safeInsetRight: number = 0;
  @State safeInsetBottom: number = 0;
  @State safeInsetLeft: number = 0;
  @State contentScalePercent: number = 100;
  @State contentOffsetXPercent: number = 0;
  @State contentOffsetYPercent: number = 0;
  @State calibrationMessage: string = '';
  @State selectedProjectionModeId: string = RECEIVER_NATIVE_MODE_ID;
  @State resolutionSelectionMessage: string = '';
  @StorageLink('carplayTheme') theme: string = 'aurora';
  @StorageLink('carplayAccent') accent: string = '#0A84FF';
  @StorageLink('carplayEncoderFps') encoderFps: number = 30;
  @StorageLink('carplayCaptureFps') captureFps: number = 60;
  @StorageLink('carplayUseBluetoothAudio') useBluetoothAudio: boolean = false;
  @StorageLink('carplayActiveEncoderFps') activeEncoderFps: number = 0;
  @StorageLink('carplayActiveCaptureFps') activeCaptureFps: number = 0;
  @State dockHint: string = '';
  @StorageLink('carplayReceiverHomeMessage') receiverHomeMessage: string = '';
  @State batteryPercent: number = 0;
  @State signalLevel: number = 0;
  @State networkLabel: string = '网络';
  @State appDiscoveryMessage: string = '正在读取可启动应用';
  @State dockActionMessage: string = '';
  @State mediaState: ProjectionMediaSnapshot = {
    title: EMPTY_PROJECTION_MEDIA.title,
    artist: EMPTY_PROJECTION_MEDIA.artist,
    lyric: EMPTY_PROJECTION_MEDIA.lyric,
    positionMs: EMPTY_PROJECTION_MEDIA.positionMs,
    durationMs: EMPTY_PROJECTION_MEDIA.durationMs,
    isPlaying: EMPTY_PROJECTION_MEDIA.isPlaying,
    commands: [],
    queue: [],
    message: EMPTY_PROJECTION_MEDIA.message
  };
  @State mediaActionMessage: string = '';
  private statusTimer: number = -1;
  private mediaCoordinator?: ProjectionMediaCoordinator;
  private appSurfaceId: string = '';
  private appSurfaceArea?: Area;
  private mapSurfaceId: string = '';
  private mapSurfaceLoaded: boolean = false;
  private mapSurfaceArea?: Area;
  private lastMapSurface: ProjectionMapSurface | undefined = undefined;
  private readonly touchRouter: ProjectionTouchRouter = new ProjectionTouchRouter();
  private readonly settingsController: ProjectionDashboardSettingsController =
    new ProjectionDashboardSettingsController();
  private dockScroller: Scroller = new Scroller();
  private appsScroller: Scroller = new Scroller();
  private dockMenuScroller: Scroller = new Scroller();
  private settingsScroller: Scroller = new Scroller();
  private themesScroller: Scroller = new Scroller();
  private readonly sidebarMediaScroller: Scroller = new Scroller();
  private projectionViewportWidth: number = 0;
  private projectionViewportHeight: number = 0;
  private readonly touchHandler = (event: emitter.GenericEventData<CarPlayTouchTap>): void => {
    this.touchRouter.handleTap(
      event.data,
      AppStorage.get<boolean>('carplayProjectionHomeActive') === true,
      AppStorage.get<number>('carplayProjectionDisplayId') ?? -1,
      this.dashboardView,
      this.activeAppLabel,
      this.navigationPreview,
      (x: number, y: number): ProjectionPoint => this.canvasPixelToContentPoint(x, y)
    );
  };

  private readonly touchReportHandler = (event: emitter.GenericEventData<CarPlayTouchReport>): void => {
    this.handleTouchReport(event.data);
  };

  private scrollControllerAt(x: number, y: number): Scroller | undefined {
    const emptyBounds: ProjectionBounds = { left: 0, top: 0, right: 0, bottom: 0 };
    if (this.touchRouter.contains(this.touchRouter.touchBounds.get('dock') ?? emptyBounds, x, y)) {
      return this.dockScroller;
    }
    if (this.dashboardView === 'apps' &&
      this.touchRouter.contains(this.touchRouter.touchBounds.get('grid') ?? emptyBounds, x, y)) {
      return this.appsScroller;
    }
    if ((this.dashboardView === 'maps' || this.dashboardView === 'music') &&
      this.touchRouter.contains(this.touchRouter.touchBounds.get(this.dashboardView) ?? emptyBounds, x, y)) {
      return this.dockMenuScroller;
    }
    if (this.dashboardView === 'settings' &&
      this.touchRouter.contains(this.touchRouter.touchBounds.get('settingsContent') ?? emptyBounds, x, y)) {
      return this.settingsScroller;
    }
    if (this.dashboardView === 'themes' &&
      this.touchRouter.contains(this.touchRouter.touchBounds.get('themes') ?? emptyBounds, x, y)) {
      return this.themesScroller;
    }
    if (this.navigationPreview &&
      this.touchRouter.contains(this.touchRouter.touchBounds.get('media') ?? emptyBounds, x, y)) {
      return this.sidebarMediaScroller;
    }
    return undefined;
  }

  private handleTouchReport(report: CarPlayTouchReport | undefined): void {
    this.touchRouter.handleReport(
      report,
      AppStorage.get<boolean>('carplayProjectionHomeActive') === true,
      AppStorage.get<number>('carplayProjectionDisplayId') ?? -1,
      this.dashboardView,
      (x: number, y: number): ProjectionPoint => this.canvasPixelToContentPoint(x, y),
      (x: number, y: number): Scroller | undefined => this.scrollControllerAt(x, y)
    );
  }

  aboutToAppear(): void {
    initializeProjectionSettings();
    this.settingsController.normalizeEncoderFps(this);
    this.settingsController.loadSafeInsets(this);
    this.settingsController.loadContentCalibration(this);
    this.settingsController.loadSplitRatios(this);
    this.settingsController.loadProjectionResolution(this);
    AppStorage.setOrCreate('carplayDashboardView', 'home');
    emitter.on<CarPlayTouchTap>(CARPLAY_TOUCH_TAP_EVENT, this.touchHandler);
    emitter.on<CarPlayTouchReport>(CARPLAY_TOUCH_REPORT_EVENT, this.touchReportHandler);
    void this.discoverApps().catch((error: Error): void => {
      this.apps = projectionAppCatalog([]);
      this.appDiscoveryMessage = `应用入口核验失败：${error.message}`;
      hilog.error(DOMAIN, 'CarPlayerProjection', '%{public}s', this.appDiscoveryMessage);
    });
    void this.startMediaSessionBridge();
    void this.refreshDeviceStatus();
    this.statusTimer = setInterval((): void => {
      void this.refreshDeviceStatus();
    }, 30000);
  }

  aboutToDisappear(): void {
    emitter.off<CarPlayTouchTap>(CARPLAY_TOUCH_TAP_EVENT, this.touchHandler);
    emitter.off<CarPlayTouchReport>(CARPLAY_TOUCH_REPORT_EVENT, this.touchReportHandler);
    this.touchRouter.resetScrollState();
    this.onMapSurfaceChange(undefined);
    this.onAppSurfaceChange(undefined);
    this.touchRouter.touchAreas.clear();
    this.touchRouter.touchBounds.clear();
    if (this.statusTimer >= 0) {
      clearInterval(this.statusTimer);
      this.statusTimer = -1;
    }
    const mediaCoordinator = this.mediaCoordinator;
    this.mediaCoordinator = undefined;
    if (mediaCoordinator) {
      void mediaCoordinator.close().catch((error: Error): void => {
        hilog.error(DOMAIN, 'CarPlayerMedia', '媒体控制器释放失败：%{public}s', error.message);
      });
    }
  }

  private handleAppSurfaceChange(surfaceId: string, area: Area | undefined, attached: boolean): void {
    if (!attached) {
      this.appSurfaceId = '';
      this.appSurfaceArea = undefined;
      this.onAppSurfaceChange(undefined);
      return;
    }
    this.appSurfaceId = surfaceId;
    this.appSurfaceArea = area;
    const ui = this.getUIContext();
    if (!area || !surfaceId) {
      return;
    }
    const surface: ProjectionMapSurface = {
      surfaceId,
      left: Math.round(ui.vp2px(Number.parseFloat(`${area.globalPosition.x}`))),
      top: Math.round(ui.vp2px(Number.parseFloat(`${area.globalPosition.y}`))),
      width: Math.round(ui.vp2px(Number.parseFloat(`${area.width}`))),
      height: Math.round(ui.vp2px(Number.parseFloat(`${area.height}`)))
    };
    if (surface.width > 0 && surface.height > 0) {
      this.onAppSurfaceChange(surface);
    }
  }

  private handleMapSurfaceChange(surfaceId: string, area: Area | undefined, attached: boolean): void {
    if (!attached) {
      this.mapSurfaceLoaded = false;
      this.mapSurfaceId = '';
      this.mapSurfaceArea = undefined;
      this.lastMapSurface = undefined;
      this.onMapSurfaceChange(undefined);
      return;
    }
    this.mapSurfaceLoaded = true;
    this.mapSurfaceId = surfaceId;
    this.mapSurfaceArea = area;
    const ui = this.getUIContext();
    if (!surfaceId || !area ||
      Number.parseFloat(`${area.width}`) <= 0 || Number.parseFloat(`${area.height}`) <= 0) {
      return;
    }
    const surface: ProjectionMapSurface = {
      surfaceId,
      left: Math.round(ui.vp2px(Number.parseFloat(`${area.globalPosition.x}`))),
      top: Math.round(ui.vp2px(Number.parseFloat(`${area.globalPosition.y}`))),
      width: Math.round(ui.vp2px(Number.parseFloat(`${area.width}`))),
      height: Math.round(ui.vp2px(Number.parseFloat(`${area.height}`)))
    };
    if (surface.width <= 0 || surface.height <= 0) {
      return;
    }
    const previous = this.lastMapSurface;
    if (previous && previous.surfaceId === surface.surfaceId && previous.left === surface.left &&
      previous.top === surface.top && previous.width === surface.width && previous.height === surface.height) {
      return;
    }
    this.lastMapSurface = surface;
    this.onMapSurfaceChange(surface);
  }

  private areaBounds(area: Area): ProjectionBounds {
    const left = Number.parseFloat(`${area.globalPosition.x}`);
    const top = Number.parseFloat(`${area.globalPosition.y}`);
    return {
      left,
      top,
      right: left + Number.parseFloat(`${area.width}`),
      bottom: top + Number.parseFloat(`${area.height}`)
    };
  }

  private updateTouchArea(group: string, key: string, area: Area, action: () => void,
    longPress?: () => void, drag?: (pointX: number) => void): void {
    this.touchRouter.updateTouchArea(group, key, area, action, longPress, drag);
  }

  private selectApp(app: ProjectionApp): void {
    if (app.category === 'vehicle') {
      if (app.view === 'receiver') {
        this.receiverHomeMessage = '正在请求车机主页';
        this.onReceiverHomeClick();
        return;
      }
      this.showDashboardView(app.view ?? 'settings');
      return;
    }
    const keepSplitLayout = this.dashboardView === 'split' && app.category === 'music';
    if (app.category !== 'home' && !isProjectionAppLaunchable(app)) {
      this.appDiscoveryMessage = app.unavailableReason ?? `${app.label} 的启动入口尚未验证`;
      this.mediaActionMessage = this.appDiscoveryMessage;
      this.showDockActionMessage(this.appDiscoveryMessage);
      return;
    }
    this.dockActionMessage = '';
    this.preserveSplitSurfaceForOverlays = false;
    if (app.category === 'map') {
      this.selectedMapUri = app.uri;
      AppStorage.setOrCreate('carplaySelectedMapAppId', app.appId);
    } else if (app.category === 'music') {
      this.selectedMusicUri = app.uri;
    }
    this.dashboardView = keepSplitLayout ? 'split' : 'home';
    AppStorage.setOrCreate('carplayDashboardView', this.dashboardView);
    if (app.uri === HOME_APP.uri) {
      this.showHome();
    } else {
      this.setNavigationPreview(false);
      this.onAppClick(app);
    }
  }

  private showHome(): void {
    this.setNavigationPreview(true);
    const mapUri = this.selectedMapUri || PROJECTION_MAP_URI;
    if (this.activeAppUri === mapUri && this.activeAppLabel.length > 0) {
      return;
    }
    const map = this.apps.find((app: ProjectionApp): boolean => app.uri === mapUri);
    if (map && isProjectionAppLaunchable(map)) {
      this.onAppClick(map);
    } else {
      if (map) {
        this.appDiscoveryMessage = map.unavailableReason ?? `${map.label} 的启动入口尚未验证`;
      }
      this.onHomeClick();
    }
  }

  private setNavigationPreview(preview: boolean): void {
    this.navigationPreview = preview;
    AppStorage.setOrCreate('carplayNavigationPreview', preview);
  }

  private showDashboardView(view: string): void {
    if (view === 'split' && !this.activeMusicApp()) {
      const message = this.appOnPhone
        ? '请先将音乐 app 切回车机屏幕，再进入分屏'
        : '请先从音乐 Dock 打开音乐 app，再进入分屏';
      this.mediaActionMessage = message;
      this.showDockActionMessage(message);
      return;
    }
    this.dockActionMessage = '';
    if (view === 'split' || view === 'home') {
      this.preserveSplitSurfaceForOverlays = false;
    } else if (this.dashboardView === 'split' &&
      (AppStorage.get<number>('carplayEmbeddedMapDisplayId') ?? -1) > 0) {
      this.preserveSplitSurfaceForOverlays = true;
    }
    this.touchRouter.touchBounds.delete('grid');
    this.touchRouter.touchBounds.delete('media');
    this.dashboardView = view;
    AppStorage.setOrCreate('carplayDashboardView', view);
    if (view === 'split') {
      this.setNavigationPreview(false);
    }
  }

  private async discoverApps(refresh: boolean = true): Promise<void> {
    const installed = await discoverProjectionApps(refresh);
    this.apps = projectionAppCatalog(installed);
    const savedMapId = AppStorage.get<string>('carplaySelectedMapAppId');
    const selectedMap = this.apps.find((app: ProjectionApp): boolean =>
      app.appId === savedMapId && app.category === 'map');
    this.selectedMapUri = selectedMap?.uri ?? PROJECTION_MAP_URI;
    if (!savedMapId) {
      AppStorage.setOrCreate('carplaySelectedMapAppId', 'amap');
    }
    const launchableCount = installed.filter((app: ProjectionApp): boolean =>
      isProjectionAppLaunchable(app)).length;
    this.appDiscoveryMessage = launchableCount > 0
      ? `${launchableCount} 个入口通过本机能力核验；目标屏实际显示仍需车机验证`
      : '未核验到可用入口；检查应用安装、querySchemes 与旧源码 URI 入口';
    if (this.activeAppLabel.length === 0) {
      this.showHome();
    }
  }

  private async startMediaSessionBridge(): Promise<void> {
    const coordinator = new ProjectionMediaCoordinator({
      getContext: (): common.UIAbilityContext =>
        this.getUIContext().getHostContext() as common.UIAbilityContext,
      getSnapshot: (): ProjectionMediaSnapshot => this.mediaState,
      onSnapshot: (snapshot: ProjectionMediaSnapshot): void => { this.mediaState = snapshot; },
      getApps: (): ProjectionApp[] => this.apps,
      onAppsChanged: (apps: ProjectionApp[]): void => { this.apps = apps; },
      onActionMessage: (message: string): void => { this.mediaActionMessage = message; },
      onLog: (message: string): void => this.onMediaLog(message)
    });
    this.mediaCoordinator = coordinator;
    await coordinator.start();
  }

  private async sendMediaCommand(command: ProjectionMediaCommand): Promise<void> {
    await this.mediaCoordinator?.send(command);
  }
  private openMediaApp(): void {
    const bundleName = this.mediaState.bundleName;
    const activeMediaApp = bundleName
      ? findLaunchableProjectionApp(this.apps, 'music', undefined, bundleName)
      : undefined;
    const app = activeMediaApp ?? this.launchableCategoryApp('music');
    if (app) {
      this.selectApp(app);
    } else {
      this.showDashboardView('music');
      this.showDockActionMessage('当前音乐应用没有已验证的启动入口；请选择可用音乐 app');
    }
  }

  private openMapApp(): void {
    const app = this.launchableCategoryApp('map');
    if (app) {
      this.selectApp(app);
    } else {
      this.showDashboardView('maps');
      this.showDockActionMessage('所选导航 app 没有可用启动入口；请选择已验证的地图 app');
    }
  }

  private isDashboardHome(): boolean {
    return this.dashboardView === 'home' && (this.navigationPreview || this.activeAppLabel.length === 0);
  }

  private activeAppHasCategory(category: 'map' | 'music'): boolean {
    return this.dashboardView === 'home' && !this.navigationPreview && this.activeAppUri.length > 0 &&
      this.apps.some((app: ProjectionApp): boolean =>
        app.uri === this.activeAppUri && app.category === category);
  }

  private isDockItemSelected(id: string): boolean {
    if (id === 'home') {
      return this.isDashboardHome();
    }
    if (id === 'apps' || id === 'split' || id === 'settings') {
      return this.dashboardView === id;
    }
    if (id === 'map') {
      return this.dashboardView === 'maps' || this.activeAppHasCategory('map');
    }
    if (id === 'music') {
      return this.dashboardView === 'music' || this.activeAppHasCategory('music');
    }
    return false;
  }

  private dockItems(): ProjectionDockItem[] {
    return [
      { id: 'home', label: '首页', icon: 'app.media.ic_house', selected: this.isDockItemSelected('home') },
      { id: 'apps', label: '应用', icon: 'app.media.ic_layout_grid', selected: this.isDockItemSelected('apps') },
      { id: 'map', label: '地图', icon: 'app.media.ic_navigation', selected: this.isDockItemSelected('map') },
      { id: 'music', label: '音乐', icon: 'app.media.ic_music', selected: this.isDockItemSelected('music') },
      { id: 'split', label: '分屏', icon: 'app.media.ic_split', selected: this.isDockItemSelected('split') },
      { id: 'settings', label: '设置', icon: 'app.media.ic_settings', selected: this.isDockItemSelected('settings') }
    ];
  }

  private toggleDockPosition(): void {
    this.dockPosition = this.dockPosition === 'bottom' ? 'left' : 'bottom';
  }

  private isLightAppearance(): boolean {
    return !resolveNightMode(this.dayNightMode, this.nightMode);
  }

  private colorWithAlpha(color: string, alpha: string): string {
    return `#${alpha}${color.slice(1)}`;
  }

  private primaryTextColor(): string {
    return this.isLightAppearance() ? '#1C1C1E' : '#FFFFFF';
  }

  private secondaryTextColor(): string {
    return this.isLightAppearance() ? '#A63C3C43' : '#9EFFFFFF';
  }

  private mutedTextColor(): string {
    return this.isLightAppearance() ? '#993C3C43' : '#80FFFFFF';
  }

  private mapBackgroundColor(): string {
    return this.isLightAppearance() ? '#E9E7E1' : '#1D2230';
  }

  private glassStrokeColor(): string {
    return this.isLightAppearance() ? '#BFFFFFFF' : '#38FFFFFF';
  }

  private cardStrokeColor(): string {
    return this.isLightAppearance() ? '#243C3C43' : '#20FFFFFF';
  }

  private glassSecondaryColor(): string {
    return this.isLightAppearance() ? '#0D000000' : '#14FFFFFF';
  }

  private glassPanelColor(): string {
    return this.isLightAppearance() ? '#85FFFFFF' : this.colorWithAlpha(projectionTheme(this.theme).surface, '75');
  }

  private glassSurfaceColor(): string {
    return this.isLightAppearance() ? '#B8FFFFFF' : this.colorWithAlpha(projectionTheme(this.theme).panel, '9E');
  }

  private settingsPanelColor(): string {
    return this.glassPanelColor();
  }

  private settingsGroupColor(): string {
    return this.glassSecondaryColor();
  }

  private settingsSeparatorColor(): string {
    return this.isLightAppearance() ? '#243C3C43' : '#1FFFFFFF';
  }

  private wallpaperResource(themeId: string): Resource {
    switch (themeId) {
      case 'sunset':
        return $r('app.media.projection_sunset');
      case 'forest':
        return $r('app.media.projection_forest');
      case 'ocean':
        return $r('app.media.projection_ocean');
      case 'graphite':
        return $r('app.media.projection_graphite');
      default:
        return $r('app.media.projection_aurora');
    }
  }

  private mapPreviewResource(): Resource {
    return this.isLightAppearance()
      ? $r('app.media.projection_map_preview_light') : $r('app.media.projection_map_preview');
  }

  private dockIconResource(icon: string, selected: boolean): Resource {
    if (!this.isLightAppearance() || selected) {
      return $r(icon);
    }
    switch (icon) {
      case 'app.media.ic_house':
        return $r('app.media.ic_house_light');
      case 'app.media.ic_layout_grid':
        return $r('app.media.ic_layout_grid_light');
      case 'app.media.ic_navigation':
        return $r('app.media.ic_navigation_light');
      case 'app.media.ic_music':
        return $r('app.media.ic_music_light');
      case 'app.media.ic_split':
        return $r('app.media.ic_split_light');
      case 'app.media.ic_settings':
        return $r('app.media.ic_settings_light');
      default:
        return $r(icon);
    }
  }

  private settingsIconResource(lightIcon: string, darkIcon: string, selected: boolean = false): Resource {
    return this.isLightAppearance() && !selected ? $r(lightIcon) : $r(darkIcon);
  }

  private toggleSettingsDropdown(key: string): void {
    const previousKey = this.activeSettingsDropdown;
    this.activeSettingsDropdown = previousKey === key ? '' : key;
    if (previousKey.length > 0) {
      this.clearSettingsDropdownAreas(previousKey);
    }
  }

  private closeSettingsDropdown(key: string): void {
    if (this.activeSettingsDropdown === key) {
      this.activeSettingsDropdown = '';
    }
    this.clearSettingsDropdownAreas(key);
  }

  private clearSettingsDropdownAreas(key: string): void {
    const prefix = `settings:dropdown-${key}-option-`;
    for (const areaKey of this.touchRouter.touchAreas.keys()) {
      if (areaKey.startsWith(prefix)) {
        this.touchRouter.touchAreas.delete(areaKey);
      }
    }
  }

  private chooseSettingsDropdownOption(key: string, index: number, onSelect: (index: number) => void): void {
    onSelect(index);
    this.closeSettingsDropdown(key);
  }

  private setDisplayBrightnessFromTouch(pointX: number, bounds: ProjectionBounds): void {
    const width = bounds.right - bounds.left;
    if (width <= 0) {
      return;
    }
    const position = Math.max(0, Math.min(1, (pointX - bounds.left) / width));
    this.settingsController.updateDisplayBrightness(this, 20 + position * 80);
  }

  private screenToContentPoint(x: number, y: number): ProjectionPoint {
    const scale = this.contentScalePercent / 100;
    if (scale <= 0 || this.projectionViewportWidth <= 0 || this.projectionViewportHeight <= 0) {
      return { x, y };
    }
    const centerX = this.projectionViewportWidth / 2;
    const centerY = this.projectionViewportHeight / 2;
    const offsetX = this.projectionViewportWidth * this.contentOffsetXPercent / 100;
    const offsetY = this.projectionViewportHeight * this.contentOffsetYPercent / 100;
    return {
      x: (x - centerX - offsetX) / scale + centerX,
      y: (y - centerY - offsetY) / scale + centerY
    };
  }

  private canvasPixelToContentPoint(x: number, y: number): ProjectionPoint {
    const ui = this.getUIContext();
    const originX = ui.px2vp(this.viewAreaOriginX);
    const originY = ui.px2vp(this.viewAreaOriginY);
    const content = this.screenToContentPoint(ui.px2vp(x) - originX, ui.px2vp(y) - originY);
    return { x: content.x + originX, y: content.y + originY };
  }

  private categoryApp(category: string): ProjectionApp | undefined {
    const selected = category === 'map' ? this.selectedMapUri : this.selectedMusicUri;
    return this.apps.find((app: ProjectionApp): boolean => app.category === category && app.uri === selected) ??
      this.apps.find((app: ProjectionApp): boolean => app.category === category &&
        (category === 'map' ? app.uri === PROJECTION_MAP_URI : app.bundleName === this.mediaState.bundleName)) ??
      this.apps.find((app: ProjectionApp): boolean => app.category === category);
  }

  private launchableCategoryApp(category: string): ProjectionApp | undefined {
    const selectedUri = category === 'map' ? this.selectedMapUri : this.selectedMusicUri;
    const selected = this.apps.find((app: ProjectionApp): boolean =>
      app.category === category && app.uri === selectedUri);
    if (selected) {
      return isProjectionAppLaunchable(selected) ? selected : undefined;
    }
    if (category === 'music' && this.mediaState.bundleName) {
      const mediaApp = this.apps.find((app: ProjectionApp): boolean =>
        app.category === category && app.bundleName === this.mediaState.bundleName);
      if (mediaApp) {
        return isProjectionAppLaunchable(mediaApp) ? mediaApp : undefined;
      }
    }
    return findLaunchableProjectionApp(this.apps, category === 'map' ? 'map' : 'music');
  }

  private activeMusicApp(): ProjectionApp | undefined {
    return this.appOnPhone ? undefined : activeProjectionMusicApp(this.apps, this.activeAppUri);
  }

  private formatMediaTime(positionMs: number): string {
    const totalSeconds = Math.floor(Math.max(0, positionMs) / 1000);
    const minutes = Math.floor(totalSeconds / 60);
    const seconds = `${totalSeconds % 60}`.padStart(2, '0');
    return `${minutes}:${seconds}`;
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

  private updateAppsGridColumns(width: number): void {
    const columns = width < 360 ? 3 : width < 480 ? 4 : width < 640 ? 5 : 6;
    if (columns !== this.appsGridColumns) {
      this.appsGridColumns = columns;
    }
  }

  private appsGridTemplate(): string {
    if (this.appsGridColumns === 3) {
      return '1fr 1fr 1fr';
    }
    if (this.appsGridColumns === 5) {
      return '1fr 1fr 1fr 1fr 1fr';
    }
    if (this.appsGridColumns === 6) {
      return '1fr 1fr 1fr 1fr 1fr 1fr';
    }
    return '1fr 1fr 1fr 1fr';
  }

  private activateDock(id: string, longPress: boolean = false): void {
    if (id === 'home') {
      this.selectApp(HOME_APP);
    } else if (id === 'apps') {
      this.showDashboardView('apps');
    } else if (id === 'settings') {
      this.showDashboardView('settings');
    } else if (id === 'split') {
      this.showDashboardView('split');
    } else if (id === 'map' || id === 'music') {
      const app = this.launchableCategoryApp(id);
      if (longPress || !app) {
        this.showDashboardView(id === 'map' ? 'maps' : 'music');
        if (!longPress && !app) {
          this.showDockActionMessage(id === 'map'
            ? '没有已验证的地图启动入口，请从导航列表中选择'
            : '没有已验证的音乐启动入口，请从音乐列表中选择');
        }
      } else {
        this.selectApp(app);
      }
    }
  }

  private showDockActionMessage(message: string): void {
    this.dockActionMessage = message;
    try {
      promptAction.showToast({ message });
    } catch (error) {
      hilog.warn(DOMAIN, 'CarPlayerProjection', '提示显示失败：%{public}s',
        error instanceof Error ? error.message : String(error));
    }
  }

  private async playQueueItem(itemId: number): Promise<void> {
    await this.mediaCoordinator?.playQueueItem(itemId);
  }

  private async refreshDeviceStatus(): Promise<void> {
    this.batteryPercent = Math.max(0, Math.min(100, Math.round(batteryInfo.batterySOC)));
    try {
      const slotId = await radio.getPrimarySlotId();
      const signalInfo = await radio.getSignalInformation(slotId);
      let level = 0;
      for (const item of signalInfo) {
        level = Math.max(level, item.signalLevel);
      }
      this.signalLevel = Math.max(0, Math.min(4, Math.round(level)));
      this.networkLabel = signalInfo.length > 0 ? '移动网络' : '无信号';
    } catch (_error) {
      this.signalLevel = 0;
      this.networkLabel = '网络不可用';
    }
  }

  build() {
    ProjectionDashboardShell({
      theme: this.theme,
      accent: this.accent,
      dayNightMode: this.dayNightMode,
      nightMode: this.nightMode,
      dockPosition: this.dockPosition,
      dashboardView: this.dashboardView,
      preserveSplitSurfaceForOverlays: this.preserveSplitSurfaceForOverlays,
      settingsTab: this.settingsTab,
      activeSettingsDropdown: this.activeSettingsDropdown,
      displayBrightness: this.displayBrightness,
      splitMapRatio: this.splitMapRatio,
      splitMusicRatio: this.splitMusicRatio,
      splitMapRatioInput: this.splitMapRatioInput,
      splitMusicRatioInput: this.splitMusicRatioInput,
      splitRatioMessage: this.splitRatioMessage,
      selectedMapUri: this.selectedMapUri,
      selectedMusicUri: this.selectedMusicUri,
      apps: this.apps,
      appsGridColumns: this.appsGridColumns,
      appsGridTemplate: this.appsGridTemplate(),
      activeAppLabel: this.activeAppLabel,
      activeAppUri: this.activeAppUri,
      appOnPhone: this.appOnPhone,
      mapAppLabel: this.mapAppLabel,
      mapAppUri: this.mapAppUri,
      mapOnPhone: this.mapOnPhone,
      navigationPreview: this.navigationPreview,
      launchMessage: this.launchMessage,
      mapMessage: this.mapMessage,
      mediaState: this.mediaState,
      dockActionMessage: this.dockActionMessage,
      dockHint: this.dockHint,
      batteryPercent: this.batteryPercent,
      signalLevel: this.signalLevel,
      networkLabel: this.networkLabel,
      dockIconSize: this.dockIconSize,
      deviceDisplayUuid: this.vehicleDisplayUuid,
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
      useBluetoothAudio: this.useBluetoothAudio,
      encoderFps: this.encoderFps,
      captureFps: this.captureFps,
      activeEncoderFps: this.activeEncoderFps,
      activeCaptureFps: this.activeCaptureFps,
      receiverHomeMessage: this.receiverHomeMessage,
      viewAreaOriginX: this.viewAreaOriginX,
      viewAreaOriginY: this.viewAreaOriginY,
      primaryTextColor: this.primaryTextColor(),
      secondaryTextColor: this.secondaryTextColor(),
      mutedTextColor: this.mutedTextColor(),
      mapBackgroundColor: this.mapBackgroundColor(),
      glassStrokeColor: this.glassStrokeColor(),
      cardStrokeColor: this.cardStrokeColor(),
      glassSecondaryColor: this.glassSecondaryColor(),
      glassPanelColor: this.glassPanelColor(),
      glassSurfaceColor: this.glassSurfaceColor(),
      settingsPanelColor: this.settingsPanelColor(),
      settingsGroupColor: this.settingsGroupColor(),
      settingsSeparatorColor: this.settingsSeparatorColor(),
      lightAppearance: this.isLightAppearance(),
      themeBackgroundColor: projectionTheme(this.theme).background,
      dockItems: this.dockItems(),
      verticalDock: this.dockPosition !== 'bottom',
      wallpaperResource: (themeId: string): Resource => this.wallpaperResource(themeId),
      mapPreviewResource: (): Resource => this.mapPreviewResource(),
      dockIconResource: (icon: string, selected: boolean): Resource => this.dockIconResource(icon, selected),
      settingsIconResource: (lightIcon: string, darkIcon: string, selected: boolean = false): Resource =>
        this.settingsIconResource(lightIcon, darkIcon, selected),
      onSettingsTabChange: (tab: string): void => { this.settingsTab = tab; },
      onDockAction: (id: string, longPress: boolean): void => this.activateDock(id, longPress),
      onDockHintChange: (hint: string): void => { this.dockHint = hint; },
      onThemeChange: (themeId: string): void => { this.theme = themeId; },
      onAccentChange: (color: string): void => { this.accent = color; },
      onDockMenuBoundsChange: (area: Area): void => {
        const bounds = this.areaBounds(area);
        this.touchRouter.touchBounds.set('maps', bounds);
        this.touchRouter.touchBounds.set('music', bounds);
      },
      onSelectApp: (app: ProjectionApp): void => this.selectApp(app),
      onAppSurfaceChange: (surfaceId: string, area: Area | undefined, attached: boolean): void =>
        this.handleAppSurfaceChange(surfaceId, area, attached),
      onMapSurfaceChange: (surfaceId: string, area: Area | undefined, attached: boolean): void =>
        this.handleMapSurfaceChange(surfaceId, area, attached),
      onTouchAreaChange: (
        group: string, key: string, area: Area, action: () => void, longPress?: () => void,
        drag?: (pointX: number) => void
      ): void => this.updateTouchArea(group, key, area, action, longPress, drag),
      onTouchBoundsChange: (group: string, area: Area): void => {
        this.touchRouter.touchBounds.set(group, this.areaBounds(area));
      },
      onToggleAppDisplay: (): void => this.onToggleAppDisplay(),
      onToggleMapDisplay: (): void => this.onToggleMapDisplay(),
      onHomeClick: (): void => this.showDashboardView('home'),
      onOpenMediaApp: (): void => this.openMediaApp(),
      onOpenMapApp: (): void => this.openMapApp(),
      onSendMediaCommand: (command: ProjectionMediaCommand): void => { void this.sendMediaCommand(command); },
      onDayNightModeChange: (mode: 'AUTO' | 'DAY' | 'NIGHT'): void =>
        this.settingsController.selectDayNightMode(this, mode),
      onBrightnessChange: (value: number): void => this.settingsController.updateDisplayBrightness(this, value),
      onBrightnessTouch: (pointX: number, area: Area): void =>
        this.setDisplayBrightnessFromTouch(pointX, this.areaBounds(area)),
      onSplitRatioAdjust: (pane: ProjectionSplitPane, delta: number): void =>
        this.settingsController.adjustSplitRatio(this, pane, delta),
      onSplitRatioInputChange: (pane: ProjectionSplitPane, value: string): void =>
        this.settingsController.updateSplitRatioInput(this, pane, value),
      onSplitRatioRestore: (pane: ProjectionSplitPane): void =>
        this.settingsController.restoreSplitRatioInput(this, pane),
      onSplitRatioFocus: (pane: ProjectionSplitPane): void =>
        this.getUIContext().getFocusController().requestFocus(
          pane === 'map' ? 'projectionMapSplitRatio' : 'projectionMusicSplitRatio'),
      onDockPositionToggle: (): void => this.toggleDockPosition(),
      onSafeInsetAdjust: (edge: ProjectionSafeInsetEdge, delta: number): void =>
        this.settingsController.adjustSafeInset(this, edge, delta),
      onContentCalibrationAdjust: (control: ProjectionCalibrationControl, delta: number): void =>
        this.settingsController.adjustContentCalibration(this, control, delta),
      onDropdownToggle: (key: string): void => this.toggleSettingsDropdown(key),
      onDropdownSelect: (key: string, index: number): void => this.chooseSettingsDropdownOption(
        key, index, (selectedIndex: number): void => {
          if (key === 'projectionResolution') {
            const mode = this.projectionModeOptions[selectedIndex];
            if (mode) {
              this.settingsController.selectProjectionResolution(this, mode.id);
            }
          } else if (key === 'encoderFps') {
            this.settingsController.selectEncoderFps(this, selectedIndex);
          } else {
            this.settingsController.selectCaptureFps(this, selectedIndex);
          }
        }),
      onProjectionContentAreaChange: (area: Area): void => {
        this.touchRouter.touchBounds.set('settingsContent', this.areaBounds(area));
      },
      onDockScrollerReady: (scroller: Scroller): void => { this.dockScroller = scroller; },
      onAppsScrollerReady: (scroller: Scroller): void => { this.appsScroller = scroller; },
      onDockMenuScrollerReady: (scroller: Scroller): void => { this.dockMenuScroller = scroller; },
      onSettingsScrollerReady: (scroller: Scroller): void => { this.settingsScroller = scroller; },
      onThemesScrollerReady: (scroller: Scroller): void => { this.themesScroller = scroller; },
      onGridAreaChange: (area: Area): void => {
        this.touchRouter.touchBounds.set('grid', this.areaBounds(area));
        this.updateAppsGridColumns(Number.parseFloat(`${area.width}`));
      },
      onViewportAreaChange: (area: Area): void => {
        const height = Number.parseFloat(`${area.height}`);
        this.projectionViewportWidth = Math.max(0, Number.parseFloat(`${area.width}`) - 16);
        this.projectionViewportHeight = Math.max(0, height - 16);
        this.dockIconSize = this.dockPosition === 'bottom'
          ? Math.max(18, Math.min(30, height / 20))
          : Math.max(16, Math.min(30, (height - 100) / 5));
      },
      onEncoderFpsSelect: (index: number): void => this.settingsController.selectEncoderFps(this, index),
      onCaptureFpsSelect: (index: number): void => this.settingsController.selectCaptureFps(this, index),
      onBluetoothAudioChange: (enabled: boolean): void => { this.useBluetoothAudio = enabled; }
    })
  }
}