import display from '@ohos.display';
import { isSupportedProjectionSize } from './ProjectionSettings';

export interface CarPlayDisplaySize {
  width: number;
  height: number;
}

export function projectionDisplayDensity(width: number): number {
  return Math.max(0.5, Math.min(3, width / 960));
}

export function projectionDisplayToggleTarget(
  currentlyOnPhone: boolean, phoneDisplayId: number, virtualDisplayId: number
): number {
  return currentlyOnPhone ? virtualDisplayId : phoneDisplayId;
}

export class CarPlayVirtualDisplay {
  private screenId: number = -1;
  private log: (message: string) => void = (_message: string): void => {};

  get id(): number {
    return this.screenId;
  }

  async create(
    surfaceId: string,
    size: CarPlayDisplaySize,
    log: (message: string) => void
  ): Promise<number> {
    this.log = log;
    this.log(`虚拟屏参数校验：surfaceId=${surfaceId || 'capture-only'}, size=${size.width}x${size.height}`);
    if (this.screenId >= 0) {
      throw new Error('CarPlay virtual display is already active');
    }
    if (!isSupportedProjectionSize(size.width, size.height)) {
      throw new Error('Invalid CarPlay virtual display parameters');
    }
    try {
      const density = projectionDisplayDensity(size.width);
      this.log(`虚拟屏创建请求：name=Harmony CarPlay, size=${size.width}x${size.height}, density=${density}, ` +
        `surface=${surfaceId ? 'bound' : 'capture-only'}, supportsFocus=true`);
      this.screenId = await display.createVirtualScreen({
        name: 'Harmony CarPlay',
        width: size.width,
        height: size.height,
        density,
        surfaceId,
        supportsFocus: true
      });
      if (!Number.isInteger(this.screenId) || this.screenId <= 0) {
        this.screenId = -1;
        throw new Error('HarmonyOS returned an invalid virtual display ID');
      }
      AppStorage.setOrCreate('carplayProjectionDensity', density);
      this.log(`虚拟屏创建成功：displayId=${this.screenId}`);
      if (surfaceId) {
        await display.setVirtualScreenSurface(this.screenId, surfaceId);
        this.log(`虚拟屏输出 Surface 已确认绑定：displayId=${this.screenId}, surfaceId=${surfaceId}`);
      }
      await display.makeUnique(this.screenId);
      this.log(`虚拟屏已切换为独立显示模式：displayId=${this.screenId}`);
      return this.screenId;
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      this.log(`虚拟屏创建失败：${message}`);
      throw new Error(`创建 CarPlay 虚拟屏失败：${message}`);
    }
  }

  async destroy(): Promise<void> {
    const screenId = this.screenId;
    this.screenId = -1;
    if (screenId < 0) {
      return;
    }
    try {
      this.log(`开始销毁虚拟屏：displayId=${screenId}`);
      await display.destroyVirtualScreen(screenId);
      this.screenId = -1;
      this.log(`虚拟屏销毁成功：displayId=${screenId}`);
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      this.screenId = screenId;
      this.log(`虚拟屏销毁失败：displayId=${screenId}, error=${message}`);
      throw new Error(`销毁 CarPlay 虚拟屏失败：${message}`);
    }
  }
}
