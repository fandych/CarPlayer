import {
  EncodedH264Event,
  H264_SYNC_FRAME_FLAG,
  MAX_FRAME_QUEUE_AGE_MS,
  MAX_QUEUED_FRAMES,
  MAX_QUEUED_VIDEO_BYTES,
  containsH264Idr,
  splitH264NalUnits
} from './AirPlayVideoPackets';

export class AirPlayVideoFrameQueue {
  private sendQueue: Promise<void> = Promise.resolve();
  private queuedFrames: number = 0;
  private queuedBytes: number = 0;
  private failed: boolean = false;
  private frameGeneration: number = 0;
  private awaitingKeyFrame: boolean = false;

  constructor(
    private readonly processEvent: (event: EncodedH264Event) => Promise<void>,
    private readonly log: (message: string) => void,
    private readonly requestKeyFrame: () => void
  ) {}

  handleEncoderEvent(event: EncodedH264Event): Promise<void> {
    if (this.failed) {
      return Promise.reject(new Error('AirPlay screen stream failed; a new session is required'));
    }
    const isFrame = event.type === 'frame';
    const byteLength = isFrame ? event.data?.length ?? 0 : 0;
    if (isFrame && (this.queuedFrames >= MAX_QUEUED_FRAMES ||
      (this.queuedFrames > 0 && this.queuedBytes + byteLength > MAX_QUEUED_VIDEO_BYTES))) {
      this.beginFrameRecovery('frame/byte budget exceeded');
      return Promise.resolve();
    }
    if (isFrame && this.awaitingKeyFrame) {
      if ((event.flags & H264_SYNC_FRAME_FLAG) === 0 &&
        (!event.data || !containsH264Idr(splitH264NalUnits(event.data)))) {
        return Promise.resolve();
      }
      this.awaitingKeyFrame = false;
      this.log('AirPlay video queue recovered with a key frame');
    }
    const generation = this.frameGeneration;
    const enqueuedAt = Date.now();
    if (isFrame) {
      this.queuedFrames++;
      this.queuedBytes += byteLength;
    }
    const operation = this.sendQueue.then((): Promise<void> => {
      if (this.failed) {
        throw new Error('AirPlay screen stream failed; queued media discarded');
      }
      if (isFrame && generation !== this.frameGeneration) {
        return Promise.resolve();
      }
      if (isFrame && Date.now() - enqueuedAt > MAX_FRAME_QUEUE_AGE_MS) {
        this.beginFrameRecovery('frame queue age exceeded');
        return Promise.resolve();
      }
      return this.processEvent(event);
    }).catch((error: Error): void => {
      this.failed = true;
      throw error;
    });
    this.sendQueue = operation.then(
      (): void => this.finishQueuedEvent(isFrame, byteLength),
      (): void => this.finishQueuedEvent(isFrame, byteLength)
    );
    return operation;
  }

  async flush(): Promise<void> {
    await this.sendQueue;
  }

  requestRecoveryKeyFrame(): void {
    try {
      this.requestKeyFrame();
    } catch (error) {
      this.log(`WARN: Could not request video recovery key frame: ${error instanceof Error ? error.message : String(error)}`);
    }
  }

  private beginFrameRecovery(reason: string): void {
    if (this.awaitingKeyFrame) {
      return;
    }
    this.frameGeneration++;
    this.awaitingKeyFrame = true;
    this.log(`WARN: AirPlay video ${reason}; queuedFrames=${this.queuedFrames}, ` +
      `queuedBytes=${this.queuedBytes}; awaiting a new key frame`);
    this.requestRecoveryKeyFrame();
  }

  private finishQueuedEvent(isFrame: boolean, byteLength: number): void {
    if (!isFrame) {
      return;
    }
    this.queuedFrames--;
    this.queuedBytes -= byteLength;
    if (this.queuedFrames === 0 && this.awaitingKeyFrame) {
      this.requestRecoveryKeyFrame();
    }
  }
}
