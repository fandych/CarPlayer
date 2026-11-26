import display from '@ohos.display';
import {
  projectionContentDisplayConfig,
  projectionDisplayToggleTarget
} from '../video/CarPlayVirtualDisplay';
import { ProjectionMapSurface } from './ProjectionDashboard';
import {
  isProjectionAppLaunchable,
  ProjectionApp,
  PROJECTION_APP_CANDIDATES
} from './ProjectionAppCatalog';
import { discoverProjectionApps } from './ProjectionDashboard';
import { ProjectionHomeAppDisplay } from './ProjectionHomeAppDisplay';

export interface ProjectionHomeMapDisplayCallbacks {
  getActiveApp: () => ProjectionApp | undefined;
  getAppOnPhone: () => boolean;
  appDisplayId: () => number;
  setMapState: (app: ProjectionApp | undefined, onPhone: boolean) => void;
  setMapMessage: (message: string) => void;
  setLaunchMessage: (message: string) => void;
  isSwitching: () => boolean;
  setSwitching: (switching: boolean) => void;
  logProjection: (message: string) => void;
}

export class ProjectionHomeMapDisplay {
  app: ProjectionApp | undefined = undefined;
  displayId: number = -1;
  onPhone: boolean = false;
  activeSurface: ProjectionMapSurface | undefined = undefined;
  private displayGeneration: number = 0;
  private readonly callbacks: ProjectionHomeMapDisplayCallbacks;
  private readonly appDisplay: ProjectionHomeAppDisplay;

  constructor(callbacks: ProjectionHomeMapDisplayCallbacks, appDisplay: ProjectionHomeAppDisplay) {
    this.callbacks = callbacks;
    this.appDisplay = appDisplay;
  }

  invalidate(): void {
    this.displayGeneration++;
  }

  private publishTouchBounds(surface: ProjectionMapSurface): void {
    AppStorage.setOrCreate('carplayEmbeddedMapDisplayId', this.onPhone ? -1 : this.displayId);
    AppStorage.setOrCreate('carplayEmbeddedMapLeft', surface.left);
    AppStorage.setOrCreate('carplayEmbeddedMapTop', surface.top);
    AppStorage.setOrCreate('carplayEmbeddedMapWidth', surface.width);
    AppStorage.setOrCreate('carplayEmbeddedMapHeight', surface.height);
  }

  async releaseDisplay(restoreToPhone: boolean = true): Promise<void> {
    const displayId = this.displayId;
    const app = this.app;
    const restoreAppToPhone = restoreToPhone && !this.onPhone;
    this.app = undefined;
    this.displayId = -1;
    this.onPhone = false;
    this.activeSurface = undefined;
    this.callbacks.setMapState(undefined, false);
    AppStorage.setOrCreate('carplayEmbeddedMapDisplayId', -1);
    AppStorage.setOrCreate('carplayEmbeddedMapLeft', 0);
    AppStorage.setOrCreate('carplayEmbeddedMapTop', 0);
    AppStorage.setOrCreate('carplayEmbeddedMapWidth', 0);
    AppStorage.setOrCreate('carplayEmbeddedMapHeight', 0);
    if (displayId >= 0) {
      if (app && restoreAppToPhone) {
        try {
          await this.appDisplay.launchApp(app, display.getDefaultDisplaySync().id, app.appId === 'amap');
        } catch (error) {
          this.callbacks.logProjection(
            `释放地图屏前恢复链接失败：${error instanceof Error ? error.message : String(error)}`
          );
        }
      }
      try {
        await display.destroyVirtualScreen(displayId);
      } catch (error) {
        this.callbacks.logProjection(
          `销毁地图卡片虚拟屏失败：${error instanceof Error ? error.message : String(error)}`
        );
      }
    }
  }

