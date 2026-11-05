import common from '@ohos.app.ability.common';
import backgroundTaskManager from '@ohos.resourceschedule.backgroundTaskManager';
import wantAgent from '@ohos.app.ability.wantAgent';

interface BackgroundTaskErrorDetails {
  code?: number | string;
  message?: string;
}

export class CarPlayBackgroundTask {
  private readonly context: common.UIAbilityContext;
  private active: boolean = false;
  private starting: boolean = false;
  private cancelledDuringStart: boolean = false;
  private startOperation?: Promise<void>;
  private cancelHandler?: (info: backgroundTaskManager.ContinuousTaskCancelInfo) => void;

  constructor(context: common.UIAbilityContext) {
    this.context = context;
  }

  async start(onCancelled: (reason: string) => void): Promise<void> {
    if (this.active) {
      return;
    }
    if (this.startOperation) {
      await this.startOperation;
      return;
    }
    const operation = this.startInternal(onCancelled);
    this.startOperation = operation;
    try {
      await operation;
    } finally {
      if (this.startOperation === operation) {
        this.startOperation = undefined;
      }
    }
  }

  async stop(): Promise<void> {
    const pendingStart = this.startOperation;
    if (pendingStart) {
      await pendingStart;
    }
    const failures: string[] = [];
    const handler = this.cancelHandler;
    if (handler) {
      try {
        backgroundTaskManager.off('continuousTaskCancel', handler);
        this.cancelHandler = undefined;
      } catch (error) {
        failures.push(`取消长时任务撤销监听失败：${this.errorMessage(error)}`);
      }
    }
    if (this.active) {
      try {
        await backgroundTaskManager.stopBackgroundRunning(this.context);
        this.active = false;
      } catch (error) {
        failures.push(`停止多设备连接长时任务失败：${this.errorMessage(error)}`);
      }
    }
    if (failures.length > 0) {
      throw new Error(failures.join('；'));
    }
  }

  private async startInternal(onCancelled: (reason: string) => void): Promise<void> {
    this.starting = true;
    this.cancelledDuringStart = false;
    const handler = (info: backgroundTaskManager.ContinuousTaskCancelInfo): void => {
      if (!this.active && !this.starting) {
        return;
      }
      if (this.starting) {
        this.cancelledDuringStart = true;
      }
      this.active = false;
      onCancelled(String(info.reason));
    };
    try {
      backgroundTaskManager.on('continuousTaskCancel', handler);
      this.cancelHandler = handler;
      const info: wantAgent.WantAgentInfo = {
        wants: [{
          bundleName: 'com.fandy.carplayer',
          abilityName: 'EntryAbility'
        }],
        actionType: wantAgent.OperationType.START_ABILITY,
        requestCode: 0,
        actionFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
      };
      const agent = await wantAgent.getWantAgent(info);
      if (!agent) {
        throw new Error('系统未能创建后台任务通知的点击动作');
      }
      await backgroundTaskManager.startBackgroundRunning(
        this.context,
        backgroundTaskManager.BackgroundMode.MULTI_DEVICE_CONNECTION,
        agent
      );
      if (this.cancelledDuringStart) {
        await backgroundTaskManager.stopBackgroundRunning(this.context);
        throw new Error('多设备连接长时任务在启动期间被系统取消');
      }
      this.active = true;
    } catch (error) {
      const message = this.errorMessage(error);
      const failures: string[] = [];
      const currentHandler = this.cancelHandler;
      this.cancelHandler = undefined;
      if (currentHandler) {
        try {
          backgroundTaskManager.off('continuousTaskCancel', currentHandler);
        } catch (cleanupError) {
          failures.push(`取消撤销监听失败：${this.errorMessage(cleanupError)}`);
        }
      }
      if (this.active) {
        try {
          await backgroundTaskManager.stopBackgroundRunning(this.context);
        } catch (cleanupError) {
          failures.push(`清理已启动的长时任务失败：${this.errorMessage(cleanupError)}`);
        } finally {
          this.active = false;
        }
      }
      throw new Error(
        `申请多设备连接后台长时任务失败：${message}${failures.length > 0 ? `；${failures.join('；')}` : ''}`
      );
    } finally {
      this.starting = false;
      this.cancelledDuringStart = false;
    }
  }

  private errorMessage(error: Error | Object): string {
    if (error instanceof Error) {
      return error.message;
    }
    const details = error as BackgroundTaskErrorDetails;
    return details.code === undefined
      ? details.message ?? String(error)
      : `code=${details.code}: ${details.message ?? ''}`;
  }
}
