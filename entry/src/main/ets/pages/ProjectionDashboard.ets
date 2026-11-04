import batteryInfo from '@ohos.batteryInfo';
import { hilog } from '@kit.PerformanceAnalysisKit';
import bundleManager from '@ohos.bundle.bundleManager';
import promptAction from '@ohos.promptAction';
import radio from '@ohos.telephony.radio';
import emitter from '@ohos.events.emitter';
import abilityAccessCtrl from '@ohos.abilityAccessCtrl';
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
  resolveProjectionApps,
  includeMediaSessionApp
} from './ProjectionAppCatalog';
import {
  EMPTY_PROJECTION_MEDIA,
  MediaSessionBridge,
  ProjectionMediaCommand,
  ProjectionMediaSnapshot,
  ProjectionQueueItem
} from '../session/MediaSessionBridge';
import {
  initializeProjectionSettings, projectionTheme, PROJECTION_THEMES, PROJECTION_ACCENTS,
  ProjectionCalibrationControl, ProjectionContentCalibration, ProjectionDisplayMode, ProjectionTheme,
  ProjectionSafeInsetEdge, normalizeSafeInset, projectionSafeInsetKey,
  readProjectionContentCalibration, readProjectionResolutionPreference, resolveNightMode,
  readProjectionSplitRatio, resolveProjectionDisplayMode, saveProjectionContentCalibration,
  saveProjectionResolutionPreference, saveProjectionSplitRatio, ProjectionSplitPane,
  RECEIVER_NATIVE_MODE_ID
} from '../video/ProjectionSettings';

const DOMAIN: number = 0xCA22;
let projectionAppDiscovery: Promise<ProjectionApp[]> | undefined = undefined;

export interface ProjectionMapSurface {
  surfaceId: string;
  left: number;
  top: number;
  width: number;
  height: number;
}

interface ProjectionBounds {
  left: number;
  top: number;
  right: number;
  bottom: number;
}

interface ProjectionPoint {
  x: number;
  y: number;
}

interface ProjectionTouchScrollState {
  displayId: number;
  contactId: number;
  startX: number;
  startY: number;
  lastX: number;
  lastY: number;
  scroller?: Scroller;
  drag?: (pointX: number) => void;
}

interface ProjectionTouchArea extends ProjectionBounds {
  group: string;
  action: () => void;
  longPress?: () => void;
  drag?: (pointX: number) => void;
}