  async updateSurface(surface: ProjectionMapSurface | undefined): Promise<void> {
    if (!surface) {
      this.displayGeneration++;
      await this.releaseDisplay();
      this.callbacks.setMapMessage('正在准备地图画面');
      return;
    }
    const selectedMapId = AppStorage.get<string>('carplaySelectedMapAppId') ?? 'amap';
    const generation = ++this.displayGeneration;
    const availableApps = await discoverProjectionApps();
    if (generation !== this.displayGeneration) {
      return;
    }
    const mapApp = availableApps.find((candidate: ProjectionApp): boolean =>
      candidate.appId === selectedMapId && isProjectionAppLaunchable(candidate));
    if (!mapApp) {
      await this.releaseDisplay();
      if (generation !== this.displayGeneration) {
        return;
      }
      const candidate = PROJECTION_APP_CANDIDATES.find((item: ProjectionApp): boolean =>
        item.appId === selectedMapId);
      this.callbacks.setMapMessage(candidate
        ? `${candidate.label}：${candidate.unavailableReason ?? '启动入口尚未通过本机核验'}`
        : '所选导航应用入口不可用');
      return;
    }
    const preserveExistingAmap = mapApp.appId === 'amap' && (
      (this.callbacks.getActiveApp()?.appId === 'amap' &&
        (this.callbacks.getAppOnPhone() || this.callbacks.appDisplayId() > 0)) ||
      (this.app?.appId === 'amap' && this.displayId > 0)
    );
    if (this.displayId >= 0 && this.activeSurface?.surfaceId === surface.surfaceId &&
      this.activeSurface.width === surface.width && this.activeSurface.height === surface.height) {
      this.activeSurface = surface;
      this.publishTouchBounds(surface);
      return;
    }

    await this.releaseDisplay(false);
    if (generation !== this.displayGeneration) {
      return;
    }
    this.callbacks.setMapMessage(`正在启动${mapApp.label}`);
    const density = AppStorage.get<number>('carplayProjectionDensity');
    if (density === undefined || !Number.isFinite(density) || density <= 0) {
      this.callbacks.setMapMessage('地图卡片暂不可用');
      return;
    }
    const renderConfig = projectionContentDisplayConfig(surface.width, surface.height, density);
    this.callbacks.logProjection(
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
      if (generation !== this.displayGeneration) {
        await display.destroyVirtualScreen(displayId);
        return;
      }
      await display.setVirtualScreenSurface(displayId, surface.surfaceId);
      await display.makeUnique(displayId);
      this.displayId = displayId;
      this.activeSurface = surface;
      this.publishTouchBounds(surface);

      this.app = mapApp;
      this.callbacks.setMapState(this.app, this.onPhone);
      await this.appDisplay.launchApp(mapApp, displayId, preserveExistingAmap);
      if (generation === this.displayGeneration) {
        this.onPhone = false;
        this.callbacks.setMapState(this.app, this.onPhone);
        this.callbacks.setMapMessage('');
        this.callbacks.setLaunchMessage('');
        this.callbacks.logProjection(`${mapApp.label}启动请求已受理：displayId=${displayId}; 目标屏实显仍需验证`);
      }
    } catch (error) {
      if (displayId >= 0) {
        if (this.displayId === displayId) {
          await this.releaseDisplay(false);
        } else {
          try {
            await display.destroyVirtualScreen(displayId);
          } catch (cleanupError) {
            this.callbacks.logProjection(
              `清理未接管的地图虚拟屏失败：${cleanupError instanceof Error ? cleanupError.message : String(cleanupError)}`
            );
          }
        }
      }
      if (generation === this.displayGeneration) {
        this.callbacks.setMapMessage('地图卡片启动失败');
        this.callbacks.logProjection(`地图卡片启动失败：${error instanceof Error ? error.message : String(error)}`);
      }
    }
  }

  async toggleDisplay(): Promise<void> {
    const app = this.app;
    const screenId = this.displayId;
    if (!app || screenId <= 0 || this.callbacks.isSwitching()) {
      return;
    }
    this.callbacks.setSwitching(true);
    try {
      const target = projectionDisplayToggleTarget(
        this.onPhone, display.getDefaultDisplaySync().id, screenId
      );
      await this.appDisplay.launchApp(app, target, app.appId === 'amap');
      this.onPhone = !this.onPhone;
      this.callbacks.setMapState(this.app, this.onPhone);
      if (this.activeSurface) {
        this.publishTouchBounds(this.activeSurface);
      }
      this.callbacks.setLaunchMessage('');
      this.callbacks.logProjection(`地图应用切换请求已受理：${app.label}, displayId=${target}`);
    } catch (error) {
      const message = `地图应用切换失败：${error instanceof Error ? error.message : String(error)}`;
      this.callbacks.setLaunchMessage(message);
      this.callbacks.logProjection(message);
    } finally {
      this.callbacks.setSwitching(false);
    }
  }
}
