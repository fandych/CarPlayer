import common from '@ohos.app.ability.common';
import sensor from '@ohos.sensor';
import emitter from '@ohos.events.emitter';
import { CARPLAY_RECEIVER_HOME_EVENT } from '../video/CarPlayTouchInput';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { diagnosticLogArchive } from '../session/DiagnosticLogArchive';
import { ProjectionDashboard } from './ProjectionDashboard';
import {
  isProjectionAppLaunchable,
  ProjectionApp,
  PROJECTION_APP_CANDIDATES
} from './ProjectionAppCatalog';
import { ProjectionShakeDetector } from '../video/ProjectionShakeDetector';
import { projectionTheme, resolveNightMode } from '../video/ProjectionSettings';
import { ProjectionHomeAppDisplay } from './ProjectionHomeAppDisplay';
import { ProjectionHomeMapDisplay } from './ProjectionHomeMapDisplay';

const DOMAIN: number = 0xCA22;

@Entry
@Component
struct ProjectionHome {
  @State launchMessage: string = '';
  @State mapMessage: string = '正在准备地图画面';
  @State activeAppLabel: string = '';
  @StorageLink('carplayProjectionOutputWidth') projectionOutputWidth: number = 0;
  @StorageLink('carplayProjectionOutputHeight') projectionOutputHeight: number = 0;
  @StorageLink('carplayProjectionViewAreaX') projectionViewAreaX: number = 0;
  @StorageLink('carplayProjectionViewAreaY') projectionViewAreaY: number = 0;
  @StorageLink('carplayProjectionViewAreaWidth') projectionViewAreaWidth: number = 0;
  @StorageLink('carplayProjectionViewAreaHeight') projectionViewAreaHeight: number = 0;
  @StorageLink('carplayProjectionDensity') projectionDensity: number = 1;
  @StorageLink('carplayTheme') theme: string = 'aurora';
  @StorageLink('carplayDayNightMode') dayNightMode: string = 'NIGHT';
  @StorageLink('carplayNightMode') nightMode: boolean = true;
  @State private activeApp: ProjectionApp | undefined = undefined;
  @State private appOnPhone: boolean = false;
  @State private mapApp: ProjectionApp | undefined = undefined;
  @State private mapOnPhone: boolean = false;
  private appSwitching: boolean = false;
  private sensorStarted: boolean = false;
  private readonly shakeDetector: ProjectionShakeDetector = new ProjectionShakeDetector();
  private readonly shakeHandler = (event: sensor.AccelerometerResponse): void => {
    if (this.shakeDetector.update(event.x, event.y, event.z, Date.now())) {
      void this.toggleAppDisplay();
    }
  };
  private readonly lastLayoutSizes: Map<string, string> = new Map();
  private readonly appDisplay = new ProjectionHomeAppDisplay({
    getHostContext: (): common.UIAbilityContext => this.getUIContext().getHostContext() as common.UIAbilityContext,
    getActiveApp: (): ProjectionApp | undefined => this.activeApp,
    getAppOnPhone: (): boolean => this.appOnPhone,
    setAppOnPhone: (onPhone: boolean): void => { this.appOnPhone = onPhone; },
    setLaunchMessage: (message: string): void => { this.launchMessage = message; },
    getLaunchMessage: (): string => this.launchMessage,
    isSwitching: (): boolean => this.appSwitching,
    setSwitching: (switching: boolean): void => { this.appSwitching = switching; },
    logProjection: (message: string): void => this.logProjection(message)
  });
  private readonly mapDisplay = new ProjectionHomeMapDisplay({
    getActiveApp: (): ProjectionApp | undefined => this.activeApp,
    getAppOnPhone: (): boolean => this.appOnPhone,
    appDisplayId: (): number => this.appDisplay.displayId,
    setMapState: (app: ProjectionApp | undefined, onPhone: boolean): void => {
      this.mapApp = app;
      this.mapOnPhone = onPhone;
    },
    setMapMessage: (message: string): void => { this.mapMessage = message; },
    setLaunchMessage: (message: string): void => { this.launchMessage = message; },
    isSwitching: (): boolean => this.appSwitching,
    setSwitching: (switching: boolean): void => { this.appSwitching = switching; },
    logProjection: (message: string): void => this.logProjection(message)
  }, this.appDisplay);

