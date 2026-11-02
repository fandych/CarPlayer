import avSession from '@ohos.multimedia.avsession';

export interface ProjectionQueueItem {
  itemId: number;
  title: string;
  subtitle: string;
}

export interface ProjectionMediaSnapshot {
  title: string;
  artist: string;
  bundleName?: string;
  abilityName?: string;
  isPlaying: boolean;
  commands: ProjectionMediaCommand[];
  queue: ProjectionQueueItem[];
  message: string;
}

export const EMPTY_PROJECTION_MEDIA: ProjectionMediaSnapshot = {
  title: '暂无播放信息',
  artist: '',
  isPlaying: false,
  commands: [],
  queue: [],
  message: '启动音乐应用后显示播放信息'
};

export type ProjectionMediaCommand = 'play' | 'pause' | 'playNext' | 'playPrevious';

export class MediaSessionBridge {
  private controller?: avSession.AVSessionController;
  private sessionId: string = '';
  private refreshing: boolean = false;
  private closed: boolean = false;
  private watchingSessions: boolean = false;
  private readonly onChange: () => void;

  constructor(onChange: () => void = (): void => {}) {
    this.onChange = onChange;
  }

  async refresh(): Promise<ProjectionMediaSnapshot> {
    if (this.closed || this.refreshing) {
      return this.snapshot;
    }
    this.refreshing = true;
    try {
      const descriptors = await avSession.getAllSessionDescriptors();
      if (this.closed) {
        return this.snapshot;
      }
      if (!this.watchingSessions) {
        avSession.onSessionCreate(this.onChange);
        avSession.onSessionDestroy(this.onChange);
        avSession.onTopSessionChange(this.onChange);
        this.watchingSessions = true;
      }
      const activeSession = descriptors.find((descriptor: avSession.AVSessionDescriptor): boolean =>
        descriptor.isTopSession && descriptor.isActive && descriptor.type === 'audio') ??
        descriptors.find((descriptor: avSession.AVSessionDescriptor): boolean =>
          descriptor.isActive && descriptor.type === 'audio') ??
        descriptors.find((descriptor: avSession.AVSessionDescriptor): boolean =>
          descriptor.sessionId === this.sessionId && descriptor.type === 'audio');
      if (!activeSession) {
        await this.releaseController();
        this.snapshot = {
          title: EMPTY_PROJECTION_MEDIA.title,
          artist: EMPTY_PROJECTION_MEDIA.artist,
          isPlaying: EMPTY_PROJECTION_MEDIA.isPlaying,
          commands: [],
          queue: [],
          message: '未检测到活动音乐会话'
        };
        return this.snapshot;
      }

      if (this.sessionId !== activeSession.sessionId || !this.controller) {
        await this.releaseController();
        const controller = await avSession.createController(activeSession.sessionId);
        if (this.closed) {
          await controller.destroy();
          return this.snapshot;
        }
        this.controller = controller;
        this.sessionId = activeSession.sessionId;
        controller.on('metadataChange', ['title', 'artist', 'author'], this.onChange);
        controller.on('playbackStateChange', ['state'], this.onChange);
        controller.on('validCommandChange', this.onChange);
        controller.on('sessionDestroy', this.onChange);
      }
      const controller = this.controller;
      const metadata = await controller.getAVMetadata();
      const playbackState = await controller.getAVPlaybackState();
      const validCommands = await controller.getValidCommands();
      const mediaCommands: ProjectionMediaCommand[] = ['play', 'pause', 'playNext', 'playPrevious'];
      const commands: ProjectionMediaCommand[] = [];
      for (const command of mediaCommands) {
        if (validCommands.includes(command)) {
          commands.push(command);
        }
      }
      let queue: ProjectionQueueItem[] = [];
      let queueMessage = '';
      try {
        const items = await controller.getAVQueueItems();
        queue = items.map((item: avSession.AVQueueItem): ProjectionQueueItem => ({
          itemId: item.itemId,
          title: item.description?.title ?? '',
          subtitle: item.description?.subtitle ?? item.description?.description ?? ''
        })).filter((item: ProjectionQueueItem): boolean => item.title.length > 0);
      } catch (error) {
        queueMessage = `当前应用未提供播放队列：${error instanceof Error ? error.message : String(error)}`;
      }
      let message = queueMessage;
      if (commands.length === 0) {
        message = message.length > 0
          ? `当前音乐应用未开放播放控制；${message}`
          : '当前音乐应用未开放播放控制';
      } else if (message.length === 0) {
        message = '媒体会话已连接';
      }
      this.snapshot = {
        title: metadata.title ?? '未知曲目',
        artist: metadata.artist ?? metadata.author ?? '',
        bundleName: activeSession.elementName.bundleName,
        abilityName: activeSession.elementName.abilityName,
        isPlaying: playbackState.state === avSession.PlaybackState.PLAYBACK_STATE_PLAY,
        commands,
        queue,
        message
      };
      return this.snapshot;
    } finally {
      this.refreshing = false;
    }
  }

  async send(command: ProjectionMediaCommand): Promise<void> {
    await this.refresh();
    const controller = this.controller;
    if (!controller) {
      throw new Error('当前没有可控制的活动媒体会话');
    }
    const validCommands = await controller.getValidCommands();
    if (!validCommands.includes(command)) {
      throw new Error(`当前音乐应用未开放${command}控制`);
    }
    await controller.sendControlCommand({ command });
  }

  async playQueueItem(itemId: number): Promise<void> {
    const controller = this.controller;
    if (!controller) {
      throw new Error('当前没有可浏览的活动媒体队列');
    }
    await controller.skipToQueueItem(itemId);
  }

  async close(): Promise<void> {
    this.closed = true;
    try {
      if (this.watchingSessions) {
        this.watchingSessions = false;
        avSession.offSessionCreate(this.onChange);
        avSession.offSessionDestroy(this.onChange);
        avSession.offTopSessionChange(this.onChange);
      }
    } finally {
      await this.releaseController();
    }
  }

  private snapshot: ProjectionMediaSnapshot = EMPTY_PROJECTION_MEDIA;

  private async releaseController(): Promise<void> {
    const controller = this.controller;
    this.controller = undefined;
    this.sessionId = '';
    if (controller) {
      controller.off('metadataChange');
      controller.off('playbackStateChange');
      controller.off('validCommandChange');
      controller.off('sessionDestroy');
      await controller.destroy();
    }
  }
}
