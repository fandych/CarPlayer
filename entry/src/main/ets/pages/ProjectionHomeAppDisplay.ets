import common from '@ohos.app.ability.common';
import display from '@ohos.display';
import {
  projectionContentDisplayConfig,
  projectionDisplayToggleTarget
} from '../video/CarPlayVirtualDisplay';
import { ProjectionMapSurface } from './ProjectionDashboard';
import { ProjectionApp } from './ProjectionAppCatalog';
import { launchProjectionApp } from './ProjectionAppLauncher';

export interface ProjectionHomeAppDisplayCallbacks {
  getHostContext: () => common.UIAbilityContext;
  getActiveApp: () => ProjectionApp | undefined;
  getAppOnPhone: () => boolean;
  setAppOnPhone: (onPhone: boolean) => void;
  setLaunchMessage: (message: string) => void;
  getLaunchMessage: () => string;
  isSwitching: () => boolean;
  setSwitching: (switching: boolean) => void;
  logProjection: (message: string) => void;
}

export class ProjectionHomeAppDisplay {
  displayId: number = -1;
  contentWidth: number = 0;
  contentHeight: number = 0;
  activeSurface?: ProjectionMapSurface;
  moveExistingInstance: boolean = false;
  private surfaceAttached: boolean = false;
  private displayGeneration: number = 0;
  private surfaceGeneration: number = 0;
  private readonly callbacks: ProjectionHomeAppDisplayCallbacks;

  constructor(callbacks: ProjectionHomeAppDisplayCallbacks) {
    this.callbacks = callbacks;
  }

  invalidate(): void {
    this.displayGeneration++;
  }

  async launchApp(app: ProjectionApp, displayId: number, preserveExistingInstance: boolean = false): Promise<void> {
    await launchProjectionApp(
      (): common.UIAbilityContext => this.callbacks.getHostContext(),
      app,
      displayId,
      preserveExistingInstance
    );
  }

  publishTouchBounds(surface?: ProjectionMapSurface): void {
    AppStorage.setOrCreate('carplayEmbeddedAppDisplayId',
      surface && !this.callbacks.getAppOnPhone() ? this.displayId : -1);
    AppStorage.setOrCreate('carplayEmbeddedAppLeft', surface?.left ?? 0);
    AppStorage.setOrCreate('carplayEmbeddedAppTop', surface?.top ?? 0);
    AppStorage.setOrCreate('carplayEmbeddedAppWidth', surface?.width ?? 0);
    AppStorage.setOrCreate('carplayEmbeddedAppHeight', surface?.height ?? 0);
    AppStorage.setOrCreate('carplayEmbeddedAppContentWidth', this.contentWidth);
    AppStorage.setOrCreate('carplayEmbeddedAppContentHeight', this.contentHeight);
  }

  async releaseDisplay(): Promise<void> {
    const screenId = this.displayId;
    this.displayId = -1;
    this.contentWidth = 0;
    this.contentHeight = 0;
    this.activeSurface = undefined;
    this.surfaceAttached = false;
    this.surfaceGeneration++;
    this.publishTouchBounds();
    if (screenId <= 0) {
      return;
    }
    try {
      const activeApp = this.callbacks.getActiveApp();
      if (activeApp && !this.callbacks.getAppOnPhone()) {
        await this.launchApp(activeApp, display.getDefaultDisplaySync().id, activeApp.appId === 'amap');
        this.callbacks.setAppOnPhone(true);
      }
    } catch (error) {
      this.callbacks.logProjection(
        `释放内容屏前恢复应用失败：${error instanceof Error ? error.message : String(error)}`
      );
    }
    try {
      await display.destroyVirtualScreen(screenId);
    } catch (error) {
      this.callbacks.logProjection(
        `销毁应用内容屏失败：${error instanceof Error ? error.message : String(error)}`
      );
    }
  }