  aboutToAppear(): void {
    AppStorage.setOrCreate('carplayNavigationPreview', false);
    const message = 'ProjectionHome appeared; rendering dock and app dashboard';
    hilog.info(DOMAIN, 'CarPlayerProjection', '%{public}s', message);
    this.logProjection(message);
    try {
      sensor.on(sensor.SensorId.ACCELEROMETER, this.shakeHandler, { interval: 50000000 });
      this.sensorStarted = true;
    } catch (error) {
      this.logProjection(`摇一摇传感器不可用：${error instanceof Error ? error.message : String(error)}`);
    }
  }

  aboutToDisappear(): void {
    const message = 'ProjectionHome disappeared';
    hilog.info(DOMAIN, 'CarPlayerProjection', '%{public}s', message);
    this.logProjection(message);
    this.mapDisplay.invalidate();
    void this.mapDisplay.releaseDisplay();
    this.appDisplay.invalidate();
    void this.appDisplay.releaseDisplay();
    if (this.sensorStarted) {
      sensor.off(sensor.SensorId.ACCELEROMETER, this.shakeHandler);
      this.sensorStarted = false;
    }
  }

  private async selectApp(app: ProjectionApp): Promise<void> {
    if (this.appSwitching) {
      return;
    }
    if (app.category !== 'vehicle' && app.category !== 'home' && !isProjectionAppLaunchable(app)) {
      this.launchMessage = app.unavailableReason ?? `${app.label} 的启动入口尚未验证`;
      this.logProjection(this.launchMessage);
      return;
    }
    if (this.activeApp?.uri === app.uri && !this.appOnPhone && this.appDisplay.displayId > 0) {
      return;
    }
    this.appDisplay.moveExistingInstance = app.appId === 'amap' && (
      (this.activeApp?.appId === 'amap' && (this.appOnPhone || this.appDisplay.displayId > 0)) ||
      (this.mapApp?.appId === 'amap' && this.mapDisplay.displayId > 0)
    );
    const keepNavigationSource = AppStorage.get<string>('carplayDashboardView') === 'split' &&
      app.category === 'music';
    if (this.mapDisplay.displayId > 0 && !keepNavigationSource) {
      this.appSwitching = true;
      this.mapDisplay.invalidate();
      try {
        await this.mapDisplay.releaseDisplay(app.category !== 'map');
      } finally {
        this.appSwitching = false;
      }
    }
    this.activeApp = app;
    this.activeAppLabel = app.label;
    this.launchMessage = '';
    if (this.appDisplay.displayId > 0) {
      this.appSwitching = true;
      try {
        await this.appDisplay.launchApp(app, this.appDisplay.displayId, this.appDisplay.moveExistingInstance);
        this.appDisplay.moveExistingInstance = false;
        this.appOnPhone = false;
        this.appDisplay.publishTouchBounds(this.appDisplay.activeSurface);
        this.launchMessage = '';
        this.logProjection(`${app.label}启动请求已受理；目标屏显示仍需车机验证`);
      } catch (error) {
        this.launchMessage = `无法启动${app.label}：${error instanceof Error ? error.message : String(error)}`;
        this.logProjection(this.launchMessage);
      } finally {
        this.appSwitching = false;
      }
    }
  }

  private async returnHome(): Promise<void> {
    if (this.appSwitching) {
      return;
    }
    this.appSwitching = true;
    this.appDisplay.invalidate();
    try {
      await this.appDisplay.releaseDisplay();
      this.activeApp = undefined;
      this.activeAppLabel = '';
      this.appDisplay.moveExistingInstance = false;
      this.launchMessage = '';
    } finally {
      this.appSwitching = false;
    }
  }

