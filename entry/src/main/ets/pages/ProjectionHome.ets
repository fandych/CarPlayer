import common from '@ohos.app.ability.common';
import display from '@ohos.display';
import sensor from '@ohos.sensor';
import emitter from '@ohos.events.emitter';
import { CARPLAY_RECEIVER_HOME_EVENT } from '../video/CarPlayTouchInput';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { diagnosticLogArchive } from '../session/DiagnosticLogArchive';
import {
  discoverProjectionApps,
  ProjectionDashboard,
  ProjectionMapSurface
} from './ProjectionDashboard';
import {
  isProjectionAppLaunchable,
  projectionAppLaunchTarget,
  ProjectionApp,
  PROJECTION_APP_CANDIDATES
} from './ProjectionAppCatalog';
import { ProjectionShakeDetector } from '../video/ProjectionShakeDetector';
import {
  projectionContentDisplayConfig, projectionDisplayToggleTarget
} from '../video/CarPlayVirtualDisplay';
import { projectionTheme, resolveNightMode } from '../video/ProjectionSettings';

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
  private activeApp?: ProjectionApp;
  private appDisplayId: number = -1;
  private appContentWidth: number = 0;
  private appContentHeight: number = 0;
  private appDisplayGeneration: number = 0;
  private activeAppSurface?: ProjectionMapSurface;
  private appSurfaceAttached: boolean = false;
  private appSurfaceGeneration: number = 0;
  private activeAppMoveExistingInstance: boolean = false;
  @State private appOnPhone: boolean = false;
  private appSwitching: boolean = false;
  private sensorStarted: boolean = false;
  private readonly shakeDetector: ProjectionShakeDetector = new ProjectionShakeDetector();
  private readonly shakeHandler = (event: sensor.AccelerometerResponse): void => {
    if (this.shakeDetector.update(event.x, event.y, event.z, Date.now())) {
      void this.toggleAppDisplay();
    }
  };
  private readonly lastLayoutSizes: Map<string, string> = new Map();
  private mapDisplayId: number = -1;
  private mapApp?: ProjectionApp;
  private mapDisplayGeneration: number = 0;
  private activeMapSurface: ProjectionMapSurface | undefined = undefined;
  @State private mapOnPhone: boolean = false;

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
    this.mapDisplayGeneration++;
    void this.releaseMapDisplay();
    this.appDisplayGeneration++;
    void this.releaseAppDisplay();
    if (this.sensorStarted) {
      sensor.off(sensor.SensorId.ACCELEROMETER, this.shakeHandler);
      this.sensorStarted = false;
    }
  }

  private publishAppTouchBounds(surface?: ProjectionMapSurface): void {
    AppStorage.setOrCreate('carplayEmbeddedAppDisplayId', surface && !this.appOnPhone ? this.appDisplayId : -1);
    AppStorage.setOrCreate('carplayEmbeddedAppLeft', surface?.left ?? 0);
    AppStorage.setOrCreate('carplayEmbeddedAppTop', surface?.top ?? 0);
    AppStorage.setOrCreate('carplayEmbeddedAppWidth', surface?.width ?? 0);
    AppStorage.setOrCreate('carplayEmbeddedAppHeight', surface?.height ?? 0);
    AppStorage.setOrCreate('carplayEmbeddedAppContentWidth', this.appContentWidth);
    AppStorage.setOrCreate('carplayEmbeddedAppContentHeight', this.appContentHeight);
  }

  private async launchApp(
    app: ProjectionApp, displayId: number, preserveExistingInstance: boolean = false
  ): Promise<void> {
    if (!isProjectionAppLaunchable(app) || !app.launchTarget) {
      throw new Error(app.unavailableReason ?? `${app.label} 的启动入口尚未验证`);
    }
    const hostContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
    const target = projectionAppLaunchTarget(app, preserveExistingInstance);
    if (!target) {
      throw new Error(preserveExistingInstance
        ? `${app.label} 未核验为可复用的单实例 Ability；为保护导航状态，已拒绝重新启动`
        : `${app.label} 没有可用的启动入口`);
    }
    if (target.kind === 'ability') {
      if (!target.bundleName || !target.abilityName) {
        throw new Error(`${app.label} 的已验证 Ability 目标不完整`);
      }
      await hostContext.startAbility({
        bundleName: target.bundleName,
        moduleName: target.moduleName ?? app.moduleName,
        abilityName: target.abilityName
      }, { displayId });
      return;
    }
    if (preserveExistingInstance) {
      throw new Error(`${app.label} 只有 URI 启动入口，无法安全迁移现有实例`);
    }
    if (!target.uri) {
      throw new Error(`${app.label} 的已验证 App Link 目标为空`);
    }
    await hostContext.startAbility({
      action: 'ohos.want.action.viewData',
      uri: target.uri
    }, { displayId });
  }

  private async releaseAppDisplay(): Promise<void> {
    const screenId = this.appDisplayId;
    this.appDisplayId = -1;
    this.appContentWidth = 0;
    this.appContentHeight = 0;
    this.activeAppSurface = undefined;
    this.appSurfaceAttached = false;
    this.appSurfaceGeneration++;
    this.publishAppTouchBounds();
    if (screenId <= 0) {
      return;
    }
    try {
      if (this.activeApp && !this.appOnPhone) {
        await this.launchApp(
          this.activeApp,
          display.getDefaultDisplaySync().id,
          this.activeApp.appId === 'amap'
        );
        this.appOnPhone = true;
      }
    } catch (error) {
      this.logProjection(`释放内容屏前恢复应用失败：${error instanceof Error ? error.message : String(error)}`);
    }
    try {
      await display.destroyVirtualScreen(screenId);
    } catch (error) {
      this.logProjection(`销毁应用内容屏失败：${error instanceof Error ? error.message : String(error)}`);
    }
  }

  private async updateAppSurface(surface?: ProjectionMapSurface): Promise<void> {
    if (!surface) {
      this.appDisplayGeneration++;
      this.appSurfaceGeneration++;
      this.appSurfaceAttached = false;
      this.publishAppTouchBounds();
      return;
    }
    let appDisplayReleased: boolean = false;
    if (this.appDisplayId > 0 && this.activeAppSurface &&
      (this.activeAppSurface.width !== surface.width || this.activeAppSurface.height !== surface.height)) {
      const generation = ++this.appDisplayGeneration;
      await this.releaseAppDisplay();
      if (generation !== this.appDisplayGeneration) {
        return;
      }
      appDisplayReleased = true;
    }
    if (this.appDisplayId > 0 && this.activeAppSurface) {
      const screenId = this.appDisplayId;
      const surfaceGeneration = ++this.appSurfaceGeneration;
      try {
        if (!this.appSurfaceAttached || this.activeAppSurface.surfaceId !== surface.surfaceId) {
          await display.setVirtualScreenSurface(screenId, surface.surfaceId);
        }
        if (this.appDisplayId !== screenId || surfaceGeneration !== this.appSurfaceGeneration) {
          return;
        }
      } catch (error) {
        if (this.appDisplayId !== screenId || surfaceGeneration !== this.appSurfaceGeneration) {
          return;
        }
        this.launchMessage = `应用画面更新失败：${error instanceof Error ? error.message : String(error)}`;
        this.logProjection(this.launchMessage);
        return;
      }
      this.activeAppSurface = surface;
      this.appSurfaceAttached = true;
      if (this.launchMessage.startsWith('应用画面更新失败：')) {
        this.launchMessage = '';
      }
      this.publishAppTouchBounds(surface);
      return;
    }
    const generation = ++this.appDisplayGeneration;
    this.appSwitching = true;
    if (!appDisplayReleased) {
      await this.releaseAppDisplay();
    }
    if (generation !== this.appDisplayGeneration) {
      this.appSwitching = false;
      return;
    }
    let screenId = -1;
    try {
      const density = AppStorage.get<number>('carplayProjectionDensity');
      if (!density || !Number.isFinite(density) || density <= 0) {
        throw new Error('投影显示密度不可用');
      }
      const renderConfig = projectionContentDisplayConfig(surface.width, surface.height, density);
      this.logProjection(
        `应用虚拟屏清晰度：surface=${surface.width}x${surface.height}, ` +
          `render=${renderConfig.width}x${renderConfig.height}, density=${renderConfig.density}, ` +
          `scale=${renderConfig.scale}`
      );
      screenId = await display.createVirtualScreen({
        name: 'CarPlayer app content',
        width: renderConfig.width,
        height: renderConfig.height,
        density: renderConfig.density,
        surfaceId: surface.surfaceId,
        supportsFocus: true
      });
      await display.setVirtualScreenSurface(screenId, surface.surfaceId);
      await display.makeUnique(screenId);
      if (generation !== this.appDisplayGeneration) {
        await display.destroyVirtualScreen(screenId);
        return;
      }
      this.appDisplayId = screenId;
      this.appContentWidth = renderConfig.width;
      this.appContentHeight = renderConfig.height;
      this.activeAppSurface = surface;
      this.appSurfaceAttached = true;
      if (this.activeApp) {
        await this.launchApp(this.activeApp, screenId, this.activeAppMoveExistingInstance);
        this.activeAppMoveExistingInstance = false;
        this.appOnPhone = false;
        this.launchMessage = '';
      }
      this.publishAppTouchBounds(this.activeAppSurface);
    } catch (error) {
      if (screenId > 0 && this.appDisplayId !== screenId) {
        await display.destroyVirtualScreen(screenId).catch((): void => {});
      }
      this.launchMessage = `应用内容屏启动失败：${error instanceof Error ? error.message : String(error)}`;
      this.logProjection(this.launchMessage);
    } finally {
      this.appSwitching = false;
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
    if (this.activeApp?.uri === app.uri && !this.appOnPhone && this.appDisplayId > 0) {
      return;
    }
    this.activeAppMoveExistingInstance = app.appId === 'amap' && (
      (this.activeApp?.appId === 'amap' && (this.appOnPhone || this.appDisplayId > 0)) ||
      (this.mapApp?.appId === 'amap' && this.mapDisplayId > 0)
    );
    const keepNavigationSource = AppStorage.get<string>('carplayDashboardView') === 'split' &&
      app.category === 'music';
    if (this.mapDisplayId > 0 && !keepNavigationSource) {
      this.appSwitching = true;
      this.mapDisplayGeneration++;
      try {
        await this.releaseMapDisplay(app.category !== 'map');
      } finally {
        this.appSwitching = false;
      }
    }
    this.activeApp = app;
    this.activeAppLabel = app.label;
    this.launchMessage = '';
    if (this.appDisplayId > 0) {
      this.appSwitching = true;
      try {
        await this.launchApp(app, this.appDisplayId, this.activeAppMoveExistingInstance);
        this.activeAppMoveExistingInstance = false;
        this.appOnPhone = false;
        this.publishAppTouchBounds(this.activeAppSurface);
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
    this.appDisplayGeneration++;
    try {
      await this.releaseAppDisplay();
      this.activeApp = undefined;
      this.activeAppLabel = '';
      this.activeAppMoveExistingInstance = false;
      this.launchMessage = '';
    } finally {
      this.appSwitching = false;
    }
  }

  private back(): void {
    if (!this.activeApp || this.appOnPhone || this.appDisplayId <= 0) {
      void this.returnHome();
      return;
    }
    this.launchMessage = 'Phone 端未提供已验证的第三方应用返回键注入能力';
    this.logProjection(this.launchMessage);
  }

  private async toggleAppDisplay(): Promise<void> {
    const app = this.activeApp;
    if (!app || this.appDisplayId <= 0 || this.appSwitching) {
      return;
    }
    this.appSwitching = true;
    try {
      const target = projectionDisplayToggleTarget(
        this.appOnPhone, display.getDefaultDisplaySync().id, this.appDisplayId
      );
      await this.launchApp(app, target, app.appId === 'amap');
      this.appOnPhone = !this.appOnPhone;
      this.publishAppTouchBounds(this.activeAppSurface);
      this.launchMessage = '';
      this.logProjection(`应用启动请求已受理：${app.label}, displayId=${target}; target rendering is not verified`);
    } catch (error) {
      this.launchMessage = `应用链接打开失败：${error instanceof Error ? error.message : String(error)}`;
      this.logProjection(this.launchMessage);
    } finally {
      this.appSwitching = false;
    }
  }

  private async toggleMapDisplay(): Promise<void> {
    const app = this.mapApp;
    const screenId = this.mapDisplayId;
    if (!app || screenId <= 0 || this.appSwitching) {
      return;
    }
    this.appSwitching = true;
    try {
      const target = projectionDisplayToggleTarget(
        this.mapOnPhone, display.getDefaultDisplaySync().id, screenId
      );
      await this.launchApp(app, target, app.appId === 'amap');
      this.mapOnPhone = !this.mapOnPhone;
      if (this.activeMapSurface) {
        this.publishMapTouchBounds(this.activeMapSurface);
      }
      this.launchMessage = '';
      this.logProjection(`地图应用切换请求已受理：${app.label}, displayId=${target}`);
    } catch (error) {
      this.launchMessage = `地图应用切换失败：${error instanceof Error ? error.message : String(error)}`;
      this.logProjection(this.launchMessage);
    } finally {
      this.appSwitching = false;
    }
  }

  private publishMapTouchBounds(surface: ProjectionMapSurface): void {
    AppStorage.setOrCreate('carplayEmbeddedMapDisplayId', this.mapOnPhone ? -1 : this.mapDisplayId);
    AppStorage.setOrCreate('carplayEmbeddedMapLeft', surface.left);
    AppStorage.setOrCreate('carplayEmbeddedMapTop', surface.top);
    AppStorage.setOrCreate('carplayEmbeddedMapWidth', surface.width);
    AppStorage.setOrCreate('carplayEmbeddedMapHeight', surface.height);
  }

  private async releaseMapDisplay(restoreToPhone: boolean = true): Promise<void> {
    const displayId = this.mapDisplayId;
    const app = this.mapApp;
    const restoreAppToPhone = restoreToPhone && !this.mapOnPhone;
    this.mapApp = undefined;
    this.mapDisplayId = -1;
    this.mapOnPhone = false;
    this.activeMapSurface = undefined;
    AppStorage.setOrCreate('carplayEmbeddedMapDisplayId', -1);
    AppStorage.setOrCreate('carplayEmbeddedMapLeft', 0);
    AppStorage.setOrCreate('carplayEmbeddedMapTop', 0);
    AppStorage.setOrCreate('carplayEmbeddedMapWidth', 0);
    AppStorage.setOrCreate('carplayEmbeddedMapHeight', 0);
    if (displayId >= 0) {
      if (app && restoreAppToPhone) {
        try {
          await this.launchApp(app, display.getDefaultDisplaySync().id, app.appId === 'amap');
        } catch (error) {
          this.logProjection(`释放地图屏前恢复链接失败：${error instanceof Error ? error.message : String(error)}`);
        }
      }
      try {
        await display.destroyVirtualScreen(displayId);
      } catch (error) {
        this.logProjection(`销毁地图卡片虚拟屏失败：${error instanceof Error ? error.message : String(error)}`);
      }
    }
  }

  private async updateMapSurface(surface: ProjectionMapSurface | undefined): Promise<void> {
    if (!surface) {
      this.mapDisplayGeneration++;
      await this.releaseMapDisplay();
      this.mapMessage = '正在准备地图画面';
      return;
    }
    const selectedMapId = AppStorage.get<string>('carplaySelectedMapAppId') ?? 'amap';
    const generation = ++this.mapDisplayGeneration;
    const availableApps = await discoverProjectionApps();
    if (generation !== this.mapDisplayGeneration) {
      return;
    }
    const mapApp = availableApps.find((app: ProjectionApp): boolean =>
      app.appId === selectedMapId && isProjectionAppLaunchable(app));
    if (!mapApp) {
      await this.releaseMapDisplay();
      if (generation !== this.mapDisplayGeneration) {
        return;
      }
      const candidate = PROJECTION_APP_CANDIDATES.find((app: ProjectionApp): boolean =>
        app.appId === selectedMapId);
      this.mapMessage = candidate
        ? `${candidate.label}：${candidate.unavailableReason ?? '启动入口尚未通过本机核验'}`
        : '所选导航应用入口不可用';
      return;
    }
    const preserveExistingAmap = mapApp.appId === 'amap' && (
      (this.activeApp?.appId === 'amap' && (this.appOnPhone || this.appDisplayId > 0)) ||
      (this.mapApp?.appId === 'amap' && this.mapDisplayId > 0)
    );
    if (this.mapDisplayId >= 0 && this.activeMapSurface?.surfaceId === surface.surfaceId &&
      this.activeMapSurface.width === surface.width && this.activeMapSurface.height === surface.height) {
      this.activeMapSurface = surface;
      this.publishMapTouchBounds(surface);
      return;
    }

    await this.releaseMapDisplay(false);
    if (generation !== this.mapDisplayGeneration) {
      return;
    }
    this.mapMessage = `正在启动${mapApp.label}`;
    const density = AppStorage.get<number>('carplayProjectionDensity');
    if (density === undefined || !Number.isFinite(density) || density <= 0) {
      this.mapMessage = '地图卡片暂不可用';
      return;
    }
    const renderConfig = projectionContentDisplayConfig(surface.width, surface.height, density);
    this.logProjection(
      `地图虚拟屏清晰度：surface=${surface.width}x${surface.height}, ` +
        `render=${renderConfig.width}x${renderConfig.height}, density=${renderConfig.density}, ` +
        `scale=${renderConfig.scale}`
    );

    let displayId = -1;
    try {
      displayId = await display.createVirtualScreen({
        name: 'CarPlayer map card',
        width: renderConfig.width,
        height: renderConfig.height,
        density: renderConfig.density,
        surfaceId: surface.surfaceId,
        supportsFocus: true
      });
      if (!Number.isInteger(displayId) || displayId <= 0) {
        throw new Error('HarmonyOS 返回了无效的地图虚拟屏 ID');
      }
      if (generation !== this.mapDisplayGeneration) {
        await display.destroyVirtualScreen(displayId);
        return;
      }
      await display.setVirtualScreenSurface(displayId, surface.surfaceId);
      await display.makeUnique(displayId);
      this.mapDisplayId = displayId;
      this.activeMapSurface = surface;
      this.publishMapTouchBounds(surface);

      this.mapApp = mapApp;
      await this.launchApp(mapApp, displayId, preserveExistingAmap);
      if (generation === this.mapDisplayGeneration) {
        this.mapOnPhone = false;
        this.mapMessage = '';
        this.launchMessage = '';
        this.logProjection(`${mapApp.label}启动请求已受理：displayId=${displayId}; 目标屏实显仍需验证`);
      }
    } catch (error) {
      if (displayId >= 0) {
        if (this.mapDisplayId === displayId) {
          await this.releaseMapDisplay(false);
        } else {
          try {
          await display.destroyVirtualScreen(displayId);
          } catch (cleanupError) {
            this.logProjection(
              `清理未接管的地图虚拟屏失败：${cleanupError instanceof Error ? cleanupError.message : String(cleanupError)}`
            );
          }
        }
      }
      if (generation === this.mapDisplayGeneration) {
        this.mapMessage = '地图卡片启动失败';
        this.logProjection(`地图卡片启动失败：${error instanceof Error ? error.message : String(error)}`);
      }
    }
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
          onAppSurfaceChange: (surface): void => { void this.updateAppSurface(surface); },
          onMapSurfaceChange: (surface): void => {
            void this.updateMapSurface(surface);
          },
          onMediaLog: (message): void => this.logProjection(message),
          onAppClick: (app): void => {
            void this.selectApp(app);
          }
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