  async updateSurface(surface?: ProjectionMapSurface): Promise<void> {
    if (!surface) {
      this.displayGeneration++;
      this.surfaceGeneration++;
      this.surfaceAttached = false;
      this.publishTouchBounds();
      return;
    }
    let displayReleased: boolean = false;
    if (this.displayId > 0 && this.activeSurface &&
      (this.activeSurface.width !== surface.width || this.activeSurface.height !== surface.height)) {
      const generation = ++this.displayGeneration;
      await this.releaseDisplay();
      if (generation !== this.displayGeneration) {
        return;
      }
      displayReleased = true;
    }
    if (this.displayId > 0 && this.activeSurface) {
      const screenId = this.displayId;
      const surfaceGeneration = ++this.surfaceGeneration;
      try {
        if (!this.surfaceAttached || this.activeSurface.surfaceId !== surface.surfaceId) {
          await display.setVirtualScreenSurface(screenId, surface.surfaceId);
        }
        if (this.displayId !== screenId || surfaceGeneration !== this.surfaceGeneration) {
          return;
        }
      } catch (error) {
        if (this.displayId !== screenId || surfaceGeneration !== this.surfaceGeneration) {
          return;
        }
        const message = `应用画面更新失败：${error instanceof Error ? error.message : String(error)}`;
        this.callbacks.setLaunchMessage(message);
        this.callbacks.logProjection(message);
        return;
      }
      this.activeSurface = surface;
      this.surfaceAttached = true;
      if (this.callbacks.getLaunchMessage().startsWith('应用画面更新失败：')) {
        this.callbacks.setLaunchMessage('');
      }
      this.publishTouchBounds(surface);
      return;
    }
    const generation = ++this.displayGeneration;
    this.callbacks.setSwitching(true);
    if (!displayReleased) {
      await this.releaseDisplay();
    }
    if (generation !== this.displayGeneration) {
      this.callbacks.setSwitching(false);
      return;
    }
    let screenId = -1;
    try {
      const density = AppStorage.get<number>('carplayProjectionDensity');
      if (!density || !Number.isFinite(density) || density <= 0) {
        throw new Error('投影显示密度不可用');
      }
      const renderConfig = projectionContentDisplayConfig(surface.width, surface.height, density);
      this.callbacks.logProjection(
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
      if (generation !== this.displayGeneration) {
        await display.destroyVirtualScreen(screenId);
        return;
      }
      this.displayId = screenId;
      this.contentWidth = renderConfig.width;
      this.contentHeight = renderConfig.height;
      this.activeSurface = surface;
      this.surfaceAttached = true;
      const activeApp = this.callbacks.getActiveApp();
      if (activeApp) {
        await this.launchApp(activeApp, screenId, this.moveExistingInstance);
        this.moveExistingInstance = false;
        this.callbacks.setAppOnPhone(false);
        this.callbacks.setLaunchMessage('');
      }
      this.publishTouchBounds(this.activeSurface);
    } catch (error) {
      if (screenId > 0 && this.displayId !== screenId) {
        await display.destroyVirtualScreen(screenId).catch((): void => {});
      }
      const message = `应用内容屏启动失败：${error instanceof Error ? error.message : String(error)}`;
      this.callbacks.setLaunchMessage(message);
      this.callbacks.logProjection(message);
    } finally {
      this.callbacks.setSwitching(false);
    }
  }

  async toggleDisplay(): Promise<void> {
    const app = this.callbacks.getActiveApp();
    if (!app || this.displayId <= 0 || this.callbacks.isSwitching()) {
      return;
    }
    this.callbacks.setSwitching(true);
    try {
      const target = projectionDisplayToggleTarget(
        this.callbacks.getAppOnPhone(), display.getDefaultDisplaySync().id, this.displayId
      );
      await this.launchApp(app, target, app.appId === 'amap');
      this.callbacks.setAppOnPhone(!this.callbacks.getAppOnPhone());
      this.publishTouchBounds(this.activeSurface);
      this.callbacks.setLaunchMessage('');
      this.callbacks.logProjection(
        `应用启动请求已受理：${app.label}, displayId=${target}; target rendering is not verified`
      );
    } catch (error) {
      const message = `应用链接打开失败：${error instanceof Error ? error.message : String(error)}`;
      this.callbacks.setLaunchMessage(message);
      this.callbacks.logProjection(message);
    } finally {
      this.callbacks.setSwitching(false);
    }
  }
}