  private back(): void {
    if (!this.activeApp || this.appOnPhone || this.appDisplay.displayId <= 0) {
      void this.returnHome();
      return;
    }
    this.launchMessage = 'Phone 端未提供已验证的第三方应用返回键注入能力';
    this.logProjection(this.launchMessage);
  }

  private async toggleAppDisplay(): Promise<void> {
    await this.appDisplay.toggleDisplay();
  }

  private async toggleMapDisplay(): Promise<void> {
    await this.mapDisplay.toggleDisplay();
  }

  private logProjection(message: string): void {
    const hostContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
    diagnosticLogArchive.appendFromAbility(hostContext.filesDir, 'projection', message);
  }

  private logLayoutArea(element: string, width: string, height: string): void {
    const size = `${width}x${height}`;
    if (this.lastLayoutSizes.get(element) === size) {
      return;
    }
    this.lastLayoutSizes.set(element, size);
    const message = `ProjectionHome layout ${element}: ${size}`;
    hilog.info(DOMAIN, 'CarPlayerProjection', '%{public}s', message);
    this.logProjection(message);
  }

  private projectionAreaDensity(): number {
    return Number.isFinite(this.projectionDensity) && this.projectionDensity > 0 ? this.projectionDensity : 1;
  }

  private projectionAreaWidthVp(): number {
    const width = this.projectionViewAreaWidth > 0 ? this.projectionViewAreaWidth : this.projectionOutputWidth;
    return width > 0 ? width / this.projectionAreaDensity() : 1;
  }

  private projectionAreaHeightVp(): number {
    const height = this.projectionViewAreaHeight > 0 ? this.projectionViewAreaHeight : this.projectionOutputHeight;
    return height > 0 ? height / this.projectionAreaDensity() : 1;
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column() {
        ProjectionDashboard({
          launchMessage: this.launchMessage,
          mapMessage: this.mapMessage,
          activeAppLabel: this.activeAppLabel,
          activeAppUri: this.activeApp?.uri ?? '',
          appOnPhone: this.appOnPhone,
          mapAppLabel: this.mapApp?.label ?? '',
          mapAppUri: this.mapApp?.uri ?? '',
          mapOnPhone: this.mapOnPhone,
          viewAreaOriginX: this.projectionViewAreaX,
          viewAreaOriginY: this.projectionViewAreaY,
          onToggleAppDisplay: (): void => { void this.toggleAppDisplay(); },
          onToggleMapDisplay: (): void => { void this.toggleMapDisplay(); },
          onHomeClick: (): void => { void this.returnHome(); },
          onBackClick: (): void => this.back(),
          onReceiverHomeClick: (): void => { emitter.emit(CARPLAY_RECEIVER_HOME_EVENT); },
          onAppSurfaceChange: (surface): void => { void this.appDisplay.updateSurface(surface); },
          onMapSurfaceChange: (surface): void => { void this.mapDisplay.updateSurface(surface); },
          onMediaLog: (message): void => this.logProjection(message),
          onAppClick: (app): void => { void this.selectApp(app); }
        })
          .width('100%')
          .height('100%')
          .onAreaChange((_oldArea, newArea) => {
            this.logLayoutArea('dashboard active viewArea', `${newArea.width}`, `${newArea.height}`);
          })
      }
      .width(this.projectionAreaWidthVp())
      .height(this.projectionAreaHeightVp())
      .position({
        x: this.projectionViewAreaX / this.projectionAreaDensity(),
        y: this.projectionViewAreaY / this.projectionAreaDensity()
      })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(resolveNightMode(this.dayNightMode, this.nightMode)
      ? projectionTheme(this.theme).background : '#FFFFFF')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
