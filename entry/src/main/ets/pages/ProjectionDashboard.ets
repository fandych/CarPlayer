import batteryInfo from '@ohos.batteryInfo';
import { hilog } from '@kit.PerformanceAnalysisKit';
import bundleManager from '@ohos.bundle.bundleManager';
import radio from '@ohos.telephony.radio';
import emitter from '@ohos.events.emitter';
import abilityAccessCtrl from '@ohos.abilityAccessCtrl';
import common from '@ohos.app.ability.common';
import { CARPLAY_TOUCH_TAP_EVENT, CarPlayTouchTap } from '../video/CarPlayTouchInput';
import {
  ProjectionApp,
  PROJECTION_MAP_URI,
  PROJECTION_VEHICLE_APPS,
  isProjectionAppLaunchable,
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
  resolveProjectionDisplayMode, saveProjectionContentCalibration, saveProjectionResolutionPreference,
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

interface ProjectionTouchArea extends ProjectionBounds {
  group: string;
  action: () => void;
  longPress?: () => void;
}

interface ProjectionModeSelectOption {
  value: string;
}

const HOME_APP: ProjectionApp = {
  appId: 'shell-home',
  uri: 'carplay-client://v1/shell/home',
  launchState: 'VERIFIED',
  label: '首页',
  mark: 'C',
  color: '#41C99A',
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
  onAppSurfaceChange: (surface: ProjectionMapSurface | undefined) => void =
    (_surface: ProjectionMapSurface | undefined): void => {};
  onMapSurfaceChange: (surface: ProjectionMapSurface | undefined) => void =
    (_surface: ProjectionMapSurface | undefined): void => {};
  @Prop activeAppLabel: string = '';
  @Prop activeAppUri: string = '';
  @StorageLink('carplayNavigationPreview') navigationPreview: boolean = false;
  @Prop launchMessage: string = '';
  @Prop mapMessage: string = '正在准备地图画面';
  @State apps: ProjectionApp[] = [];
  @State dashboardView: string = 'home';
  @State selectedMapUri: string = '';
  @State selectedMusicUri: string = '';
  @State dockIconSize: number = 30;
  @StorageLink('carplayNightMode') nightMode: boolean = false;
  @StorageLink('carplayDayNightMode') dayNightMode: string = 'AUTO';
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
  @StorageLink('carplayTheme') theme: string = 'forest';
  @StorageLink('carplayAccent') accent: string = '#41C99A';
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
  @State mediaState: ProjectionMediaSnapshot = {
    title: EMPTY_PROJECTION_MEDIA.title,
    artist: EMPTY_PROJECTION_MEDIA.artist,
    isPlaying: EMPTY_PROJECTION_MEDIA.isPlaying,
    commands: [],
    queue: [],
    message: EMPTY_PROJECTION_MEDIA.message
  };
  @State mediaActionMessage: string = '';
  private statusTimer: number = -1;
  private mediaTimer: number = -1;
  private mediaSessionBridge?: MediaSessionBridge;
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
  private projectionViewportWidth: number = 0;
  private projectionViewportHeight: number = 0;
  private readonly touchHandler = (event: emitter.GenericEventData<CarPlayTouchTap>): void => {
    const tap = event.data;
    if (!tap || AppStorage.get<boolean>('carplayProjectionHomeActive') !== true ||
      AppStorage.get<number>('carplayProjectionDisplayId') !== tap.displayId) {
      return;
    }
    const ui = this.getUIContext();
    const start = this.screenToContentPoint(ui.px2vp(tap.startX), ui.px2vp(tap.startY));
    const end = this.screenToContentPoint(ui.px2vp(tap.endX), ui.px2vp(tap.endY));
    const startX = start.x;
    const startY = start.y;
    const endX = end.x;
    const endY = end.y;
    if (Math.hypot(endX - startX, endY - startY) > 20) {
      return;
    }
    const dock = this.touchBounds.get('dock');
    if (dock && (this.contains(dock, startX, startY) || this.contains(dock, endX, endY))) {
      if (this.contains(dock, startX, startY) && this.contains(dock, endX, endY)) {
        for (const area of this.touchAreas.values()) {
          if (area.group === 'dock' && this.contains(area, startX, startY) &&
            this.contains(area, endX, endY)) {
            if ((tap.durationMs ?? 0) >= 550) {
              area.longPress?.();
            } else {
              area.action();
            }
            return;
          }
        }
      }
      return;
    }
    if ((tap.durationMs ?? 0) >= 550) {
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
      if (bounds && this.contains(area, startX, startY) && this.contains(area, endX, endY) &&
        this.contains(bounds, startX, startY) && this.contains(bounds, endX, endY)) {
        area.action();
        return;
      }
    }
  };

  aboutToAppear(): void {
    initializeProjectionSettings();
    this.loadSafeInsets();
    this.loadContentCalibration();
    this.loadProjectionResolution();
    AppStorage.setOrCreate('carplayDashboardView', 'home');
    emitter.on<CarPlayTouchTap>(CARPLAY_TOUCH_TAP_EVENT, this.touchHandler);
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
    longPress?: () => void): void {
    const bounds = this.areaBounds(area);
    this.touchAreas.set(`${group}:${key}`, {
      group,
      action,
      longPress,
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
      return;
    }
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
    try {
      const state = await bridge.refresh();
      if (this.mediaSessionBridge === bridge) {
        this.mediaState = state;
        this.apps = includeMediaSessionApp(this.apps, state.bundleName, state.abilityName);
      }
      return true;
    } catch (error) {
      if (this.mediaSessionBridge === bridge) {
        this.mediaState = this.mediaStateWithMessage(
          `媒体会话不可用：${error instanceof Error ? error.message : String(error)}`
        );
      }
      return false;
    }
  }

  private async sendMediaCommand(command: ProjectionMediaCommand): Promise<void> {
    const bridge = this.mediaSessionBridge;
    if (!bridge || !this.mediaState.commands.includes(command)) {
      return;
    }
    try {
      await bridge.send(command);
      this.mediaActionMessage = '控制命令已发送';
      await this.refreshMediaSession(bridge);
    } catch (error) {
      this.mediaActionMessage = `媒体控制失败：${error instanceof Error ? error.message : String(error)}`;
    }
  }

  private openMediaApp(): void {
    const bundleName = this.mediaState.bundleName;
    const abilityName = this.mediaState.abilityName;
    if (!bundleName || !abilityName) {
      this.activateDock('music');
      return;
    }
    const app = this.apps.find((item: ProjectionApp): boolean => item.bundleName === bundleName);
    if (app) {
      this.selectApp(app);
    } else {
      this.mediaActionMessage = '当前音乐应用未提供可用的打开链接';
    }
  }

  private openMapApp(): void {
    const mapUri = this.selectedMapUri || PROJECTION_MAP_URI;
    const app = this.apps.find((item: ProjectionApp): boolean => item.uri === mapUri);
    if (app) {
      this.selectApp(app);
    }
  }

  private isDashboardHome(): boolean {
    return this.dashboardView === 'home' && (this.navigationPreview || this.activeAppLabel.length === 0);
  }

  private toggleDockPosition(): void {
    this.dockPosition = this.dockPosition === 'bottom' ? 'left' : 'bottom';
  }

  private cycleDayNightMode(): void {
    this.dayNightMode = this.dayNightMode === 'AUTO' ? 'DAY' :
      this.dayNightMode === 'DAY' ? 'NIGHT' : 'AUTO';
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

  private cycleProjectionResolution(): void {
    if (this.projectionModeOptions.length < 2) {
      return;
    }
    const currentIndex = this.projectionModeOptions.findIndex(
      (mode: ProjectionDisplayMode): boolean => mode.id === this.selectedProjectionModeId
    );
    const nextIndex = (currentIndex + 1 + this.projectionModeOptions.length) % this.projectionModeOptions.length;
    const nextMode = this.projectionModeOptions[nextIndex];
    if (nextMode) {
      this.selectProjectionResolution(nextMode.id);
    }
  }

  private projectionModeSelectOptions(): ProjectionModeSelectOption[] {
    const options: ProjectionModeSelectOption[] = [];
    for (const mode of this.projectionModeOptions) {
      const option: ProjectionModeSelectOption = { value: mode.label };
      options.push(option);
    }
    return options;
  }

  @Builder
  private CalibrationControlRow(label: string, value: number, control: ProjectionCalibrationControl) {
    Row({ space: 8 }) {
      Text(label).fontSize(11).fontColor('#DCE4DE').layoutWeight(1)
      Button('−')
        .width(34)
        .onClick((): void => this.adjustContentCalibration(control, -1))
        .onAreaChange((_oldArea, newArea) => this.updateTouchArea(
          'settings', `calibration-${control}-minus`, newArea,
          (): void => this.adjustContentCalibration(control, -1)))
      Text(`${value}%`).fontSize(11).fontColor('#F2F6F2').width(42).textAlign(TextAlign.Center)
      Button('+')
        .width(34)
        .onClick((): void => this.adjustContentCalibration(control, 1))
        .onAreaChange((_oldArea, newArea) => this.updateTouchArea(
          'settings', `calibration-${control}-plus`, newArea,
          (): void => this.adjustContentCalibration(control, 1)))
    }
    .width('100%')
    .height(38)
  }

  private categoryApp(category: string): ProjectionApp | undefined {
    const selected = category === 'map' ? this.selectedMapUri : this.selectedMusicUri;
    return this.apps.find((app: ProjectionApp): boolean => app.category === category && app.uri === selected) ??
      this.apps.find((app: ProjectionApp): boolean => app.category === category &&
        (category === 'map' ? app.uri === PROJECTION_MAP_URI : app.bundleName === this.mediaState.bundleName)) ??
      this.apps.find((app: ProjectionApp): boolean => app.category === category);
  }

  private activateDock(id: string, longPress: boolean = false): void {
    if (id === 'primary') {
      if (this.isDashboardHome()) {
        this.showDashboardView('apps');
      } else {
        this.selectApp(HOME_APP);
      }
    } else if (id === 'settings') {
      this.showDashboardView('settings');
    } else if (id === 'split') {
      this.showDashboardView('split');
    } else if (id === 'map' || id === 'music') {
      const app = this.categoryApp(id);
      if (longPress || !app) {
        this.showDashboardView(id === 'map' ? 'maps' : 'music');
      } else {
        this.selectApp(app);
      }
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
          .backgroundColor(this.signalLevel >= 1 ? this.accent : '#59645E')
      Column()
        .width(3)
        .height(8)
          .backgroundColor(this.signalLevel >= 2 ? this.accent : '#59645E')
      Column()
        .width(3)
        .height(11)
          .backgroundColor(this.signalLevel >= 3 ? this.accent : '#59645E')
      Column()
        .width(3)
        .height(14)
          .backgroundColor(this.signalLevel >= 4 ? this.accent : '#59645E')
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
          .border({ width: 1, color: '#B6C5BB' })
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
        .backgroundColor('#B6C5BB')
    }
    .alignItems(VerticalAlign.Center)
    .accessibilityText(`电量 ${this.batteryPercent}%`)
  }

  @Builder
  DockItem(id: string, label: string, icon: string, selected: boolean, vertical: boolean) {
    Stack({ alignContent: Alignment.Center }) {
      Image($r(icon)).width(this.dockIconSize).height(this.dockIconSize).objectFit(ImageFit.Contain).borderRadius(8)
    }
    .width(vertical ? '100%' : '0%')
    .height(vertical ? '0%' : '100%')
    .layoutWeight(1)
    .borderRadius(8)
    .backgroundColor(selected ? '#FFFFFF22' : Color.Transparent)
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
      Column({ space: 4 }) {
        Column({ space: 3 }) {
          this.SignalIndicator()
          this.BatteryIndicator()
        }
        .height(32)
        .justifyContent(FlexAlign.Center)
        .padding({ left: 2, right: 2 })
        this.DockItem('primary', this.isDashboardHome() ? '应用' : '首页',
          this.isDashboardHome() ? 'app.media.ic_layout_grid' : 'app.media.ic_house',
          this.dashboardView === 'apps', true)
        this.DockItem('map', '地图', this.categoryApp('map')?.icon ?? 'app.media.ic_navigation',
          this.dashboardView === 'maps' ||
            (!this.navigationPreview && this.activeAppUri === this.categoryApp('map')?.uri), true)
        this.DockItem('music', '音乐', this.categoryApp('music')?.icon ?? 'app.media.ic_music',
          this.dashboardView === 'music' || this.activeAppUri === this.categoryApp('music')?.uri, true)
        this.DockItem('split', '分屏', 'app.media.ic_layout_grid', this.dashboardView === 'split', true)
        this.DockItem('settings', '设置', 'app.media.ic_settings', this.dashboardView === 'settings', true)
      }
      .width('11%')
      .constraintSize({ minWidth: 48, maxWidth: 66 })
      .height('100%')
      .padding({ top: 8, bottom: 8, left: 5, right: 5 })
      .alignItems(HorizontalAlign.Center)
      .border({ width: { right: 0.5 }, color: '#FFFFFF18' })
      .backgroundColor(projectionTheme(this.theme).surface)
      .onAreaChange((_oldArea, newArea) => this.touchBounds.set('dock', this.areaBounds(newArea)))
    } else {
      Row({ space: 4 }) {
        Column({ space: 2 }) {
          this.SignalIndicator()
          this.BatteryIndicator()
        }
        .width(36)
        .height('100%')
        .justifyContent(FlexAlign.Center)
        this.DockItem('primary', this.isDashboardHome() ? '应用' : '首页',
          this.isDashboardHome() ? 'app.media.ic_layout_grid' : 'app.media.ic_house',
          this.dashboardView === 'apps', false)
        this.DockItem('map', '地图', this.categoryApp('map')?.icon ?? 'app.media.ic_navigation',
          this.dashboardView === 'maps' ||
            (!this.navigationPreview && this.activeAppUri === this.categoryApp('map')?.uri), false)
        this.DockItem('music', '音乐', this.categoryApp('music')?.icon ?? 'app.media.ic_music',
          this.dashboardView === 'music' || this.activeAppUri === this.categoryApp('music')?.uri, false)
        this.DockItem('split', '分屏', 'app.media.ic_layout_grid', this.dashboardView === 'split', false)
        this.DockItem('settings', '设置', 'app.media.ic_settings', this.dashboardView === 'settings', false)
      }
      .width('100%')
      .height(64)
      .padding({ left: 8, right: 8, top: 4, bottom: 4 })
      .border({ width: { top: 0.5 }, color: '#FFFFFF18' })
      .backgroundColor(projectionTheme(this.theme).surface)
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
    Column({ space: 5 }) {
      this.AppIcon(app, 36)
      Text(app.label)
        .fontSize(10)
        .fontColor('#DCE4DE')
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      if (app.category !== 'vehicle' && app.category !== 'home') {
        Text(isProjectionAppLaunchable(app) ? '入口可用 · 目标屏待实测' : '待验证')
          .fontSize(9).fontColor('#E7C77B').maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
    }
    .width('100%')
    .height(72)
    .justifyContent(FlexAlign.Center)
    .borderRadius(8)
    .backgroundColor(projectionTheme(this.theme).panel)
    .opacity(app.launchState === 'UNVERIFIED' ? 0.62 : 1)
    .onClick(() => this.selectApp(app))
    .onAreaChange((_oldArea, newArea) => this.updateTouchArea(
      'grid', app.uri, newArea, (): void => this.selectApp(app)))
    .accessibilityText(app.category === 'vehicle' || app.category === 'home' || isProjectionAppLaunchable(app)
      ? `打开${app.label}` : `${app.label}，启动入口待验证`)
  }

  @Builder
  AppsPage() {
    Scroll() {
      Column({ space: 8 }) {
        Text('车机应用').fontSize(14).fontColor('#F2F6F2').alignSelf(ItemAlign.Start)
        Text(this.appDiscoveryMessage).fontSize(10).fontColor('#AAB8AF')
          .width('100%').maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
        Button('重新核验应用入口')
          .width('100%').height(34)
          .onClick((): void => {
            void this.discoverApps(true).catch((error: Error): void => {
              this.appDiscoveryMessage = `应用入口核验失败：${error.message}`;
            });
          })
          .onAreaChange((_oldArea, newArea) => this.updateTouchArea(
            'grid', 'refreshAppTargets', newArea, (): void => {
              void this.discoverApps(true).catch((error: Error): void => {
                this.appDiscoveryMessage = `应用入口核验失败：${error.message}`;
              });
            }))
        Grid() {
          ForEach(PROJECTION_VEHICLE_APPS, (app: ProjectionApp) => {
            GridItem() { this.AppTile(app) }
          }, (app: ProjectionApp) => app.uri)
        }
        .columnsTemplate('1fr 1fr 1fr 1fr').columnsGap(8).rowsGap(8).height(80)
        this.AppCategory('地图', 'map')
        this.AppCategory('音乐', 'music')
        this.AppCategory('视频', 'video')
        this.AppCategory('其他应用', 'finance')
      }
      .width('100%').padding(12)
    }
    .width('100%').height('100%')
    .backgroundColor(projectionTheme(this.theme).background)
    .onAreaChange((_oldArea, newArea) => this.touchBounds.set('grid', this.areaBounds(newArea)))
  }

  @Builder
  AppCategory(title: string, category: string) {
    if (this.apps.some((app: ProjectionApp): boolean => app.category === category)) {
      Text(title).fontSize(13).fontColor('#AAB8AF').alignSelf(ItemAlign.Start)
      Grid() {
        ForEach(this.apps.filter((app: ProjectionApp): boolean => app.category === category), (app: ProjectionApp) => {
          GridItem() { this.AppTile(app) }
        }, (app: ProjectionApp) => app.uri)
      }
      .columnsTemplate('1fr 1fr 1fr').rowsGap(8).columnsGap(8)
      .height(Math.ceil(this.apps.filter((app: ProjectionApp): boolean => app.category === category).length / 3) * 80)
    }
  }

  @Builder
  DockMenu() {
    Column({ space: 12 }) {
      Row() {
        Text(this.dashboardView === 'maps' ? '地图' : '音乐').fontSize(16).fontColor('#F5F5F7')
        Blank()
        Button({ type: ButtonType.Circle }) {
          SymbolGlyph($r('sys.symbol.xmark')).fontSize(18).fontColor(['#F5F5F7'])
        }
        .width(32).height(32).backgroundColor('#FFFFFF18')
        .onClick((): void => this.showDashboardView('home'))
        .accessibilityText('关闭应用菜单')
        .onAreaChange((_oldArea, newArea) => {
          this.updateTouchArea('maps', 'close', newArea, (): void => this.showDashboardView('home'));
          this.updateTouchArea('music', 'close', newArea, (): void => this.showDashboardView('home'));
        })
      }
      .width('100%')
      Scroll() {
        Column({ space: 6 }) {
          ForEach(this.apps.filter((app: ProjectionApp): boolean =>
            app.category === (this.dashboardView === 'maps' ? 'map' : 'music')), (app: ProjectionApp) => {
            Row({ space: 12 }) {
              this.AppIcon(app, 36)
              Text(app.label).fontSize(14).fontColor('#F5F5F7').layoutWeight(1).maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              if (this.categoryApp(app.category)?.uri === app.uri) {
                SymbolGlyph($r('sys.symbol.checkmark')).fontSize(18).fontColor([this.accent])
              }
            }
            .width('100%').height(54).padding({ left: 10, right: 10 }).borderRadius(8)
            .backgroundColor('#FFFFFF0D')
            .onClick((): void => this.selectApp(app))
            .onAreaChange((_oldArea, newArea) => this.updateTouchArea(
              app.category === 'map' ? 'maps' : 'music', app.uri, newArea, (): void => this.selectApp(app)))
            .opacity(isProjectionAppLaunchable(app) ? 1 : 0.62)
          }, (app: ProjectionApp) => app.uri)
          if (!this.apps.some((app: ProjectionApp): boolean =>
            app.category === (this.dashboardView === 'maps' ? 'map' : 'music'))) {
            Text('暂无可用应用').fontSize(13).fontColor('#AAB8AF').padding(16)
          }
        }
        .width('100%')
      }
      .layoutWeight(1).width('100%')
    }
    .width('100%').height('100%').padding(16)
    .backgroundColor(projectionTheme(this.theme).background)
    .onAreaChange((_oldArea, newArea) => {
      const bounds = this.areaBounds(newArea);
      this.touchBounds.set('maps', bounds);
      this.touchBounds.set('music', bounds);
    })
  }

  private activeMusicApp(): ProjectionApp | undefined {
    return this.apps.find((app: ProjectionApp): boolean =>
      app.uri === this.activeAppUri && app.category === 'music' && isProjectionAppLaunchable(app));
  }

  @Builder
  SplitPage() {
    Row({ space: 8 }) {
      Column({ space: 6 }) {
        Text('导航 APP').fontSize(13).fontColor('#F2F6F2')
        Stack({ alignContent: Alignment.Center }) {
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
            Text(this.mapMessage).fontSize(11).fontColor('#DCE4DE')
              .textAlign(TextAlign.Center).padding(12)
          }
        }
        .layoutWeight(1)
        .width('100%')
        .clip(true)
      }
      .layoutWeight(1)
      .height('100%')
      .padding(8)
      .borderRadius(10)
      .backgroundColor(projectionTheme(this.theme).panel)

      Column({ space: 6 }) {
        Text('音乐 APP').fontSize(13).fontColor('#F2F6F2')
        if (this.activeAppLabel.length > 0) {
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
              Text(this.launchMessage).fontSize(11).fontColor('#DCE4DE')
                .textAlign(TextAlign.Center).padding(12)
            } else if (!this.activeMusicApp()) {
              Text('当前应用未验证为音乐源')
                .fontSize(11).fontColor('#E7C77B').textAlign(TextAlign.Center).padding(12)
            }
          }
          .layoutWeight(1)
          .width('100%')
          .clip(true)
        } else {
          Text('需先验证音乐 APP 的公开启动入口、指定屏幕和同时显示能力')
            .fontSize(11).fontColor('#AAB8AF').maxLines(2)
          Grid() {
            ForEach(this.apps.filter((app: ProjectionApp): boolean => app.category === 'music'),
              (app: ProjectionApp) => {
                GridItem() { this.AppTile(app) }
              }, (app: ProjectionApp) => app.appId)
          }
          .columnsTemplate('1fr 1fr')
          .rowsGap(8)
          .columnsGap(8)
          .layoutWeight(1)
        }
      }
      .layoutWeight(1)
      .height('100%')
      .padding(8)
      .borderRadius(10)
      .backgroundColor(projectionTheme(this.theme).panel)
    }
    .width('100%')
    .height('100%')
    .onAreaChange((_oldArea, newArea) => this.touchBounds.set('split', this.areaBounds(newArea)))
  }

  @Builder
  SafeInsetRow(label: string, edge: 'top' | 'right' | 'bottom' | 'left', value: number) {
    Row({ space: 8 }) {
      Text(label).fontSize(11).fontColor('#DCE4DE').layoutWeight(1)
      Button('−')
        .width(34)
        .onClick((): void => this.adjustSafeInset(edge, -1))
        .onAreaChange((_oldArea, newArea) => this.updateTouchArea(
          'settings', `safe-${edge}-minus`, newArea, (): void => this.adjustSafeInset(edge, -1)))
      Text(`${value}%`).fontSize(11).fontColor('#F2F6F2').width(36).textAlign(TextAlign.Center)
      Button('+')
        .width(34)
        .onClick((): void => this.adjustSafeInset(edge, 1))
        .onAreaChange((_oldArea, newArea) => this.updateTouchArea(
          'settings', `safe-${edge}-plus`, newArea, (): void => this.adjustSafeInset(edge, 1)))
    }
    .width('100%')
    .height(38)
  }

  @Builder
  ThemesPage() {
    Scroll() {
      Column({ space: 16 }) {
        Text('主题').fontSize(16).fontColor('#F2F6F2')
        Row({ space: 16 }) {
          ForEach(PROJECTION_THEMES, (theme: ProjectionTheme) => {
            Column({ space: 6 }) {
              Button({ type: ButtonType.Circle }) {
                if (this.theme === theme.id) {
                  SymbolGlyph($r('sys.symbol.checkmark')).fontSize(20).fontColor([this.accent])
                }
              }
              .width(40).height(40).backgroundColor(theme.panel)
              .border({ width: 2, color: this.theme === theme.id ? this.accent : '#68736D' })
              .onClick((): void => { this.theme = theme.id; })
              .onAreaChange((_oldArea, newArea) => this.updateTouchArea(
                'themes', theme.id, newArea, (): void => { this.theme = theme.id; }))
              .accessibilityText(theme.label)
              Text(theme.label).fontSize(12).fontColor('#F2F6F2')
            }
            .width(64)
          }, (theme: ProjectionTheme) => theme.id)
        }
        Text('强调色').fontSize(12).fontColor('#DCE4DE')
        Row({ space: 18 }) {
          ForEach(PROJECTION_ACCENTS, (color: string) => {
            Button({ type: ButtonType.Circle }) {
              if (this.accent === color) {
                SymbolGlyph($r('sys.symbol.checkmark')).fontSize(16).fontColor(['#101713'])
              }
            }
            .width(30).height(30).backgroundColor(color)
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
    .backgroundColor(projectionTheme(this.theme).background)
    .onAreaChange((_oldArea, newArea) => this.touchBounds.set('themes', this.areaBounds(newArea)))
  }

  @Builder
  SettingsPage() {
    Scroll() {
      Column({ space: 12 }) {
        Text('设置').fontSize(16).fontColor('#F2F6F2')
        Row({ space: 16 }) {
          Column({ space: 4 }) {
            Text('Dock 位置').fontSize(12).fontColor('#DCE4DE')
            Text(this.dockPosition === 'bottom' ? '底部' : '左侧').fontSize(11).fontColor('#AAB8AF')
          }
          .layoutWeight(1)
          Button(this.dockPosition === 'bottom' ? '切换到左侧' : '切换到底部')
            .onClick((): void => this.toggleDockPosition())
            .onAreaChange((_oldArea, newArea) => this.updateTouchArea(
              'settings', 'dockPosition', newArea, (): void => this.toggleDockPosition()))
        }
        Row({ space: 16 }) {
          Column({ space: 4 }) {
            Text('昼夜模式').fontSize(12).fontColor('#DCE4DE')
            Text(this.dayNightMode === 'AUTO' ? '自动（跟随车机）' :
              this.dayNightMode === 'DAY' ? '白天' : '夜间').fontSize(11).fontColor('#AAB8AF')
          }
          .layoutWeight(1)
          Button('切换模式')
            .onClick((): void => this.cycleDayNightMode())
            .onAreaChange((_oldArea, newArea) => this.updateTouchArea(
              'settings', 'dayNightMode', newArea, (): void => this.cycleDayNightMode()))
        }
        Column({ space: 4 }) {
          Text(this.vehicleDisplayUuid.length > 0
            ? `显示安全边距 · ${this.vehicleDisplayUuid.slice(-8)}` : '显示安全边距 · 默认')
            .fontSize(12).fontColor('#DCE4DE')
          Text('按百分比避让遮挡区域；曲面轮廓仍需在目标车机校准')
            .fontSize(10).fontColor('#AAB8AF').maxLines(2)
          this.SafeInsetRow('上', 'top', this.safeInsetTop)
          this.SafeInsetRow('右', 'right', this.safeInsetRight)
          this.SafeInsetRow('下', 'bottom', this.safeInsetBottom)
          this.SafeInsetRow('左', 'left', this.safeInsetLeft)
        }
        .width('100%')
        .padding(12)
        .borderRadius(10)
        .backgroundColor(projectionTheme(this.theme).panel)
        Column({ space: 4 }) {
          Text(this.vehicleDisplayUuid.length > 0
            ? `异形屏内容校准 · ${this.vehicleDisplayUuid.slice(-8)}` : '异形屏内容校准')
            .fontSize(12).fontColor('#DCE4DE')
          Text('等比缩放与位置微调仅作用于 Shell 内容；输出分辨率和全屏背景保持不变')
            .fontSize(10).fontColor('#AAB8AF').maxLines(2)
          this.CalibrationControlRow('内容缩放', this.contentScalePercent, 'scale')
          this.CalibrationControlRow('水平位置', this.contentOffsetXPercent, 'offsetX')
          this.CalibrationControlRow('垂直位置', this.contentOffsetYPercent, 'offsetY')
          Text(this.calibrationMessage || '缩放 70–100%；水平/垂直偏移各 ±15%，按显示 UUID 保存')
            .fontSize(10).fontColor('#AAB8AF').maxLines(2)
        }
        .width('100%')
        .padding(12)
        .borderRadius(10)
        .backgroundColor(projectionTheme(this.theme).panel)
        Row({ space: 12 }) {
          Column({ space: 4 }) {
            Text('投屏分辨率').fontSize(12).fontColor('#DCE4DE')
            Text(this.activeProjectionModeId.length > 0
              ? `当前会话 ${this.projectionModeOptions.find(
                (mode: ProjectionDisplayMode): boolean => mode.id === this.activeProjectionModeId
              )?.label ?? this.activeProjectionModeId}` : '下次连接生效')
              .fontSize(11).fontColor('#AAB8AF')
          }
          .layoutWeight(1)
          Select(this.projectionModeSelectOptions())
            .selected(Math.max(0, this.projectionModeOptions.findIndex(
              (mode: ProjectionDisplayMode): boolean => mode.id === this.selectedProjectionModeId
            )))
            .enabled(this.projectionModeOptions.length > 1)
            .onSelect((index: number): void => {
              const mode = this.projectionModeOptions[index];
              if (mode) {
                this.selectProjectionResolution(mode.id);
              }
            })
            .width(180).height(36).font({ size: 12 })
            .onAreaChange((_oldArea, newArea) => this.updateTouchArea(
              'settings', 'projectionResolution', newArea, (): void => this.cycleProjectionResolution()))
        }
        .width('100%')
        .padding(12)
        .borderRadius(10)
        .backgroundColor(projectionTheme(this.theme).panel)
        Text(this.resolutionSelectionMessage || this.projectionResolutionMessage ||
          (this.projectionModeOptions.length > 1
            ? `车机原生 ${this.projectionNativeWidth}×${this.projectionNativeHeight}；档位按显示 UUID 独立保存`
            : `车机原生 ${this.projectionNativeWidth}×${this.projectionNativeHeight}；当前无其它已验证档位`))
          .fontSize(10).fontColor('#AAB8AF').width('100%').maxLines(2)
        Row({ space: 16 }) {
          Column({ space: 4 }) {
            Text('使用蓝牙音频').fontSize(12).fontColor('#DCE4DE')
            Text(this.useBluetoothAudio ? '蓝牙 A2DP（系统路由）' : 'CarPlay RTP')
              .fontSize(11).fontColor('#AAB8AF')
          }
          .layoutWeight(1)
          Toggle({ type: ToggleType.Switch, isOn: this.useBluetoothAudio })
            .selectedColor(this.accent)
            .onChange((enabled: boolean): void => { this.useBluetoothAudio = enabled; })
            .accessibilityText('使用蓝牙音频')
            .onAreaChange((_oldArea, newArea) => this.updateTouchArea(
              'settings', 'bluetoothAudio', newArea,
              (): void => { this.useBluetoothAudio = !this.useBluetoothAudio; }))
        }
        Row({ space: 16 }) {
          Text('编码帧率').fontSize(12).fontColor('#DCE4DE').layoutWeight(1)
          Select([{ value: '15 fps' }, { value: '24 fps' }, { value: '30 fps' }, { value: '60 fps' }])
            .selected(Math.max(0, [15, 24, 30, 60].indexOf(this.encoderFps)))
            .onSelect((index: number): void => { this.encoderFps = [15, 24, 30, 60][index]; })
            .width(120).height(32).font({ size: 12 })
        }
        Row({ space: 16 }) {
          Text('采集刷新率').fontSize(12).fontColor('#DCE4DE').layoutWeight(1)
          Select([{ value: '30 Hz' }, { value: '60 Hz' }])
            .selected(Math.max(0, [30, 60].indexOf(this.captureFps)))
            .onSelect((index: number): void => { this.captureFps = [30, 60][index]; })
            .width(120).height(32).font({ size: 12 })
        }
        Text('下次连接生效').fontSize(11).fontColor('#AAB8AF')
        if (this.activeEncoderFps > 0) {
          Text(`当前 ${this.activeEncoderFps} fps / ${this.activeCaptureFps} Hz`)
            .fontSize(11).fontColor('#DCE4DE')
        }
        Text(this.receiverHomeMessage || this.launchMessage).fontSize(11).fontColor('#DCE4DE')
      }
      .width('100%').padding(16)
    }
    .width('100%').height('100%')
    .backgroundColor(projectionTheme(this.theme).background)
    .onAreaChange((_oldArea, newArea) => this.touchBounds.set('settings', this.areaBounds(newArea)))
  }

  @Builder
  private MediaControl(command: ProjectionMediaCommand, label: string, symbol: Resource) {
    Button({ type: ButtonType.Normal }) {
      SymbolGlyph(symbol).fontSize(18).fontColor(['#F5F5F7'])
    }
    .layoutWeight(1).height(28).borderRadius(6)
    .backgroundColor(command === 'play' || command === 'pause' ? '#FFFFFF22' : Color.Transparent)
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
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        Image($r('app.media.ic_navigation')).width(26).height(26).objectFit(ImageFit.Contain)
        Column({ space: 3 }) {
          Text('导航信息').fontSize(12).fontWeight(FontWeight.Medium).fontColor('#F5F5F7')
          Text(this.launchMessage || '路线明细暂不可用').fontSize(10).fontColor('#FFFFFFB3')
            .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .layoutWeight(1).alignItems(HorizontalAlign.Start)
        SymbolGlyph($r('sys.symbol.arrow_up_right')).fontSize(16).fontColor(['#FFFFFFB3'])
      }
      .layoutWeight(1).width('100%').padding(10).borderRadius(8)
      .backgroundColor('#2364BD')
      .border({ width: 0.5, color: '#FFFFFF20' }).clip(true)
      .onClick((): void => this.openMapApp())
      .accessibilityText('展开导航')
      .onAreaChange((_oldArea, newArea) => {
        this.touchBounds.set('map', this.areaBounds(newArea));
        this.updateTouchArea('map', 'expandButton', newArea, (): void => this.openMapApp());
      })
      Row({ space: 8 }) {
        Image($r('app.media.ic_cloud_sun')).width(28).height(28).objectFit(ImageFit.Contain)
        Column({ space: 3 }) {
          Text('天气').fontSize(12).fontWeight(FontWeight.Medium).fontColor('#F5F5F7')
          Text('天气数据暂不可用').fontSize(10).fontColor('#FFFFFFB3')
            .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .layoutWeight(1).alignItems(HorizontalAlign.Start)
      }
      .layoutWeight(0.9).width('100%').padding(10).borderRadius(8)
      .backgroundColor('#393A40').border({ width: 0.5, color: '#E8C06B38' }).clip(true)
      Scroll() {
        Column({ space: 6 }) {
          Row({ space: 8 }) {
            this.AppIcon(this.categoryApp('music') ?? {
              uri: '', label: '音乐', mark: '', color: '#F0789C', category: 'music',
              appId: 'music-unavailable', launchState: 'UNVERIFIED',
              icon: 'app.media.ic_music'
            }, 28)
            Column({ space: 3 }) {
              Text(this.mediaState.title).fontSize(12).fontWeight(FontWeight.Medium).fontColor('#F5F5F7')
                .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
              Text(this.mediaState.artist || '音乐').fontSize(10).fontColor('#FFFFFFA6')
                .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
            }
            .layoutWeight(1).alignItems(HorizontalAlign.Start)
          }
          .width('100%')
          .onClick((): void => this.openMediaApp())
          .onAreaChange((_oldArea, newArea) => this.updateTouchArea(
            'media', 'open', newArea, (): void => this.openMediaApp()))
          Row({ space: 4 }) {
            this.MediaControl('playPrevious', '上一首', $r('sys.symbol.backward_end_fill'))
            this.MediaControl(this.mediaState.isPlaying ? 'pause' : 'play', this.mediaState.isPlaying ? '暂停' : '播放',
              this.mediaState.isPlaying ? $r('sys.symbol.pause_fill') : $r('sys.symbol.play_fill'))
            this.MediaControl('playNext', '下一首', $r('sys.symbol.forward_end_fill'))
          }
          .width('100%')
          if (this.mediaActionMessage.length > 0) {
            Text(this.mediaActionMessage).fontSize(9).fontColor('#FFFFFFA6')
              .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          ForEach(this.mediaState.queue.slice(0, 2), (item: ProjectionQueueItem) => {
            Text(item.title).fontSize(10).fontColor('#FFFFFFB3').width('100%')
              .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
              .onClick((): void => { void this.playQueueItem(item.itemId); })
              .onAreaChange((_oldArea, newArea) => this.updateTouchArea(
                'media', `queue_${item.itemId}`, newArea, (): void => { void this.playQueueItem(item.itemId); }))
              .accessibilityText(`播放${item.title}`)
          }, (item: ProjectionQueueItem) => `queue_${item.itemId}`)
        }
        .width('100%').padding(10)
      }
      .scrollBar(BarState.Auto)
      .layoutWeight(1.7).width('100%').borderRadius(8)
      .backgroundColor(projectionTheme(this.theme).panel)
      .border({ width: 0.5, color: '#F0789C30' }).clip(true)
      .onAreaChange((_oldArea, newArea) => this.touchBounds.set('media', this.areaBounds(newArea)))
    }
    .width('32%').constraintSize({ minWidth: 118, maxWidth: 250 }).height('100%')
  }

  @Builder
  MainPanel(verticalDock: boolean) {
    Stack({ alignContent: Alignment.TopStart }) {
      if (this.dashboardView === 'split') {
        this.SplitPage()
      } else if (this.activeAppLabel.length > 0) {
        Row({ space: 8 }) {
          Stack({ alignContent: Alignment.Center }) {
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
                .fontColor('#DCE4DE')
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
          .layoutWeight(1)
          .height('100%')
          .clip(true)
          if (this.navigationPreview) {
            this.DashboardSidebar()
          }
        }
        .width('100%').height('100%')
      } else {
        Row({ space: 8 }) {
          Stack({ alignContent: Alignment.Center }) {
            Column({ space: 12 }) {
              this.AppIcon(this.categoryApp('map') ?? {
                uri: PROJECTION_MAP_URI, label: '地图', mark: '', color: '#2364BD', category: 'map',
                appId: 'amap', launchState: 'UNVERIFIED',
                icon: 'app.media.ic_navigation'
              }, 48)
              Button({ type: ButtonType.Circle }) {
                SymbolGlyph($r('sys.symbol.arrow_up_right')).fontSize(22).fontColor(['#FFFFFF'])
              }
                .width(40).height(40)
                .backgroundColor('#2364BD')
                .accessibilityText('打开地图')
                .onClick((): void => this.openMapApp())
                .onAreaChange((_oldArea, newArea) => this.updateTouchArea(
                  'map', 'open', newArea, (): void => this.openMapApp()))
              if (this.launchMessage.length > 0) {
                Text(this.launchMessage)
                  .fontSize(11)
                  .fontColor('#DCE4DE')
                  .textAlign(TextAlign.Center)
                  .maxLines(2)
              }
            }
              .width('100%')
              .height('100%')
              .justifyContent(FlexAlign.Center)
          }
            .layoutWeight(1).height('100%')
            .borderRadius(8)
            .clip(true)
            .onAreaChange((_oldArea, newArea) => this.touchBounds.set('map', this.areaBounds(newArea)))
          this.DashboardSidebar()
        }
          .width('100%').height('100%')
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
    .brightness(resolveNightMode(this.dayNightMode, this.nightMode) ? 0.82 : 1)
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