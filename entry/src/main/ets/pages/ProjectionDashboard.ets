import { hilog } from '@kit.PerformanceAnalysisKit';
import emitter from '@ohos.events.emitter';
import {
  CARPLAY_TOUCH_REPORT_EVENT, CARPLAY_TOUCH_TAP_EVENT, CarPlayTouchReport, CarPlayTouchTap
} from '../video/CarPlayTouchInput';
import {
  ProjectionApp, projectionAppCatalog
} from './ProjectionAppCatalog';
import { ProjectionPoint, ProjectionTouchRouter } from './ProjectionTouchRouter';
import { ProjectionMapSurface } from './ProjectionSurface';
import { ProjectionDashboardSettingsController } from './ProjectionDashboardSettingsController';
import {
  EMPTY_PROJECTION_MEDIA,
  ProjectionMediaSnapshot
} from '../session/MediaSessionBridge';
import { ProjectionMediaCoordinator } from './ProjectionMediaCoordinator';
import { ProjectionDashboardShell } from './ProjectionDashboardShell';
import {
  initializeProjectionSettings, ProjectionDisplayMode,
  RECEIVER_NATIVE_MODE_ID
} from '../video/ProjectionSettings';
import { ProjectionDashboardAppController } from './ProjectionDashboardAppController';
import { ProjectionDashboardMediaController } from './ProjectionDashboardMediaController';
import { ProjectionDashboardPresentationController } from './ProjectionDashboardPresentationController';
import { ProjectionDashboardTouchController } from './ProjectionDashboardTouchController';
import { projectionDashboardShellBindings } from './ProjectionDashboardShellBindings';

export { ProjectionMapSurface } from './ProjectionSurface';
export { discoverProjectionApps } from './ProjectionDashboardAppDiscovery';

const DOMAIN: number = 0xCA22;

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
  @State preserveSplitSurfaceForOverlays: boolean = false;
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
  statusTimer: number = -1;
  mediaCoordinator?: ProjectionMediaCoordinator;
  appSurfaceId: string = '';
  appSurfaceArea?: Area;
  mapSurfaceId: string = '';
  mapSurfaceLoaded: boolean = false;
  mapSurfaceArea?: Area;
  lastMapSurface: ProjectionMapSurface | undefined = undefined;
  readonly touchRouter: ProjectionTouchRouter = new ProjectionTouchRouter();
  private readonly settingsController: ProjectionDashboardSettingsController =
    new ProjectionDashboardSettingsController();
  private readonly appController: ProjectionDashboardAppController = new ProjectionDashboardAppController();
  private readonly mediaController: ProjectionDashboardMediaController = new ProjectionDashboardMediaController();
  private readonly presentationController: ProjectionDashboardPresentationController =
    new ProjectionDashboardPresentationController();
  private readonly touchController: ProjectionDashboardTouchController =
    new ProjectionDashboardTouchController();
  dockScroller: Scroller = new Scroller();
  appsScroller: Scroller = new Scroller();
  dockMenuScroller: Scroller = new Scroller();
  settingsScroller: Scroller = new Scroller();
  themesScroller: Scroller = new Scroller();
  readonly sidebarMediaScroller: Scroller = new Scroller();
  projectionViewportWidth: number = 0;
  projectionViewportHeight: number = 0;
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
    this.touchController.handleTouchReport(this, event.data);
  };

  getStorage<T>(key: string): T | undefined {
    return AppStorage.get<T>(key);
  }

  setStorage<T>(key: string, value: T): void {
    AppStorage.setOrCreate(key, value);
  }

  canvasPixelToContentPoint(x: number, y: number): ProjectionPoint {
    return this.touchController.canvasPixelToContentPoint(this, x, y);
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
    void this.appController.discoverApps(this).catch((error: Error): void => {
      this.apps = projectionAppCatalog([]);
      this.appDiscoveryMessage = `应用入口核验失败：${error.message}`;
      hilog.error(DOMAIN, 'CarPlayerProjection', '%{public}s', this.appDiscoveryMessage);
    });
    void this.mediaController.startMediaSessionBridge(this);
    void this.mediaController.refreshDeviceStatus(this);
    this.statusTimer = setInterval((): void => {
      void this.mediaController.refreshDeviceStatus(this);
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
    void this.mediaController.closeMediaSession(this);
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

  build() {
    ProjectionDashboardShell(projectionDashboardShellBindings(
      this, this.appController, this.touchController, this.mediaController,
      this.presentationController, this.settingsController
    ))
  }
}