interface OptimisticPlaybackState {
  isPlaying: boolean;
  expiresAt: number;
}

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
  private mediaTimer: number = -1;
  private mediaSessionBridge?: MediaSessionBridge;
  private mediaCommandGeneration: number = 0;
  private optimisticPlaybackState?: OptimisticPlaybackState;
  private lastLoggedMediaSignature: string = '';
  private readonly mapXComponentController: XComponentController = new XComponentController();
  private readonly appXComponentController: XComponentController = new XComponentController();
  private appSurfaceId: string = '';
  private appSurfaceArea?: Area;
  private mapSurfaceId: string = '';
  private mapSurfaceLoaded: boolean = false;
  private mapSurfaceArea?: Area;
  private lastMapSurface: ProjectionMapSurface | undefined = undefined;
  private readonly touchAreas: Map<string, ProjectionTouchArea> = new Map();
  private readonly touchBounds: Map<string, ProjectionBounds> = new Map();
  private readonly dockScroller: Scroller = new Scroller();
  private readonly appsScroller: Scroller = new Scroller();
  private readonly dockMenuScroller: Scroller = new Scroller();
  private readonly settingsScroller: Scroller = new Scroller();
  private readonly themesScroller: Scroller = new Scroller();
  private readonly sidebarMediaScroller: Scroller = new Scroller();
  private touchScrollState?: ProjectionTouchScrollState;
  private projectionViewportWidth: number = 0;
  private projectionViewportHeight: number = 0;
  private readonly touchHandler = (event: emitter.GenericEventData<CarPlayTouchTap>): void => {
    const tap = event.data;
    if (!tap || AppStorage.get<boolean>('carplayProjectionHomeActive') !== true ||
      AppStorage.get<number>('carplayProjectionDisplayId') !== tap.displayId) {
      return;
    }
    const start = this.canvasPixelToContentPoint(tap.startX, tap.startY);
    const end = this.canvasPixelToContentPoint(tap.endX, tap.endY);
    const startX = start.x;
    const startY = start.y;
    const endX = end.x;
    const endY = end.y;
    if (Math.hypot(endX - startX, endY - startY) > 20) {
      return;
    }
    const pointX = (startX + endX) / 2;
    const pointY = (startY + endY) / 2;
    const dock = this.touchBounds.get('dock');
    if (dock && (this.contains(dock, startX, startY) || this.contains(dock, endX, endY))) {
      if (this.contains(dock, pointX, pointY)) {
        for (const area of this.touchAreas.values()) {
          if (area.group === 'dock' && this.contains(area, pointX, pointY)) {
            if ((tap.durationMs ?? 0) >= 550) {
              area.longPress?.();
            } else {
              if (area.drag) {
                area.drag(pointX);
              } else {
                area.action();
              }
            }
            return;
          }
        }
      }
      return;
    }
    for (const area of this.touchAreas.values()) {
      if (area.group === 'dock' ||
        ((area.group === 'media' || area.group === 'map') &&
          (this.dashboardView !== 'home' || (this.activeAppLabel.length > 0 && !this.navigationPreview))) ||
        (area.group === 'grid' && this.dashboardView !== 'apps') ||
        (area.group === 'preview' && (this.dashboardView !== 'home' || !this.navigationPreview)) ||
        (area.group === 'maps' && this.dashboardView !== 'maps') ||
        (area.group === 'music' && this.dashboardView !== 'music') ||
        (area.group === 'settings' && this.dashboardView !== 'settings') ||
        (area.group === 'themes' && this.dashboardView !== 'themes')) {
        continue;
      }
      const bounds = this.touchBounds.get(area.group);
      if (bounds && this.contains(area, pointX, pointY) && this.contains(bounds, pointX, pointY)) {
        if (area.drag) {
          area.drag(pointX);
        } else {
          area.action();
        }
        return;
      }
    }
  };

  private readonly touchReportHandler = (event: emitter.GenericEventData<CarPlayTouchReport>): void => {
    this.handleTouchReport(event.data);
  };

  private scrollControllerAt(x: number, y: number): Scroller | undefined {
    const emptyBounds: ProjectionBounds = { left: 0, top: 0, right: 0, bottom: 0 };
    if (this.contains(this.touchBounds.get('dock') ?? emptyBounds, x, y)) {
      return this.dockScroller;
    }
    if (this.dashboardView === 'apps' && this.contains(this.touchBounds.get('grid') ?? emptyBounds, x, y)) {
      return this.appsScroller;
    }
    if ((this.dashboardView === 'maps' || this.dashboardView === 'music') &&
      this.contains(this.touchBounds.get(this.dashboardView) ?? emptyBounds, x, y)) {
      return this.dockMenuScroller;
    }
    if (this.dashboardView === 'settings' &&
      this.contains(this.touchBounds.get('settingsContent') ?? emptyBounds, x, y)) {
      return this.settingsScroller;
    }
    if (this.dashboardView === 'themes' && this.contains(this.touchBounds.get('themes') ?? emptyBounds, x, y)) {
      return this.themesScroller;
    }
    if (this.navigationPreview && this.contains(this.touchBounds.get('media') ?? emptyBounds, x, y)) {
      return this.sidebarMediaScroller;
    }
    return undefined;
  }

  private handleTouchReport(report: CarPlayTouchReport | undefined): void {
    if (!report || AppStorage.get<boolean>('carplayProjectionHomeActive') !== true ||
      AppStorage.get<number>('carplayProjectionDisplayId') !== report.displayId) {
      this.touchScrollState = undefined;
      return;
    }
    const pressed = report.contacts.filter((contact): boolean => contact.down);
    if (pressed.length !== 1) {
      this.touchScrollState = undefined;
      return;
    }
    const contact = pressed[0];
    const point = this.canvasPixelToContentPoint(contact.x, contact.y);
    const previous = this.touchScrollState;
    if (!previous || previous.displayId !== report.displayId || previous.contactId !== contact.id) {
      const bounds = this.touchBounds.get('settings');
      const dragArea = this.dashboardView === 'settings'
        ? Array.from(this.touchAreas.values()).find((area: ProjectionTouchArea): boolean =>
          area.group === 'settings' && area.drag !== undefined &&
          this.contains(area, point.x, point.y) && (!bounds || this.contains(bounds, point.x, point.y)))
        : undefined;
      this.touchScrollState = {
        displayId: report.displayId,
        contactId: contact.id,
        startX: point.x,
        startY: point.y,
        lastX: point.x,
        lastY: point.y,
        scroller: dragArea ? undefined : this.scrollControllerAt(point.x, point.y),
        drag: dragArea?.drag
      };
      dragArea?.drag?.(point.x);
      return;
    }
    const deltaX = previous.lastX - point.x;
    const deltaY = previous.lastY - point.y;
    previous.lastX = point.x;
    previous.lastY = point.y;
    if (previous.drag) {
      previous.drag(point.x);
      return;
    }
    if (Math.hypot(point.x - previous.startX, point.y - previous.startY) >= 8) {
      previous.scroller?.scrollBy(deltaX, deltaY);
    }
  }

  aboutToAppear(): void {
    initializeProjectionSettings();
    this.normalizeEncoderFps();
    this.loadSafeInsets();
    this.loadContentCalibration();
    this.loadSplitRatios();
    this.loadProjectionResolution();
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
    this.touchScrollState = undefined;
    this.onMapSurfaceChange(undefined);
    this.onAppSurfaceChange(undefined);
    this.touchAreas.clear();
    this.touchBounds.clear();
    if (this.statusTimer >= 0) {
      clearInterval(this.statusTimer);
      this.statusTimer = -1;
    }
    if (this.mediaTimer >= 0) {
      clearInterval(this.mediaTimer);
      this.mediaTimer = -1;
    }
    const bridge = this.mediaSessionBridge;
    this.mediaSessionBridge = undefined;
    if (bridge) {
      void bridge.close().catch((error: Error): void => {
        hilog.error(DOMAIN, 'CarPlayerMedia', '媒体控制器释放失败：%{public}s', error.message);
      });
    }
  }

  private updateMapSurface(area: Area): void {
    this.mapSurfaceArea = area;
    this.notifyMapSurface();
  }

  private notifyAppSurface(): void {
    const ui = this.getUIContext();
    const area = this.appSurfaceArea;
    if (!area || !this.appSurfaceId) {
      return;
    }
    const surface: ProjectionMapSurface = {
      surfaceId: this.appSurfaceId,
      left: Math.round(ui.vp2px(Number.parseFloat(`${area.globalPosition.x}`))),
      top: Math.round(ui.vp2px(Number.parseFloat(`${area.globalPosition.y}`))),
      width: Math.round(ui.vp2px(Number.parseFloat(`${area.width}`))),
      height: Math.round(ui.vp2px(Number.parseFloat(`${area.height}`)))
    };
    if (surface.width > 0 && surface.height > 0) {
      this.onAppSurfaceChange(surface);
    }
  }

  private notifyMapSurface(): void {
    const ui = this.getUIContext();
    const area = this.mapSurfaceArea;
    if (!this.mapSurfaceLoaded || this.mapSurfaceId.length === 0 || !area ||
      Number.parseFloat(`${area.width}`) <= 0 || Number.parseFloat(`${area.height}`) <= 0) {
      return;
    }
    const surface: ProjectionMapSurface = {
      surfaceId: this.mapSurfaceId,
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

  private contains(bounds: ProjectionBounds, x: number, y: number): boolean {
    return x >= bounds.left && x < bounds.right && y >= bounds.top && y < bounds.bottom;
  }

  private updateTouchArea(group: string, key: string, area: Area, action: () => void,
    longPress?: () => void, drag?: (pointX: number) => void): void {
    const bounds = this.areaBounds(area);
    this.touchAreas.set(`${group}:${key}`, {
      group,
      action,
      longPress,
      drag,
      left: bounds.left,
      top: bounds.top,
      right: bounds.right,
      bottom: bounds.bottom
    });
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
    this.touchBounds.delete('grid');
    this.touchBounds.delete('media');
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
    const bridge = new MediaSessionBridge((): void => {
      if (this.mediaSessionBridge) {
        void this.refreshMediaSession(this.mediaSessionBridge);
      }
    });
    this.mediaSessionBridge = bridge;
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const manager = abilityAccessCtrl.createAtManager();
      if (manager.checkAccessTokenSync(context.applicationInfo.accessTokenId,
        'ohos.permission.MANAGE_MEDIA_RESOURCES_FOR_PUBLIC') !== 0) {
        await manager.requestPermissionsFromUser(context, ['ohos.permission.MANAGE_MEDIA_RESOURCES_FOR_PUBLIC']);
      }
    } catch (error) {
      this.mediaActionMessage = `媒体控制授权失败：${error instanceof Error ? error.message : String(error)}`;
    }
    if (this.mediaSessionBridge !== bridge) {
      return;
    }
    await this.refreshMediaSession(bridge);
    if (this.mediaSessionBridge === bridge) {
      this.mediaTimer = setInterval((): void => {
        void this.refreshMediaSession(bridge);
      }, 1000);
    }
  }

  private async refreshMediaSession(bridge: MediaSessionBridge): Promise<boolean> {
    const commandGeneration = this.mediaCommandGeneration;
    try {
      const state = await bridge.refresh();
      if (this.mediaSessionBridge === bridge && commandGeneration === this.mediaCommandGeneration) {
        const optimisticPlayback = this.optimisticPlaybackState;
        if (optimisticPlayback && state.isPlaying !== optimisticPlayback.isPlaying &&
          Date.now() < optimisticPlayback.expiresAt) {
          this.mediaState = this.mediaStateWithPlaybackState(state, optimisticPlayback.isPlaying);
        } else {
          this.optimisticPlaybackState = undefined;
          this.mediaState = state;
        }
        this.apps = includeMediaSessionApp(this.apps, state.bundleName, state.abilityName);
        this.logMediaSnapshotIfChanged(this.mediaState);
      }
      return true;
    } catch (error) {
      if (this.mediaSessionBridge === bridge && commandGeneration === this.mediaCommandGeneration) {
        this.mediaState = this.mediaStateWithMessage(
          `媒体会话不可用：${error instanceof Error ? error.message : String(error)}`
        );
      }
      return false;
    }
  }

  private mediaStateWithPlaybackState(
    state: ProjectionMediaSnapshot, isPlaying: boolean
  ): ProjectionMediaSnapshot {
    return {
      title: state.title,
      artist: state.artist,
      lyric: state.lyric,
      positionMs: state.positionMs,
      durationMs: state.durationMs,
      bundleName: state.bundleName,
      abilityName: state.abilityName,
      isPlaying,
      commands: state.commands,
      queue: state.queue,
      message: state.message
    };
  }

  private logMediaSnapshotIfChanged(state: ProjectionMediaSnapshot): void {
    if (!state.bundleName) {
      this.lastLoggedMediaSignature = '';
      return;
    }
    const signature = [
      state.bundleName,
      state.abilityName ?? '',
      state.title,
      state.artist,
      state.isPlaying
    ].join('|');
    if (signature === this.lastLoggedMediaSignature) {
      return;
    }
    this.lastLoggedMediaSignature = signature;
    this.onMediaLog(
      `媒体信息：${state.bundleName}/${state.abilityName ?? ''}；曲目=${state.title}；` +
        `歌手=${state.artist || '未知歌手'}；状态=${state.isPlaying ? '播放中' : '已暂停'}`
    );
  }

  private async sendMediaCommand(command: ProjectionMediaCommand): Promise<void> {
    const bridge = this.mediaSessionBridge;
    if (!bridge) {
      this.mediaActionMessage = '媒体控制器尚未就绪，请稍后重试';
      return;
    }
    if (!this.mediaState.commands.includes(command)) {
      this.mediaActionMessage = `当前音乐应用未开放${command}控制`;
      return;
    }
    const commandGeneration = ++this.mediaCommandGeneration;
    try {
      await bridge.send(command);
      if (commandGeneration !== this.mediaCommandGeneration) {
        return;
      }
      this.mediaActionMessage = '控制命令已发送';
      this.mediaCommandGeneration++;
      if (command === 'play' || command === 'pause') {
        const isPlaying = command === 'play';
        this.optimisticPlaybackState = { isPlaying, expiresAt: Date.now() + 2000 };
        this.mediaState = this.mediaStateWithPlaybackState(this.mediaState, isPlaying);
      }
      await this.refreshMediaSession(bridge);
    } catch (error) {
      if (commandGeneration === this.mediaCommandGeneration) {
        this.mediaCommandGeneration++;
        this.optimisticPlaybackState = undefined;
        this.mediaActionMessage = `媒体控制失败：${error instanceof Error ? error.message : String(error)}`;
        await this.refreshMediaSession(bridge);
      }
    }
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
    for (const areaKey of this.touchAreas.keys()) {
      if (areaKey.startsWith(prefix)) {
        this.touchAreas.delete(areaKey);
      }
    }
  }

  private chooseSettingsDropdownOption(key: string, index: number, onSelect: (index: number) => void): void {
    onSelect(index);
    this.closeSettingsDropdown(key);
  }

  private selectEncoderFps(index: number): void {
    const fps = [30, 60][index];
    if (fps !== undefined) {
      this.encoderFps = fps;
      if (fps > this.captureFps) {
        this.captureFps = fps;
      }
    }
  }

  private normalizeEncoderFps(): void {
    if (![30, 60].includes(this.encoderFps)) {
      this.encoderFps = 30;
    }
  }

  private selectCaptureFps(index: number): void {
    const fps = [30, 60][index];
    if (fps !== undefined) {
      this.captureFps = fps;
    }
  }

  private cycleDayNightMode(): void {
    this.dayNightMode = this.dayNightMode === 'AUTO' ? 'DAY' :
      this.dayNightMode === 'DAY' ? 'NIGHT' : 'AUTO';
  }

  private selectDayNightMode(mode: 'AUTO' | 'DAY' | 'NIGHT'): void {
    this.dayNightMode = mode;
  }

  private updateDisplayBrightness(value: number): void {
    this.displayBrightness = Math.round(Math.max(20, Math.min(100, value)));
  }

  private setDisplayBrightnessFromTouch(pointX: number, bounds: ProjectionBounds): void {
    const width = bounds.right - bounds.left;
    if (width <= 0) {
      return;
    }
    const position = Math.max(0, Math.min(1, (pointX - bounds.left) / width));
    this.updateDisplayBrightness(20 + position * 80);
  }

  private loadSplitRatios(): void {
    this.splitMapRatio = readProjectionSplitRatio('map');
    this.splitMusicRatio = readProjectionSplitRatio('music');
    this.splitMapRatioInput = `${this.splitMapRatio}`;
    this.splitMusicRatioInput = `${this.splitMusicRatio}`;
  }

  private updateSplitRatio(pane: ProjectionSplitPane, value: number): void {
    const ratio = saveProjectionSplitRatio(pane, value);
    if (pane === 'map') {
      this.splitMapRatio = ratio;
      this.splitMapRatioInput = `${ratio}`;
    } else {
      this.splitMusicRatio = ratio;
      this.splitMusicRatioInput = `${ratio}`;
    }
    const otherInput = pane === 'map' ? this.splitMusicRatioInput : this.splitMapRatioInput;
    this.splitRatioMessage = otherInput.length > 0 && !/^(?:[1-9]|10)$/.test(otherInput)
      ? '每个比例值必须是 1–10 的整数' : '';
  }

  private adjustSplitRatio(pane: ProjectionSplitPane, delta: number): void {
    this.updateSplitRatio(pane, (pane === 'map' ? this.splitMapRatio : this.splitMusicRatio) + delta);
  }

  private updateSplitRatioInput(pane: ProjectionSplitPane, value: string): void {
    const input = value.replace(/[^0-9]/g, '').slice(0, 2);
    if (pane === 'map') {
      this.splitMapRatioInput = input;
    } else {
      this.splitMusicRatioInput = input;
    }
    if (input.length === 0) {
      const otherInput = pane === 'map' ? this.splitMusicRatioInput : this.splitMapRatioInput;
      this.splitRatioMessage = otherInput.length > 0 && !/^(?:[1-9]|10)$/.test(otherInput)
        ? '每个比例值必须是 1–10 的整数' : '';
      return;
    }
    const ratio = Number.parseInt(input, 10);
    if (ratio >= 1 && ratio <= 10) {
      this.updateSplitRatio(pane, ratio);
    } else {
      this.splitRatioMessage = '每个比例值必须是 1–10 的整数';
    }
  }

  private restoreSplitRatioInput(pane: ProjectionSplitPane): void {
    const input = pane === 'map' ? this.splitMapRatioInput : this.splitMusicRatioInput;
    const valid = /^(?:[1-9]|10)$/.test(input);
    if (pane === 'map') {
      this.splitMapRatioInput = `${this.splitMapRatio}`;
    } else {
      this.splitMusicRatioInput = `${this.splitMusicRatio}`;
    }
    const otherInput = pane === 'map' ? this.splitMusicRatioInput : this.splitMapRatioInput;
    this.splitRatioMessage = !valid || (otherInput.length > 0 && !/^(?:[1-9]|10)$/.test(otherInput))
      ? '每个比例值必须是 1–10 的整数' : '';
  }

  private adjustSafeInset(edge: 'top' | 'right' | 'bottom' | 'left', delta: number): void {
    if (edge === 'top') {
      this.safeInsetTop = normalizeSafeInset(this.safeInsetTop + delta);
      AppStorage.setOrCreate(projectionSafeInsetKey(this.vehicleDisplayUuid, edge), this.safeInsetTop);
    } else if (edge === 'right') {
      this.safeInsetRight = normalizeSafeInset(this.safeInsetRight + delta);
      AppStorage.setOrCreate(projectionSafeInsetKey(this.vehicleDisplayUuid, edge), this.safeInsetRight);
    } else if (edge === 'bottom') {
      this.safeInsetBottom = normalizeSafeInset(this.safeInsetBottom + delta);
      AppStorage.setOrCreate(projectionSafeInsetKey(this.vehicleDisplayUuid, edge), this.safeInsetBottom);
    } else {
      this.safeInsetLeft = normalizeSafeInset(this.safeInsetLeft + delta);
      AppStorage.setOrCreate(projectionSafeInsetKey(this.vehicleDisplayUuid, edge), this.safeInsetLeft);
    }
  }

  private loadSafeInsets(): void {
    this.safeInsetTop = this.readSafeInset('top');
    this.safeInsetRight = this.readSafeInset('right');
    this.safeInsetBottom = this.readSafeInset('bottom');
    this.safeInsetLeft = this.readSafeInset('left');
  }

  private readSafeInset(edge: ProjectionSafeInsetEdge): number {
    const key = projectionSafeInsetKey(this.vehicleDisplayUuid, edge);
    PersistentStorage.persistProp(key, 0);
    return normalizeSafeInset(AppStorage.get<number>(key) ?? 0);
  }

  private loadContentCalibration(): void {
    const calibration: ProjectionContentCalibration =
      readProjectionContentCalibration(this.vehicleDisplayUuid);
    this.contentScalePercent = calibration.scale;
    this.contentOffsetXPercent = calibration.offsetX;
    this.contentOffsetYPercent = calibration.offsetY;
  }

  private adjustContentCalibration(control: ProjectionCalibrationControl, delta: number): void {
    if (!this.vehicleDisplayUuid) {
      this.calibrationMessage = '缺少车机显示 UUID，无法保存屏幕校准';
      return;
    }
    const currentValue = control === 'scale'
      ? this.contentScalePercent
      : control === 'offsetX' ? this.contentOffsetXPercent : this.contentOffsetYPercent;
    try {
      const value = saveProjectionContentCalibration(this.vehicleDisplayUuid, control, currentValue + delta);
      if (control === 'scale') {
        this.contentScalePercent = value;
      } else if (control === 'offsetX') {
        this.contentOffsetXPercent = value;
      } else {
        this.contentOffsetYPercent = value;
      }
      this.calibrationMessage = '校准已保存；输出分辨率保持不变';
    } catch (error) {
      this.calibrationMessage =
        `屏幕校准保存失败：${error instanceof Error ? error.message : String(error)}`;
    }
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

  private loadProjectionResolution(): void {
    if (!this.vehicleDisplayUuid || this.projectionModeOptions.length === 0) {
      this.resolutionSelectionMessage = '建立车机连接后，才能按 /info 显示档案设置分辨率';
      return;
    }
    const savedModeId = readProjectionResolutionPreference(this.vehicleDisplayUuid);
    const selection = resolveProjectionDisplayMode(this.projectionModeOptions, savedModeId);
    this.selectedProjectionModeId = selection.mode.id;
    if (selection.usedNativeFallback) {
      this.resolutionSelectionMessage = `已保存档位 ${savedModeId} 未通过当前 Profile 校验，已恢复原生尺寸`;
      saveProjectionResolutionPreference(this.vehicleDisplayUuid, RECEIVER_NATIVE_MODE_ID);
    } else {
      this.resolutionSelectionMessage = '';
    }
  }

  private selectProjectionResolution(modeId: string): void {
    const mode = this.projectionModeOptions.find((item: ProjectionDisplayMode): boolean => item.id === modeId);
    if (!mode || !this.vehicleDisplayUuid) {
      this.resolutionSelectionMessage = '该分辨率未在当前车机档案中验证';
      return;
    }
    try {
      saveProjectionResolutionPreference(this.vehicleDisplayUuid, mode.id);
      this.selectedProjectionModeId = mode.id;
      this.resolutionSelectionMessage = mode.id === this.activeProjectionModeId
        ? '所选档位已保存'
        : '所选档位将在下次连接时应用；当前视频流不会被静默改尺寸';
    } catch (error) {
      this.resolutionSelectionMessage =
        `保存分辨率档位失败：${error instanceof Error ? error.message : String(error)}`;
    }
  }

  @Builder
  private CalibrationControlRow(label: string, control: ProjectionCalibrationControl) {
    Row({ space: 8 }) {
      Text(label).fontSize(13).fontColor(this.primaryTextColor()).layoutWeight(1)
      Button('−')
        .width(40).height(40).fontColor(this.primaryTextColor())
        .backgroundColor(this.glassSecondaryColor()).borderRadius(12)
        .onClick((): void => this.adjustContentCalibration(control, -1))
        .onAreaChange((_oldArea, newArea) => this.updateTouchArea(
          'settings', `calibration-${control}-minus`, newArea,
          (): void => this.adjustContentCalibration(control, -1)))
      Text(`${control === 'scale' ? this.contentScalePercent :
        control === 'offsetX' ? this.contentOffsetXPercent : this.contentOffsetYPercent}%`)
        .fontSize(13).fontColor(this.primaryTextColor()).width(46).textAlign(TextAlign.Center)
      Button('+')
        .width(40).height(40).fontColor(this.primaryTextColor())
        .backgroundColor(this.glassSecondaryColor()).borderRadius(12)
        .onClick((): void => this.adjustContentCalibration(control, 1))
        .onAreaChange((_oldArea, newArea) => this.updateTouchArea(
          'settings', `calibration-${control}-plus`, newArea,
          (): void => this.adjustContentCalibration(control, 1)))
    }
    .width('100%')
    .height(46)
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

  private mediaProgressPercent(): number {
    if (this.mediaState.durationMs <= 0) {
      return 0;
    }
    return Math.max(0, Math.min(100, this.mediaState.positionMs / this.mediaState.durationMs * 100));
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
    const bridge = this.mediaSessionBridge;
    if (!bridge) {
      return;
    }
    try {
      await bridge.playQueueItem(itemId);
      this.mediaActionMessage = '队列播放命令已发送';
      await this.refreshMediaSession(bridge);
    } catch (error) {
      this.mediaActionMessage = `播放队列项目失败：${error instanceof Error ? error.message : String(error)}`;
    }
  }

  private mediaStateWithMessage(message: string): ProjectionMediaSnapshot {
    return {
      title: EMPTY_PROJECTION_MEDIA.title,
      artist: EMPTY_PROJECTION_MEDIA.artist,
      lyric: EMPTY_PROJECTION_MEDIA.lyric,
      positionMs: EMPTY_PROJECTION_MEDIA.positionMs,
      durationMs: EMPTY_PROJECTION_MEDIA.durationMs,
      isPlaying: EMPTY_PROJECTION_MEDIA.isPlaying,
      commands: [],
      queue: [],
      message
    };
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

  @Builder
  SignalIndicator() {
    Row({ space: 2 }) {
      Column()
        .width(3)
        .height(5)
          .backgroundColor(this.signalLevel >= 1 ? this.primaryTextColor() : this.mutedTextColor())
      Column()
        .width(3)
        .height(8)
          .backgroundColor(this.signalLevel >= 2 ? this.primaryTextColor() : this.mutedTextColor())
      Column()
        .width(3)
        .height(11)
          .backgroundColor(this.signalLevel >= 3 ? this.primaryTextColor() : this.mutedTextColor())
      Column()
        .width(3)
        .height(14)
          .backgroundColor(this.signalLevel >= 4 ? this.primaryTextColor() : this.mutedTextColor())
    }
    .height(16)
    .alignItems(VerticalAlign.Bottom)
    .accessibilityText(`${this.networkLabel}信号 ${this.signalLevel}/4`)
  }

  @Builder
  BatteryIndicator() {
    Row({ space: 3 }) {
      Stack({ alignContent: Alignment.TopStart }) {
        Column()
          .width(21)
          .height(11)
          .borderRadius(3)
          .border({ width: 1, color: this.secondaryTextColor() })
        Row()
          .width(Math.max(2, 17 * this.batteryPercent / 100))
          .height(7)
          .margin({ left: 2, top: 2 })
          .borderRadius(1)
          .backgroundColor(this.batteryPercent <= 20 ? '#E0785E' : this.accent)
      }
      .width(21)
      .height(11)
      Column()
        .width(2)
        .height(5)
        .borderRadius(1)
        .backgroundColor(this.secondaryTextColor())
    }
    .alignItems(VerticalAlign.Center)
    .accessibilityText(`电量 ${this.batteryPercent}%`)
  }

  @Builder
  DockItem(id: string, label: string, icon: string, selected: boolean, vertical: boolean) {
    Stack({ alignContent: Alignment.Center }) {
      Image(this.dockIconResource(icon, selected))
        .width(this.dockIconSize).height(this.dockIconSize).objectFit(ImageFit.Contain).borderRadius(8)
    }
    .width(vertical ? '100%' : 64)
    .height(vertical ? 48 : '100%')
    .borderRadius(16)
    .backgroundColor(selected ? this.colorWithAlpha(this.accent, 'D9') : Color.Transparent)
    .border({ width: 1, color: selected ? '#55FFFFFF' : Color.Transparent })
    .gesture(GestureGroup(GestureMode.Exclusive,
      LongPressGesture({ duration: 550 }).onAction((): void => {
        if (id === 'map' || id === 'music') {
          this.activateDock(id, true);
        }
      }),
      TapGesture().onAction((): void => this.activateDock(id))))
    .accessibilityText(label)
    .onAreaChange((_oldArea, newArea) => this.updateTouchArea(
      'dock', id, newArea, (): void => this.activateDock(id), (): void => {
        if (id === 'map' || id === 'music') {
          this.activateDock(id, true);
        }
      }))
    .bindPopup(this.dockHint === label, { message: label })
    .onHover((hovered: boolean): void => { this.dockHint = hovered ? label : ''; })
  }

  @Builder
  DockPanel(vertical: boolean) {
    if (vertical) {
      Scroll(this.dockScroller) {
        Column({ space: 4 }) {
          Column({ space: 3 }) {
            this.SignalIndicator()
            this.BatteryIndicator()
          }
          .height(32)
          .justifyContent(FlexAlign.Center)
          .padding({ left: 2, right: 2 })
          this.DockItem('home', '首页', 'app.media.ic_house', this.isDockItemSelected('home'), true)
          this.DockItem('apps', '应用', 'app.media.ic_layout_grid', this.isDockItemSelected('apps'), true)
          this.DockItem('map', '地图', 'app.media.ic_navigation', this.isDockItemSelected('map'), true)
          this.DockItem('music', '音乐', 'app.media.ic_music', this.isDockItemSelected('music'), true)
          this.DockItem('split', '分屏', 'app.media.ic_split', this.isDockItemSelected('split'), true)
          this.DockItem('settings', '设置', 'app.media.ic_settings', this.isDockItemSelected('settings'), true)
        }
        .width('100%')
        .height('100%')
        .constraintSize({ minHeight: 320 })
        .padding({ top: 8, bottom: 8, left: 5, right: 5 })
        .alignItems(HorizontalAlign.Center)
        .backgroundColor(this.glassSurfaceColor())
        .border({ width: 1, color: this.glassStrokeColor() })
        .borderRadius(24)
        .clip(true)
      }
      .width('8%').constraintSize({ minWidth: 64, maxWidth: 92 }).height('100%')
      .scrollable(ScrollDirection.Vertical).scrollBar(BarState.Off)
      .borderRadius(24).clip(true)
      .onAreaChange((_oldArea, newArea) => this.touchBounds.set('dock', this.areaBounds(newArea)))
    } else {
      Scroll(this.dockScroller) {
        Row({ space: 4 }) {
          Column({ space: 2 }) {
            this.SignalIndicator()
            this.BatteryIndicator()
          }
          .width(36)
          .height('100%')
          .justifyContent(FlexAlign.Center)
          this.DockItem('home', '首页', 'app.media.ic_house', this.isDockItemSelected('home'), false)
          this.DockItem('apps', '应用', 'app.media.ic_layout_grid', this.isDockItemSelected('apps'), false)
          this.DockItem('map', '地图', 'app.media.ic_navigation', this.isDockItemSelected('map'), false)
          this.DockItem('music', '音乐', 'app.media.ic_music', this.isDockItemSelected('music'), false)
          this.DockItem('split', '分屏', 'app.media.ic_split', this.isDockItemSelected('split'), false)
          this.DockItem('settings', '设置', 'app.media.ic_settings', this.isDockItemSelected('settings'), false)
        }
        .width('100%').height('100%').constraintSize({ minWidth: 396 })
        .padding({ left: 8, right: 8, top: 4, bottom: 4 })
        .justifyContent(FlexAlign.Center)
        .backgroundColor(this.glassSurfaceColor())
        .border({ width: 1, color: this.glassStrokeColor() })
        .borderRadius(18)
        .clip(true)
      }
      .width('100%').height(64)
      .scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off)
      .borderRadius(18).clip(true)
      .onAreaChange((_oldArea, newArea) => this.touchBounds.set('dock', this.areaBounds(newArea)))
    }
  }

  @Builder
  AppIcon(app: ProjectionApp, size: number) {
    if (app.icon) {
      Image($r(app.icon))
        .width(size)
        .height(size)
        .objectFit(ImageFit.Contain)
        .borderRadius(8)
    } else if (app.symbol) {
      SymbolGlyph($r(app.symbol))
        .fontSize(size - 4)
        .fontColor([this.accent])
        .width(size)
        .height(size)
    } else {
      SymbolGlyph($r('sys.symbol.speaker_wave_2'))
        .fontSize(size - 4)
        .fontColor([app.color])
        .width(size)
        .height(size)
    }
  }

  @Builder
  AppTile(app: ProjectionApp) {
    Column({ space: 8 }) {
      Stack({ alignContent: Alignment.Center }) {
        this.AppIcon(app, 42)
      }
      .width(68)
      .height(68)
      .borderRadius(20)
      Text(app.label)
        .fontSize(13)
        .fontColor(this.primaryTextColor())
        .fontWeight(FontWeight.Medium)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .height(100)
    .justifyContent(FlexAlign.Center)
    .borderRadius(8)
    .opacity(app.launchState === 'UNVERIFIED' ? 0.62 : 1)
    .onClick(() => this.selectApp(app))
    .onAreaChange((_oldArea, newArea) => this.updateTouchArea(
      'grid', app.uri, newArea, (): void => this.selectApp(app)))
    .accessibilityText(app.category === 'vehicle' || app.category === 'home' || isProjectionAppLaunchable(app)
      ? `打开${app.label}` : `${app.label}，启动入口待验证`)
  }

  @Builder
  AppsPage() {
    Scroll(this.appsScroller) {
      Column({ space: 12 }) {
        Row() {
          Text('应用').fontSize(22).fontWeight(FontWeight.Bold).fontColor(this.primaryTextColor())
          Blank()
          Text(`${this.visibleApps().length} 个应用`).fontSize(12).fontColor(this.secondaryTextColor())
        }
        .width('100%')
        Grid() {
          ForEach(this.visibleApps(), (app: ProjectionApp) => {
            GridItem() { this.AppTile(app) }
          }, (app: ProjectionApp) => app.uri)
        }
        .columnsTemplate(this.appsGridTemplate()).columnsGap(18).rowsGap(14)
        .height(Math.ceil(this.visibleApps().length / this.appsGridColumns) * 114)
        .width('100%')
      }
      .width('100%').padding(18)
    }
    .width('100%').height('100%')
    .backgroundColor(this.glassPanelColor())
    .border({ width: 1, color: this.glassStrokeColor() })
    .borderRadius(22)
    .clip(true)
    .onAreaChange((_oldArea, newArea) => {
      this.touchBounds.set('grid', this.areaBounds(newArea));
      this.updateAppsGridColumns(Number.parseFloat(`${newArea.width}`));
    })
  }

  @Builder
  DockMenu() {
    Column({ space: 12 }) {
      Row() {
        Blank()
        Button({ type: ButtonType.Circle }) {
          SymbolGlyph($r('sys.symbol.xmark')).fontSize(18).fontColor([this.primaryTextColor()])
        }
        .width(36).height(36).backgroundColor(this.glassSecondaryColor()).borderRadius(12)
        .onClick((): void => this.showDashboardView('home'))
        .accessibilityText('关闭应用菜单')
        .onAreaChange((_oldArea, newArea) => {
          this.updateTouchArea('maps', 'close', newArea, (): void => this.showDashboardView('home'));
          this.updateTouchArea('music', 'close', newArea, (): void => this.showDashboardView('home'));
        })
      }
      .width('100%')
      if (this.dashboardView === 'maps' && this.mapAppLabel.length > 0 &&
        this.mapAppUri === this.categoryApp('map')?.uri) {
        Button({ type: ButtonType.Circle }) {
          SymbolGlyph($r('sys.symbol.arrow_up_right')).fontSize(18).fontColor([this.primaryTextColor()])
        }
          .width(44).height(44).backgroundColor(this.glassSecondaryColor())
          .onClick((): void => this.onToggleMapDisplay())
          .accessibilityText(this.mapOnPhone ? '切换地图到虚拟屏' : '切换地图到手机')
          .onAreaChange((_oldArea, newArea) => this.updateTouchArea(
            'maps', 'toggleDisplay', newArea, (): void => this.onToggleMapDisplay()))
      } else if (this.dashboardView === 'maps' && this.activeAppLabel.length > 0 &&
        this.activeAppUri === this.categoryApp('map')?.uri) {
        Button({ type: ButtonType.Circle }) {
          SymbolGlyph($r('sys.symbol.arrow_up_right')).fontSize(18).fontColor([this.primaryTextColor()])
        }
          .width(44).height(44).backgroundColor(this.glassSecondaryColor())
          .onClick((): void => this.onToggleAppDisplay())
          .accessibilityText(this.appOnPhone ? '切换地图到虚拟屏' : '切换地图到手机')
          .onAreaChange((_oldArea, newArea) => this.updateTouchArea(
            'maps', 'toggleDisplay', newArea, (): void => this.onToggleAppDisplay()))
      }
      if (this.dockActionMessage.length > 0) {
        Text(this.dockActionMessage).fontSize(11).fontColor(this.secondaryTextColor()).maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      Scroll(this.dockMenuScroller) {
        Column({ space: 6 }) {
          ForEach(this.apps.filter((app: ProjectionApp): boolean =>
            app.category === (this.dashboardView === 'maps' ? 'map' : 'music')), (app: ProjectionApp) => {
            Row({ space: 12 }) {
              this.AppIcon(app, 36)
              Text(app.label).fontSize(14).fontColor(this.primaryTextColor()).layoutWeight(1).maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              if (this.categoryApp(app.category)?.uri === app.uri) {
                SymbolGlyph($r('sys.symbol.checkmark')).fontSize(18).fontColor([this.accent])
              }
            }
            .width('100%').height(60).padding({ left: 12, right: 12 }).borderRadius(16)
            .backgroundColor(this.categoryApp(app.category)?.uri === app.uri
              ? this.colorWithAlpha(this.accent, '2A') : this.glassPanelColor())
            .border({ width: 1, color: this.cardStrokeColor() })
            .onClick((): void => this.selectApp(app))
            .onAreaChange((_oldArea, newArea) => this.updateTouchArea(
              app.category === 'map' ? 'maps' : 'music', app.uri, newArea, (): void => this.selectApp(app)))
            .opacity(isProjectionAppLaunchable(app) ? 1 : 0.62)
          }, (app: ProjectionApp) => app.uri)
          if (!this.apps.some((app: ProjectionApp): boolean =>
            app.category === (this.dashboardView === 'maps' ? 'map' : 'music'))) {
            Text('暂无可用应用').fontSize(13).fontColor(this.secondaryTextColor()).padding(16)
          }
        }
        .width('100%')
      }
      .layoutWeight(1).width('100%')
    }
    .width('100%').height('100%').padding(16)
    .backgroundColor(this.glassPanelColor())
    .border({ width: 1, color: this.glassStrokeColor() })
    .borderRadius(22)
    .clip(true)
    .onAreaChange((_oldArea, newArea) => {
      const bounds = this.areaBounds(newArea);
      this.touchBounds.set('maps', bounds);
      this.touchBounds.set('music', bounds);
    })
  }

  private activeMusicApp(): ProjectionApp | undefined {
    return this.appOnPhone ? undefined : activeProjectionMusicApp(this.apps, this.activeAppUri);
  }

  @Builder
  SplitPage() {
    Row({ space: 8 }) {
      Column({ space: 6 }) {
        Stack({ alignContent: Alignment.BottomStart }) {
          XComponent({
            id: 'projectionSplitMapSurface',
            type: XComponentType.SURFACE,
            controller: this.mapXComponentController
          })
            .width('100%')
            .height('100%')
            .onLoad((): void => {
              this.mapSurfaceLoaded = true;
              this.mapSurfaceId = this.mapXComponentController.getXComponentSurfaceId();
              this.notifyMapSurface();
            })
            .onDestroy((): void => {
              this.mapSurfaceLoaded = false;
              this.mapSurfaceId = '';
              this.mapSurfaceArea = undefined;
              this.lastMapSurface = undefined;
              this.onMapSurfaceChange(undefined);
            })
            .onAreaChange((_oldArea, newArea) => this.updateMapSurface(newArea))
          if (this.mapMessage.length > 0) {
            Text(this.mapMessage).fontSize(11).fontColor(this.secondaryTextColor())
              .textAlign(TextAlign.Center).padding(12)
          }
        }
        .layoutWeight(1)
        .width('100%')
        .clip(true)
      }
      .layoutWeight(this.splitMapRatio)
      .height('100%')
      .padding(12)
      .borderRadius(22)
      .backgroundColor(this.glassPanelColor())
      .border({ width: 1, color: this.cardStrokeColor() })
      .clip(true)

      Column({ space: 6 }) {
        if (this.activeMusicApp()) {
          Stack({ alignContent: Alignment.Center }) {
            XComponent({
              id: 'projectionSplitMusicSurface',
              type: XComponentType.SURFACE,
              controller: this.appXComponentController
            })
              .width('100%')
              .height('100%')
              .onLoad((): void => {
                this.appSurfaceId = this.appXComponentController.getXComponentSurfaceId();
                this.notifyAppSurface();
              })
              .onDestroy((): void => {
                this.appSurfaceId = '';
                this.appSurfaceArea = undefined;
                this.onAppSurfaceChange(undefined);
              })
              .onAreaChange((_oldArea, newArea) => {
                this.appSurfaceArea = newArea;
                this.notifyAppSurface();
              })
            if (this.launchMessage.length > 0) {
              Text(this.launchMessage).fontSize(11).fontColor(this.secondaryTextColor())
                .textAlign(TextAlign.Center).padding(12)
            }
          }
          .layoutWeight(1)
          .width('100%')
          .clip(true)
        } else {
          Text('请先从音乐 Dock 打开音乐 app，再进入分屏')
            .fontSize(11).fontColor(this.secondaryTextColor()).maxLines(2).layoutWeight(1)
        }
      }
      .layoutWeight(this.splitMusicRatio)
      .height('100%')
      .padding(12)
      .borderRadius(22)
      .backgroundColor(this.glassPanelColor())
      .border({ width: 1, color: this.cardStrokeColor() })
      .clip(true)
    }
    .width('100%')
    .height('100%')
    .onAreaChange((_oldArea, newArea) => this.touchBounds.set('split', this.areaBounds(newArea)))
  }

  @Builder
  SafeInsetRow(label: string, edge: ProjectionSafeInsetEdge) {
    Row({ space: 8 }) {
      Text(label).fontSize(13).fontColor(this.primaryTextColor()).layoutWeight(1)
      Button('−')
        .width(40).height(40).fontColor(this.primaryTextColor())
        .backgroundColor(this.glassSecondaryColor()).borderRadius(12)
        .onClick((): void => this.adjustSafeInset(edge, -1))
        .onAreaChange((_oldArea, newArea) => this.updateTouchArea(
          'settings', `safe-${edge}-minus`, newArea, (): void => this.adjustSafeInset(edge, -1)))
      Text(`${edge === 'top' ? this.safeInsetTop : edge === 'right' ? this.safeInsetRight :
        edge === 'bottom' ? this.safeInsetBottom : this.safeInsetLeft}%`)
        .fontSize(13).fontColor(this.primaryTextColor()).width(42).textAlign(TextAlign.Center)
      Button('+')
        .width(40).height(40).fontColor(this.primaryTextColor())
        .backgroundColor(this.glassSecondaryColor()).borderRadius(12)
        .onClick((): void => this.adjustSafeInset(edge, 1))
        .onAreaChange((_oldArea, newArea) => this.updateTouchArea(
          'settings', `safe-${edge}-plus`, newArea, (): void => this.adjustSafeInset(edge, 1)))
    }
    .width('100%')
    .height(46)
  }

  @Builder
  ThemesPage() {
    Scroll(this.themesScroller) {
      Column({ space: 16 }) {
        Text('主题').fontSize(16).fontColor(this.primaryTextColor())
        Row({ space: 10 }) {
          ForEach(PROJECTION_THEMES, (theme: ProjectionTheme) => {
            Column({ space: 6 }) {
              Button({ type: ButtonType.Normal }) {
              Image(this.wallpaperResource(theme.id))
                .width('100%')
                .height('100%')
                .objectFit(ImageFit.Cover)
              }
              .width(84)
              .height(58)
              .padding(0)
              .borderRadius(14)
              .backgroundColor(Color.Transparent)
              .border({
              width: this.theme === theme.id ? 2 : 1,
              color: this.theme === theme.id ? this.primaryTextColor() : this.glassStrokeColor()
              })
              .clip(true)
              .onClick((): void => { this.theme = theme.id; })
              .onAreaChange((_oldArea, newArea) => this.updateTouchArea(
              'themes', theme.id, newArea, (): void => { this.theme = theme.id; }))
              .accessibilityText(theme.label)
              Text(theme.label).fontSize(12).fontColor(this.primaryTextColor())
            }
            .width(84)
          }, (theme: ProjectionTheme) => theme.id)
        }
        Text('强调色').fontSize(12).fontColor(this.secondaryTextColor())
        Row({ space: 12 }) {
          ForEach(PROJECTION_ACCENTS, (color: string) => {
            Button({ type: ButtonType.Circle }) {
              if (this.accent === color) {
              SymbolGlyph($r('sys.symbol.checkmark')).fontSize(16)
                .fontColor([this.mapBackgroundColor()])
              }
            }
            .width(30).height(30).backgroundColor(color)
            .border({
              width: this.accent === color ? 2 : 0,
              color: this.accent === color ? this.primaryTextColor() : Color.Transparent
            })
            .onClick((): void => { this.accent = color; })
            .onAreaChange((_oldArea, newArea) => this.updateTouchArea(
              'themes', color, newArea, (): void => { this.accent = color; }))
            .accessibilityText(`强调色 ${color}`)
          }, (color: string) => color)
        }
      }
      .width('100%').padding(16)
    }
    .width('100%').height('100%')
    .backgroundColor(this.glassPanelColor())
    .border({ width: 1, color: this.glassStrokeColor() })
    .borderRadius(22)
    .clip(true)
    .onAreaChange((_oldArea, newArea) => this.touchBounds.set('themes', this.areaBounds(newArea)))
  }

  @Builder
  private SplitRatioControl(pane: ProjectionSplitPane) {
    Row({ space: 4 }) {
      Button({ type: ButtonType.Normal }) {
        Text('−').fontSize(26).fontWeight(FontWeight.Bold).fontColor(this.primaryTextColor())
      }
        .width(42).height(42).padding(0)
        .backgroundColor(this.glassSecondaryColor()).borderRadius(10)
        .accessibilityText(pane === 'map' ? '减少地图比例' : '减少音乐比例')
        .onClick((): void => this.adjustSplitRatio(pane, -1))
        .onAreaChange((_oldArea, newArea) => this.updateTouchArea(
          'settings', `splitRatio-${pane}-minus`, newArea,
          (): void => this.adjustSplitRatio(pane, -1)))
      TextInput({
        text: pane === 'map' ? this.splitMapRatioInput : this.splitMusicRatioInput,
        placeholder: pane === 'map' ? '3' : '2'
      })
        .id(pane === 'map' ? 'projectionMapSplitRatio' : 'projectionMusicSplitRatio')
        .type(InputType.Number)
        .width(52).height(40)
        .fontColor(this.primaryTextColor())
        .placeholderColor(this.secondaryTextColor())
        .backgroundColor(this.glassSecondaryColor())
        .borderRadius(10)
        .textAlign(TextAlign.Center)
        .onChange((value: string): void => this.updateSplitRatioInput(pane, value))
        .onBlur((): void => this.restoreSplitRatioInput(pane))
        .onSubmit((): void => this.restoreSplitRatioInput(pane))
        .onAreaChange((_oldArea, newArea) => this.updateTouchArea(
          'settings', `splitRatio-${pane}-input`, newArea,
          (): void => this.getUIContext().getFocusController().requestFocus(
            pane === 'map' ? 'projectionMapSplitRatio' : 'projectionMusicSplitRatio')))
      Button({ type: ButtonType.Normal }) {
        Text('+').fontSize(26).fontWeight(FontWeight.Bold).fontColor(this.primaryTextColor())
      }
        .width(42).height(42).padding(0)
        .backgroundColor(this.glassSecondaryColor()).borderRadius(10)
        .accessibilityText(pane === 'map' ? '增加地图比例' : '增加音乐比例')
        .onClick((): void => this.adjustSplitRatio(pane, 1))
        .onAreaChange((_oldArea, newArea) => this.updateTouchArea(
          'settings', `splitRatio-${pane}-plus`, newArea,
          (): void => this.adjustSplitRatio(pane, 1)))
    }
  }

  @Builder
  SettingsPage() {
    Row({ space: 12 }) {
      Column({ space: 10 }) {
        Text('设置').fontSize(30).fontWeight(FontWeight.Bold).fontColor(this.primaryTextColor())
          .width('100%').padding({ left: 10, bottom: 8 })
        Button({ type: ButtonType.Normal }) {
          Row({ space: 12 }) {
            Image(this.settingsIconResource(
              'app.media.ic_day_night_light', 'app.media.ic_day_night', this.settingsTab === 'display'
            )).width(30).height(30).objectFit(ImageFit.Contain)
            Text('显示').fontSize(16)
              .fontColor(this.settingsTab === 'display' ? '#FFFFFF' : this.primaryTextColor())
              .layoutWeight(1)
          }
          .width('100%')
        }
        .width('100%').height(58).padding({ left: 12, right: 12 }).borderRadius(14)
        .backgroundColor(this.settingsTab === 'display'
          ? this.colorWithAlpha(this.accent, 'D9') : Color.Transparent)
        .onClick((): void => { this.settingsTab = 'display'; })
        .accessibilityText('显示设置')
        .onAreaChange((_oldArea, newArea) => this.updateTouchArea(
          'settings', 'tab-display', newArea, (): void => { this.settingsTab = 'display'; }))
        Button({ type: ButtonType.Normal }) {
          Row({ space: 12 }) {
            Image(this.settingsIconResource(
              'app.media.ic_car_front_light', 'app.media.ic_car_front', this.settingsTab === 'connect'
            )).width(30).height(30).objectFit(ImageFit.Contain)
            Text('连接').fontSize(16)
              .fontColor(this.settingsTab === 'connect' ? '#FFFFFF' : this.primaryTextColor())
              .layoutWeight(1)
          }
          .width('100%')
        }
        .width('100%').height(58).padding({ left: 12, right: 12 }).borderRadius(14)
        .backgroundColor(this.settingsTab === 'connect'
          ? this.colorWithAlpha(this.accent, 'D9') : Color.Transparent)
        .onClick((): void => { this.settingsTab = 'connect'; })
        .accessibilityText('连接设置')
        .onAreaChange((_oldArea, newArea) => this.updateTouchArea(
          'settings', 'tab-connect', newArea, (): void => { this.settingsTab = 'connect'; }))
      }
      .width('25%').constraintSize({ minWidth: 180, maxWidth: 270 }).height('100%')
      .padding(16).borderRadius(22)
      .backgroundColor(this.settingsGroupColor())
      .border({ width: { right: 1 }, color: this.settingsSeparatorColor() })

      if (this.settingsTab === 'display') {
        this.DisplaySettingsPane()
      } else {
        this.ConnectionSettingsPane()
      }
    }
    .width('100%').height('100%')
    .padding(10)
    .backgroundColor(this.settingsPanelColor())
    .border({ width: 1, color: this.glassStrokeColor() })
    .borderRadius(28)
    .clip(true)
    .onAreaChange((_oldArea, newArea) => this.touchBounds.set('settings', this.areaBounds(newArea)))
  }

  @Builder
  private SettingsDropdownRow(
    label: string,
    key: string,
    options: string[],
    selectedIndex: number,
    enabled: boolean,
    onSelect: (index: number) => void
  ) {
    Column() {
      Row({ space: 16 }) {
        Text(label).fontSize(14).fontColor(this.primaryTextColor()).layoutWeight(1)
        Button({ type: ButtonType.Normal }) {
          Row({ space: 8 }) {
            Text(options[selectedIndex] ?? '暂无可用选项')
              .fontSize(13)
              .fontColor(this.primaryTextColor())
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
            Text('⌄').fontSize(16).fontColor(this.secondaryTextColor())
          }
          .width('100%')
        }
        .width(180)
        .height(42)
        .padding({ left: 12, right: 12 })
        .borderRadius(12)
        .backgroundColor(this.glassSecondaryColor())
        .border({ width: 1, color: this.glassStrokeColor() })
        .enabled(enabled)
        .accessibilityText(`${label}：${options[selectedIndex] ?? '暂无可用选项'}`)
        .onClick((): void => {
          if (enabled) {
            this.toggleSettingsDropdown(key);
          }
        })
        .onAreaChange((_oldArea, newArea) => this.updateTouchArea(
          'settings', `dropdown-${key}-trigger`, newArea, (): void => {
            if (enabled) {
              this.toggleSettingsDropdown(key);
            }
          }))
      }
      .width('100%')
      .height(64)
      .padding(14)

      if (this.activeSettingsDropdown === key) {
        Row() {
          Blank()
          Column({ space: 4 }) {
            ForEach(options, (option: string, index: number) => {
              Button({ type: ButtonType.Normal }) {
                Row() {
                  Text(option).fontSize(13).fontColor(this.primaryTextColor()).layoutWeight(1)
                  if (selectedIndex === index) {
                    SymbolGlyph($r('sys.symbol.checkmark')).fontSize(14).fontColor([this.accent])
                  }
                }
                .width('100%')
              }
              .width('100%')
              .height(40)
              .padding({ left: 10, right: 10 })
              .borderRadius(10)
              .backgroundColor(selectedIndex === index
                ? this.colorWithAlpha(this.accent, '38') : Color.Transparent)
              .onClick((): void => this.chooseSettingsDropdownOption(key, index, onSelect))
              .onAreaChange((_oldArea, newArea) => this.updateTouchArea(
                'settings', `dropdown-${key}-option-${index}`, newArea,
                (): void => this.chooseSettingsDropdownOption(key, index, onSelect)))
            }, (option: string): string => `${key}-${option}`)
          }
          .width(180)
          .padding(6)
          .borderRadius(14)
          .backgroundColor(this.glassPanelColor())
          .border({ width: 1, color: this.glassStrokeColor() })
          .shadow({ radius: 18, color: '#50000000', offsetX: 0, offsetY: 8 })
        }
        .width('100%')
        .padding({ left: 14, right: 14, bottom: 8 })
      }
    }
    .width('100%')
    .border({ width: { top: 1 }, color: this.settingsSeparatorColor() })
  }

  @Builder
  private ConnectionSettingsPane() {
    Scroll(this.settingsScroller) {
      Column({ space: 14 }) {
        Text('连接').fontSize(26).fontWeight(FontWeight.Bold).fontColor(this.primaryTextColor())
        Column() {
          Row({ space: 12 }) {
            Image(this.settingsIconResource('app.media.ic_car_front_light', 'app.media.ic_car_front'))
              .width(34).height(34).objectFit(ImageFit.Contain)
            Column({ space: 3 }) {
              Text('CarPlay').fontSize(15).fontWeight(FontWeight.Medium).fontColor(this.primaryTextColor())
              Text('车机投影连接').fontSize(12).fontColor(this.secondaryTextColor())
            }
            .layoutWeight(1).alignItems(HorizontalAlign.Start)
            Text('已连接').fontSize(13).fontColor('#32D74B')
          }
          .width('100%').height(64).padding(14)
          Row({ space: 12 }) {
            Column({ space: 3 }) {
              Text('蓝牙音频').fontSize(14).fontColor(this.primaryTextColor())
              Text(this.useBluetoothAudio ? '系统蓝牙音频路由' : '使用 CarPlay RTP 音频')
                .fontSize(12).fontColor(this.secondaryTextColor())
            }
            .layoutWeight(1).alignItems(HorizontalAlign.Start)
            Toggle({ type: ToggleType.Switch, isOn: this.useBluetoothAudio })
              .selectedColor('#32D74B')
              .onChange((enabled: boolean): void => { this.useBluetoothAudio = enabled; })
              .accessibilityText('使用蓝牙音频')
              .onAreaChange((_oldArea, newArea) => this.updateTouchArea(
                'settings', 'bluetoothAudio', newArea,
                (): void => { this.useBluetoothAudio = !this.useBluetoothAudio; }))
          }
          .width('100%').height(64).padding(14)
          .border({ width: { top: 1 }, color: this.settingsSeparatorColor() })
        }
        .width('100%').borderRadius(18).backgroundColor(this.settingsGroupColor())
        .border({ width: 1, color: this.glassStrokeColor() })
        Column() {
          Row({ space: 12 }) {
            Column({ space: 3 }) {
              Text('设备状态').fontSize(14).fontColor(this.primaryTextColor())
              Text(this.networkLabel).fontSize(12).fontColor(this.secondaryTextColor())
            }
            .layoutWeight(1).alignItems(HorizontalAlign.Start)
            this.SignalIndicator()
            this.BatteryIndicator()
          }
          .width('100%').height(64).padding(14)
          this.SettingsDropdownRow(
            '投屏帧率 FPS',
            'encoderFps',
            ['30 fps', '60 fps'],
            Math.max(0, [30, 60].indexOf(this.encoderFps)),
            true,
            (index: number): void => this.selectEncoderFps(index)
          )
          this.SettingsDropdownRow(
            '采集刷新率',
            'captureFps',
            ['30 Hz', '60 Hz'],
            Math.max(0, [30, 60].indexOf(this.captureFps)),
            true,
            (index: number): void => this.selectCaptureFps(index)
          )
        }
        .width('100%').borderRadius(18).backgroundColor(this.settingsGroupColor())
        .border({ width: 1, color: this.glassStrokeColor() })
        Text(this.receiverHomeMessage || this.launchMessage).fontSize(11).fontColor(this.secondaryTextColor())
      }
      .width('100%').padding({ left: 36, right: 36, top: 28, bottom: 28 })
    }
    .layoutWeight(1).width('0%').height('100%')
    .backgroundColor(Color.Transparent)
    .onAreaChange((_oldArea, newArea) => this.touchBounds.set('settingsContent', this.areaBounds(newArea)))
  }

  @Builder
  private DisplaySettingsPane() {
    Scroll(this.settingsScroller) {
      Column({ space: 16 }) {
        Text('显示').fontSize(26).fontWeight(FontWeight.Bold).fontColor(this.primaryTextColor())
        Column() {
        Row({ space: 14 }) {
          Text('外观').fontSize(14).fontColor(this.primaryTextColor()).layoutWeight(1)
          Row({ space: 4 }) {
            Button({ type: ButtonType.Normal }) {
              Text('深色').fontSize(12).fontColor(
                this.dayNightMode === 'NIGHT' || (this.dayNightMode === 'AUTO' && this.nightMode)
                  ? this.mapBackgroundColor() : this.secondaryTextColor())
            }
            .height(42).padding({ left: 9, right: 9 }).borderRadius(9)
            .backgroundColor(this.dayNightMode === 'NIGHT' || (this.dayNightMode === 'AUTO' && this.nightMode)
              ? this.primaryTextColor() : Color.Transparent)
            .onClick((): void => this.selectDayNightMode('NIGHT'))
            .onAreaChange((_oldArea, newArea) => this.updateTouchArea(
              'settings', 'appearanceNight', newArea, (): void => this.selectDayNightMode('NIGHT')))
            Button({ type: ButtonType.Normal }) {
              Text('浅色').fontSize(12).fontColor(
                this.dayNightMode === 'DAY' || (this.dayNightMode === 'AUTO' && !this.nightMode)
                  ? this.mapBackgroundColor() : this.secondaryTextColor())
            }
            .height(42).padding({ left: 9, right: 9 }).borderRadius(9)
            .backgroundColor(this.dayNightMode === 'DAY' || (this.dayNightMode === 'AUTO' && !this.nightMode)
              ? this.primaryTextColor() : Color.Transparent)
            .onClick((): void => this.selectDayNightMode('DAY'))
            .onAreaChange((_oldArea, newArea) => this.updateTouchArea(
              'settings', 'appearanceDay', newArea, (): void => this.selectDayNightMode('DAY')))
          }
        }
        .height(68).padding(12)
        Row({ space: 14 }) {
          Column({ space: 3 }) {
            Text('亮度').fontSize(14).fontColor(this.primaryTextColor())
            Text(`${Math.round(this.displayBrightness)}%`).fontSize(12).fontColor(this.secondaryTextColor())
          }
          .width(72).alignItems(HorizontalAlign.Start)
          Slider({ value: this.displayBrightness, min: 20, max: 100, step: 1 })
            .layoutWeight(1)
            .blockColor('#FFFFFFFF')
            .selectedColor('#66787880')
            .trackColor('#66787880')
            .onChange((value: number): void => this.updateDisplayBrightness(value))
            .accessibilityText('亮度')
            .onAreaChange((_oldArea, newArea) => {
              const bounds = this.areaBounds(newArea);
              this.updateTouchArea('settings', 'displayBrightness', newArea, (): void => {},
                undefined, (pointX: number): void => this.setDisplayBrightnessFromTouch(pointX, bounds));
            })
        }
        .height(68).padding(12)
        .border({ width: { top: 1 }, color: this.settingsSeparatorColor() })
        Row({ space: 10 }) {
          Column({ space: 3 }) {
            Text('分屏比例').fontSize(14).fontColor(this.primaryTextColor())
            Text(this.splitRatioMessage || '地图 : 音乐 · 每项 1–10')
              .fontSize(11).fontColor(this.splitRatioMessage ? '#FF9F0A' : this.secondaryTextColor())
          }
          .layoutWeight(1).alignItems(HorizontalAlign.Start)
          Row({ space: 4 }) {
            this.SplitRatioControl('map')
            Text(':').fontSize(14).fontColor(this.secondaryTextColor())
            this.SplitRatioControl('music')
          }
        }
        .height(68).padding(12)
        .border({ width: { top: 1 }, color: this.settingsSeparatorColor() })
        }
        .width('100%')
        .borderRadius(18)
        .backgroundColor(this.settingsGroupColor())
        .border({ width: 1, color: this.glassStrokeColor() })
        Row({ space: 14 }) {
          Column({ space: 4 }) {
            Text('Dock 位置').fontSize(14).fontColor(this.primaryTextColor())
            Text(this.dockPosition === 'bottom' ? '底部' : '左侧').fontSize(12).fontColor(this.secondaryTextColor())
          }
          .layoutWeight(1)
          Button(this.dockPosition === 'bottom' ? '切换到左侧' : '切换到底部')
            .height(44)
            .fontColor(this.primaryTextColor())
            .backgroundColor(this.glassSecondaryColor())
            .borderRadius(12)
            .onClick((): void => this.toggleDockPosition())
            .onAreaChange((_oldArea, newArea) => this.updateTouchArea(
              'settings', 'dockPosition', newArea, (): void => this.toggleDockPosition()))
        }
        .height(68).padding(12).borderRadius(16).backgroundColor(this.settingsGroupColor())
        .border({ width: 1, color: this.glassStrokeColor() })
        Column({ space: 4 }) {
          Text(this.vehicleDisplayUuid.length > 0
            ? `显示安全边距 · ${this.vehicleDisplayUuid.slice(-8)}` : '显示安全边距 · 默认')
            .fontSize(14).fontColor(this.primaryTextColor())
          Text('按百分比避让遮挡区域；曲面轮廓仍需在目标车机校准')
            .fontSize(12).fontColor(this.secondaryTextColor()).maxLines(2)
          this.SafeInsetRow('上', 'top')
          this.SafeInsetRow('右', 'right')
          this.SafeInsetRow('下', 'bottom')
          this.SafeInsetRow('左', 'left')
        }
        .width('100%')
        .padding(14)
        .borderRadius(16)
        .backgroundColor(this.settingsGroupColor())
        .border({ width: 1, color: this.glassStrokeColor() })
        Column({ space: 4 }) {
          Text(this.vehicleDisplayUuid.length > 0
            ? `异形屏内容校准 · ${this.vehicleDisplayUuid.slice(-8)}` : '异形屏内容校准')
            .fontSize(14).fontColor(this.primaryTextColor())
          Text('等比缩放与位置微调仅作用于 Shell 内容；输出分辨率和全屏背景保持不变')
            .fontSize(12).fontColor(this.secondaryTextColor()).maxLines(2)
          this.CalibrationControlRow('内容缩放', 'scale')
          this.CalibrationControlRow('水平位置', 'offsetX')
          this.CalibrationControlRow('垂直位置', 'offsetY')
          Text(this.calibrationMessage || '缩放 70–100%；水平/垂直偏移各 ±15%，按显示 UUID 保存')
            .fontSize(10).fontColor(this.secondaryTextColor()).maxLines(2)
        }
        .width('100%')
        .padding(14)
        .borderRadius(16)
        .backgroundColor(this.settingsGroupColor())
        .border({ width: 1, color: this.glassStrokeColor() })
        Column() {
          this.SettingsDropdownRow(
            '投屏分辨率',
            'projectionResolution',
            this.projectionModeOptions.length > 0
              ? this.projectionModeOptions.map((mode: ProjectionDisplayMode): string => mode.label)
              : ['暂无可用档位'],
            Math.max(0, this.projectionModeOptions.findIndex(
              (mode: ProjectionDisplayMode): boolean => mode.id === this.selectedProjectionModeId
            )),
            this.projectionModeOptions.length > 1,
            (index: number): void => {
              const mode = this.projectionModeOptions[index];
              if (mode) {
                this.selectProjectionResolution(mode.id);
              }
            }
          )
        }
        .width('100%')
        .borderRadius(16)
        .backgroundColor(this.settingsGroupColor())
        .border({ width: 1, color: this.glassStrokeColor() })
        Text(this.resolutionSelectionMessage || this.projectionResolutionMessage ||
          (this.projectionModeOptions.length > 1
            ? `车机原生 ${this.projectionNativeWidth}×${this.projectionNativeHeight}；档位按显示 UUID 独立保存`
            : `车机原生 ${this.projectionNativeWidth}×${this.projectionNativeHeight}；当前无其它已验证档位`))
          .fontSize(12).fontColor(this.secondaryTextColor()).width('100%').maxLines(2)
      }
      .width('100%').padding(16)
    }
    .layoutWeight(1).width('0%').height('100%')
    .backgroundColor(Color.Transparent)
    .onAreaChange((_oldArea, newArea) => this.touchBounds.set('settingsContent', this.areaBounds(newArea)))
  }

  @Builder
  private MediaControl(command: ProjectionMediaCommand, label: string, symbol: Resource) {
    Button({ type: ButtonType.Normal }) {
      SymbolGlyph(symbol).fontSize(18).fontColor([
        command === 'play' || command === 'pause' ? '#FFFFFF' : this.primaryTextColor()
      ])
    }
    .layoutWeight(1).height(46).borderRadius(14)
    .backgroundColor(command === 'play' || command === 'pause'
      ? this.colorWithAlpha(this.accent, '48') : this.glassSecondaryColor())
    .enabled(this.mediaState.commands.includes(command))
    .accessibilityText(label)
    .onClick((): void => { void this.sendMediaCommand(command); })
    .onAreaChange((_oldArea, newArea) => this.updateTouchArea(
      'media', command === 'play' || command === 'pause' ? 'playPause' : command, newArea,
      (): void => {
        void this.sendMediaCommand(command === 'play' || command === 'pause'
          ? (this.mediaState.isPlaying ? 'pause' : 'play') : command);
      }))
  }

  @Builder
  private DashboardSidebar() {
    Column({ space: 10 }) {
      Column({ space: 8 }) {
        Column({ space: 3 }) {
          Text(this.mediaState.title).fontSize(16).fontWeight(FontWeight.Bold).fontColor(this.primaryTextColor())
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .width('100%').alignItems(HorizontalAlign.Start)
        .onClick((): void => this.openMediaApp())
        .onAreaChange((_oldArea, newArea) => this.updateTouchArea(
          'media', 'open', newArea, (): void => this.openMediaApp()))
        Text(this.mediaState.lyric || '暂无歌词')
          .fontSize(12).fontColor(this.secondaryTextColor())
          .width('100%').layoutWeight(1)
          .textAlign(TextAlign.Start).maxLines(3)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Progress({ value: this.mediaProgressPercent(), total: 100 })
          .width('100%').height(4).color('#FFFFFF')
        Row({ space: 4 }) {
          this.MediaControl('playPrevious', '上一首', $r('sys.symbol.backward_end_fill'))
          this.MediaControl(this.mediaState.isPlaying ? 'pause' : 'play', this.mediaState.isPlaying ? '暂停' : '播放',
            this.mediaState.isPlaying ? $r('sys.symbol.pause_fill') : $r('sys.symbol.play_fill'))
          this.MediaControl('playNext', '下一首', $r('sys.symbol.forward_end_fill'))
        }
        .width('100%')
      }
      .layoutWeight(1.25).width('100%').padding(16).borderRadius(24)
      .backgroundColor(this.glassPanelColor())
      .border({ width: 1, color: this.cardStrokeColor() })
      .clip(true)

      Stack({ alignContent: Alignment.TopStart }) {
        Image($r('app.media.projection_weather_card'))
          .width('100%').height('100%').objectFit(ImageFit.Cover)
        Column({ space: 10 }) {
          Text('上海').fontSize(14).fontWeight(FontWeight.Medium).fontColor('#FFFFFF')
            .width('100%').textAlign(TextAlign.Start)
          Row() {
            Column({ space: 6 }) {
              Text('24°').fontSize(42).fontWeight(FontWeight.Lighter).fontColor('#FFFFFF')
              Text('晴 · 27° / 18°').fontSize(12).fontColor('#D9FFFFFF')
            }
            .alignItems(HorizontalAlign.Start)
            Blank()
            Image($r('app.media.projection_weather_sun')).width(34).height(34).objectFit(ImageFit.Contain)
          }
          .width('100%').layoutWeight(1).alignItems(VerticalAlign.Center)
        }
        .width('100%').height('100%').padding(16)
      }
      .layoutWeight(1).width('100%').borderRadius(24)
      .border({ width: 1, color: this.cardStrokeColor() })
      .clip(true)
    }
    .layoutWeight(this.splitMusicRatio).height('100%')
    .onAreaChange((_oldArea, newArea) => this.touchBounds.set('media', this.areaBounds(newArea)))
  }

  @Builder
  MainPanel(verticalDock: boolean) {
    Stack({ alignContent: Alignment.TopStart }) {
      if (this.dashboardView === 'split' || this.preserveSplitSurfaceForOverlays) {
        this.SplitPage()
      } else if (this.activeAppLabel.length > 0) {
        Row({ space: 8 }) {
          Stack({ alignContent: Alignment.BottomStart }) {
            XComponent({
              id: 'projectionAppSurface',
              type: XComponentType.SURFACE,
              controller: this.appXComponentController
            })
            .width('100%')
            .height('100%')
            .onLoad((): void => {
                this.appSurfaceId = this.appXComponentController.getXComponentSurfaceId();
                this.notifyAppSurface();
              })
              .onDestroy((): void => {
                this.appSurfaceId = '';
                this.appSurfaceArea = undefined;
                this.onAppSurfaceChange(undefined);
              })
              .onAreaChange((_oldArea, newArea) => {
                this.appSurfaceArea = newArea;
                this.notifyAppSurface();
              })
            if (this.launchMessage.length > 0) {
              Text(this.launchMessage)
                .fontSize(12)
                .fontColor(this.secondaryTextColor())
                .textAlign(TextAlign.Center)
                .padding(12)
            }
            if (this.navigationPreview) {
              Column() {}
                .width('100%').height('100%')
                .onClick((): void => this.openMapApp())
                .onAreaChange((_oldArea, newArea) => {
                  this.touchBounds.set('preview', this.areaBounds(newArea));
                  this.updateTouchArea('preview', 'expand', newArea, (): void => this.openMapApp());
                })
                .accessibilityText('展开当前地图')
            }
          }
          .layoutWeight(this.splitMapRatio)
          .height('100%')
          .clip(true)
          if (this.navigationPreview) {
            this.DashboardSidebar()
          }
        }
        .width('100%').height('100%')
      } else {
        Row({ space: 14 }) {
          Stack({ alignContent: Alignment.TopStart }) {
            Image(this.mapPreviewResource())
              .width('100%').height('100%').objectFit(ImageFit.Cover)
            Column() {
              Row({ space: 12 }) {
                Stack({ alignContent: Alignment.Center }) {
                  SymbolGlyph($r('sys.symbol.arrow_up_right')).fontSize(22).fontColor(['#FFFFFF'])
                }
                .width(46).height(46).borderRadius(15).backgroundColor(this.accent)
                Column({ space: 4 }) {
                  Text('导航预览').fontSize(16).fontWeight(FontWeight.Bold).fontColor(this.primaryTextColor())
                  Text('示意地图 · 实际路线由地图应用提供')
                    .fontSize(11).fontColor(this.secondaryTextColor()).maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                }
                .alignItems(HorizontalAlign.Start)
              }
              .width('100%').padding(12).borderRadius(18)
              .backgroundColor(this.glassPanelColor())
              .border({ width: 1, color: this.cardStrokeColor() })
              Blank()
              Row({ space: 12 }) {
                Column({ space: 4 }) {
                  Text(this.launchMessage.length > 0 ? '地图暂不可用' : '准备开始导航')
                    .fontSize(15).fontWeight(FontWeight.Bold).fontColor(this.primaryTextColor())
                  Text(this.launchMessage || '打开地图应用以查看实时路线与路况')
                    .fontSize(11).fontColor(this.secondaryTextColor()).maxLines(2)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                }
                .layoutWeight(1).alignItems(HorizontalAlign.Start)
                Button({ type: ButtonType.Normal }) {
                  Row({ space: 8 }) {
                    SymbolGlyph($r('sys.symbol.arrow_up_right')).fontSize(17).fontColor(['#FFFFFF'])
                    Text('打开地图').fontSize(13).fontWeight(FontWeight.Medium).fontColor('#FFFFFF')
                  }
                }
                .height(48).padding({ left: 14, right: 14 }).borderRadius(15)
                .backgroundColor(this.accent)
                .accessibilityText('打开地图')
                .onClick((): void => this.openMapApp())
                .onAreaChange((_oldArea, newArea) => this.updateTouchArea(
                  'map', 'open', newArea, (): void => this.openMapApp()))
              }
              .width('100%').padding(12).borderRadius(18)
              .backgroundColor(this.glassPanelColor())
              .border({ width: 1, color: this.cardStrokeColor() })
            }
            .width('100%').height('100%').padding(14)
          }
          .layoutWeight(this.splitMapRatio).height('100%')
          .borderRadius(22).clip(true)
          .border({ width: 1, color: this.cardStrokeColor() })
          .onAreaChange((_oldArea, newArea) => this.touchBounds.set('map', this.areaBounds(newArea)))
          this.DashboardSidebar()
        }
        .width('100%').height('100%')
      }
      if (this.dashboardView !== 'home' && this.dashboardView !== 'split') {
        Image(this.wallpaperResource(this.theme))
          .width('100%').height('100%').objectFit(ImageFit.Cover)
        if (this.isLightAppearance()) {
          Column()
            .width('100%')
            .height('100%')
            .backgroundColor('#6BFFFFFF')
        }
      }
      if (this.dashboardView === 'apps') {
        this.AppsPage()
      } else if (this.dashboardView === 'settings') {
        this.SettingsPage()
      } else if (this.dashboardView === 'themes') {
        this.ThemesPage()
      } else if (this.dashboardView === 'maps' || this.dashboardView === 'music') {
        this.DockMenu()
      }
    }
    .layoutWeight(1)
    .width(verticalDock ? '0%' : '100%')
    .height(verticalDock ? '100%' : '0%')
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Image(this.wallpaperResource(this.theme))
        .width('100%').height('100%').objectFit(ImageFit.Cover)
      if (this.isLightAppearance()) {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor('#6BFFFFFF')
      }
      if (this.dockPosition === 'bottom') {
        Column({ space: 8 }) {
          this.MainPanel(false)
          this.DockPanel(false)
        }
        .width('100%')
        .height('100%')
        .padding({
          top: `${this.safeInsetTop}%`, right: `${this.safeInsetRight}%`,
          bottom: `${this.safeInsetBottom}%`, left: `${this.safeInsetLeft}%`
        })
        .scale({ x: this.contentScalePercent / 100, y: this.contentScalePercent / 100 })
        .translate({
          x: `${this.contentOffsetXPercent}%`,
          y: `${this.contentOffsetYPercent}%`
        })
      } else {
        Row({ space: 8 }) {
          this.DockPanel(true)
          this.MainPanel(true)
        }
        .width('100%')
        .height('100%')
        .padding({
          top: `${this.safeInsetTop}%`, right: `${this.safeInsetRight}%`,
          bottom: `${this.safeInsetBottom}%`, left: `${this.safeInsetLeft}%`
        })
        .scale({ x: this.contentScalePercent / 100, y: this.contentScalePercent / 100 })
        .translate({
          x: `${this.contentOffsetXPercent}%`,
          y: `${this.contentOffsetYPercent}%`
        })
      }
    }
    .width('100%')
    .height('100%')
    .padding(8)
    .clip(true)
    .backgroundColor(projectionTheme(this.theme).background)
    .brightness(0.5 + this.displayBrightness / 200)
    .onAreaChange((_oldArea, newArea) => {
      const height = Number.parseFloat(`${newArea.height}`);
      this.projectionViewportWidth = Math.max(0, Number.parseFloat(`${newArea.width}`) - 16);
      this.projectionViewportHeight = Math.max(0, height - 16);
      this.dockIconSize = this.dockPosition === 'bottom'
        ? Math.max(18, Math.min(30, height / 20))
        : Math.max(16, Math.min(30, (height - 100) / 5));
    })
  }
}