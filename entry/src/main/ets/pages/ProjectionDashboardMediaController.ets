import { hilog } from '@kit.PerformanceAnalysisKit';
import batteryInfo from '@ohos.batteryInfo';
import common from '@ohos.app.ability.common';
import radio from '@ohos.telephony.radio';
import { ProjectionApp } from './ProjectionAppCatalog';
import { ProjectionMediaCommand, ProjectionMediaSnapshot } from '../session/MediaSessionBridge';
import { ProjectionMediaCoordinator } from './ProjectionMediaCoordinator';
import { ProjectionDashboardState } from './ProjectionDashboardState';

const DOMAIN: number = 0xCA22;

export class ProjectionDashboardMediaController {
  async startMediaSessionBridge(state: ProjectionDashboardState): Promise<void> {
    const coordinator = new ProjectionMediaCoordinator({
      getContext: (): common.UIAbilityContext =>
        state.getUIContext().getHostContext() as common.UIAbilityContext,
      getSnapshot: (): ProjectionMediaSnapshot => state.mediaState,
      onSnapshot: (snapshot: ProjectionMediaSnapshot): void => { state.mediaState = snapshot; },
      getApps: (): ProjectionApp[] => state.apps,
      onAppsChanged: (apps: ProjectionApp[]): void => { state.apps = apps; },
      onActionMessage: (message: string): void => { state.mediaActionMessage = message; },
      onLog: (message: string): void => state.onMediaLog(message)
    });
    state.mediaCoordinator = coordinator;
    await coordinator.start();
  }

  async sendMediaCommand(state: ProjectionDashboardState, command: ProjectionMediaCommand): Promise<void> {
    await state.mediaCoordinator?.send(command);
  }

  formatMediaTime(positionMs: number): string {
    const totalSeconds = Math.floor(Math.max(0, positionMs) / 1000);
    const minutes = Math.floor(totalSeconds / 60);
    const seconds = `${totalSeconds % 60}`.padStart(2, '0');
    return `${minutes}:${seconds}`;
  }

  async playQueueItem(state: ProjectionDashboardState, itemId: number): Promise<void> {
    await state.mediaCoordinator?.playQueueItem(itemId);
  }

  async refreshDeviceStatus(state: ProjectionDashboardState): Promise<void> {
    state.batteryPercent = Math.max(0, Math.min(100, Math.round(batteryInfo.batterySOC)));
    try {
      const slotId = await radio.getPrimarySlotId();
      const signalInfo = await radio.getSignalInformation(slotId);
      let level = 0;
      for (const item of signalInfo) {
        level = Math.max(level, item.signalLevel);
      }
      state.signalLevel = Math.max(0, Math.min(4, Math.round(level)));
      state.networkLabel = signalInfo.length > 0 ? '移动网络' : '无信号';
    } catch (_error) {
      state.signalLevel = 0;
      state.networkLabel = '网络不可用';
    }
  }

  async closeMediaSession(state: ProjectionDashboardState): Promise<void> {
    const mediaCoordinator = state.mediaCoordinator;
    state.mediaCoordinator = undefined;
    if (mediaCoordinator) {
      await mediaCoordinator.close().catch((error: Error): void => {
        hilog.error(DOMAIN, 'CarPlayerMedia', '媒体控制器释放失败：%{public}s', error.message);
      });
    }
  }
}
