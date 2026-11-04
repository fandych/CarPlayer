import abilityAccessCtrl from '@ohos.abilityAccessCtrl';
import common from '@ohos.app.ability.common';
import {
  EMPTY_PROJECTION_MEDIA,
  MediaSessionBridge,
  ProjectionMediaCommand,
  ProjectionMediaSnapshot
} from '../session/MediaSessionBridge';
import { ProjectionApp, includeMediaSessionApp } from './ProjectionAppCatalog';

interface OptimisticPlaybackState {
  isPlaying: boolean;
  expiresAt: number;
}

export interface ProjectionMediaCoordinatorCallbacks {
  getContext: () => common.UIAbilityContext;
  getSnapshot: () => ProjectionMediaSnapshot;
  onSnapshot: (snapshot: ProjectionMediaSnapshot) => void;
  onAppsChanged: (apps: ProjectionApp[]) => void;
  getApps: () => ProjectionApp[];
  onActionMessage: (message: string) => void;
  onLog: (message: string) => void;
}

export class ProjectionMediaCoordinator {
  private readonly callbacks: ProjectionMediaCoordinatorCallbacks;
  private bridge?: MediaSessionBridge;
  private timer: number = -1;
  private commandGeneration: number = 0;
  private optimisticPlaybackState?: OptimisticPlaybackState;
  private lastLoggedMediaSignature: string = '';

  constructor(callbacks: ProjectionMediaCoordinatorCallbacks) {
    this.callbacks = callbacks;
  }

  async start(): Promise<void> {
    const bridge = new MediaSessionBridge((): void => {
      const current = this.bridge;
      if (current) {
        void this.refresh(current);
      }
    });
    this.bridge = bridge;
    try {
      const context = this.callbacks.getContext();
      const manager = abilityAccessCtrl.createAtManager();
      if (manager.checkAccessTokenSync(context.applicationInfo.accessTokenId,
        'ohos.permission.MANAGE_MEDIA_RESOURCES_FOR_PUBLIC') !== 0) {
        await manager.requestPermissionsFromUser(context, ['ohos.permission.MANAGE_MEDIA_RESOURCES_FOR_PUBLIC']);
      }
    } catch (error) {
      this.callbacks.onActionMessage(
        `媒体控制授权失败：${error instanceof Error ? error.message : String(error)}`
      );
    }
    if (this.bridge !== bridge) {
      return;
    }
    await this.refresh(bridge);
    if (this.bridge === bridge) {
      this.timer = setInterval((): void => {
        void this.refresh(bridge);
      }, 1000);
    }
  }

  async close(): Promise<void> {
    if (this.timer >= 0) {
      clearInterval(this.timer);
      this.timer = -1;
    }
    this.commandGeneration++;
    this.optimisticPlaybackState = undefined;
    const bridge = this.bridge;
    this.bridge = undefined;
    await bridge?.close();
  }

  async refresh(bridge: MediaSessionBridge | undefined = this.bridge): Promise<boolean> {
    if (!bridge || bridge !== this.bridge) {
      return false;
    }
    const commandGeneration = this.commandGeneration;
    try {
      const state = await bridge.refresh();
      if (this.bridge === bridge && commandGeneration === this.commandGeneration) {
        const optimisticPlayback = this.optimisticPlaybackState;
        if (optimisticPlayback && state.isPlaying !== optimisticPlayback.isPlaying &&
          Date.now() < optimisticPlayback.expiresAt) {
          this.callbacks.onSnapshot(this.mediaStateWithPlaybackState(state, optimisticPlayback.isPlaying));
        } else {
          this.optimisticPlaybackState = undefined;
          this.callbacks.onSnapshot(state);
        }
        this.callbacks.onAppsChanged(includeMediaSessionApp(
          this.callbacks.getApps(), state.bundleName, state.abilityName
        ));
        this.logMediaSnapshotIfChanged(this.callbacks.getSnapshot());
      }
      return true;
    } catch (error) {
      if (this.bridge === bridge && commandGeneration === this.commandGeneration) {
        this.callbacks.onSnapshot(this.mediaStateWithMessage(
          `媒体会话不可用：${error instanceof Error ? error.message : String(error)}`
        ));
      }
      return false;
    }
  }

  async send(command: ProjectionMediaCommand): Promise<void> {
    const bridge = this.bridge;
    if (!bridge) {
      this.callbacks.onActionMessage('媒体控制器尚未就绪，请稍后重试');
      return;
    }
    if (!this.callbacks.getSnapshot().commands.includes(command)) {
      this.callbacks.onActionMessage(`当前音乐应用未开放${command}控制`);
      return;
    }
    const commandGeneration = ++this.commandGeneration;
    try {
      await bridge.send(command);
      if (commandGeneration !== this.commandGeneration) {
        return;
      }
      this.callbacks.onActionMessage('控制命令已发送');
      this.commandGeneration++;
      if (command === 'play' || command === 'pause') {
        const isPlaying = command === 'play';
        this.optimisticPlaybackState = { isPlaying, expiresAt: Date.now() + 2000 };
        this.callbacks.onSnapshot(this.mediaStateWithPlaybackState(this.callbacks.getSnapshot(), isPlaying));
      }
      await this.refresh(bridge);
    } catch (error) {
      if (commandGeneration === this.commandGeneration) {
        this.commandGeneration++;
        this.optimisticPlaybackState = undefined;
        this.callbacks.onActionMessage(`媒体控制失败：${error instanceof Error ? error.message : String(error)}`);
        await this.refresh(bridge);
      }
    }
  }

  async playQueueItem(itemId: number): Promise<void> {
    const bridge = this.bridge;
    if (!bridge) {
      return;
    }
    try {
      await bridge.playQueueItem(itemId);
      this.callbacks.onActionMessage('队列播放命令已发送');
      await this.refresh(bridge);
    } catch (error) {
      this.callbacks.onActionMessage(
        `播放队列项目失败：${error instanceof Error ? error.message : String(error)}`
      );
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
    this.callbacks.onLog(
      `媒体信息：${state.bundleName}/${state.abilityName ?? ''}；曲目=${state.title}；` +
        `歌手=${state.artist || '未知歌手'}；状态=${state.isPlaying ? '播放中' : '已暂停'}`
    );
  }
}
