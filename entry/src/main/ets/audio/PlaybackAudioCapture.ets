import audio from '@ohos.multimedia.audio';
import { CarAudioOutput, scalePlaybackPcm } from './CarAudioOutput';

export type PcmDataHandler = (data: Uint8Array) => void;

export class PlaybackAudioCapture {
  private capturer?: audio.AudioCapturer;
  private readHandler?: (data: ArrayBuffer) => void;
  private interruptHandler?: (event: audio.InterruptEvent) => void;
  private readonly onPcmData: PcmDataHandler;
  private readonly onStatus: (status: string) => void;
  private readonly sampleRate: number;
  private started: boolean = false;
  private firstPcmLogged: boolean = false;
  private generation: number = 0;
  private cancelStart?: () => void;
  private readonly carOutput: CarAudioOutput = new CarAudioOutput();

  constructor(onPcmData: PcmDataHandler, onStatus: (status: string) => void, sampleRate: number = 48000) {
    this.onPcmData = onPcmData;
    this.onStatus = onStatus;
    if (sampleRate !== 44100 && sampleRate !== 48000) {
      throw new Error(`Unsupported playback capture sample rate ${sampleRate}`);
    }
    this.sampleRate = sampleRate;
  }

  async requestStart(): Promise<void> {
    if (this.capturer) {
      throw new Error('播放音频采集已经初始化');
    }
    const generation = ++this.generation;
    const streamInfo: audio.AudioStreamInfo = {
      samplingRate: this.sampleRate === 44100
        ? audio.AudioSamplingRate.SAMPLE_RATE_44100
        : audio.AudioSamplingRate.SAMPLE_RATE_48000,
      channels: audio.AudioChannel.CHANNEL_2,
      sampleFormat: audio.AudioSampleFormat.SAMPLE_FORMAT_S16LE,
      encodingType: audio.AudioEncodingType.ENCODING_TYPE_RAW
    };
    const capturerInfo: audio.AudioCapturerInfo = {
      source: audio.SourceType.SOURCE_TYPE_PLAYBACK_CAPTURE,
      capturerFlags: 0
    };
    const options: audio.AudioCapturerOptions = {
      streamInfo,
      capturerInfo,
      playbackCaptureMode: audio.AudioPlaybackCaptureMode.MODE_DEFAULT
    };
    this.onStatus('播放音频采集模式：MODE_DEFAULT（包含系统允许捕获的媒体及导航；切屏不重建采集）');
    const capturer = await audio.createAudioCapturer(options);
    if (generation !== this.generation) {
      await capturer.release();
      return;
    }
    this.capturer = capturer;
    const strategy: audio.AudioSessionStrategy = {
      concurrencyMode: audio.AudioConcurrencyMode.CONCURRENCY_MIX_WITH_OTHERS
    };
    try {
      capturer.setIndependentAudioSessionStrategy(strategy, audio.AudioSessionBehaviorFlags.DEFAULT_BEHAVIOR);
      this.onStatus('播放音频采集焦点策略：CONCURRENCY_MIX_WITH_OTHERS');
    } catch (error) {
      await capturer.release();
      this.capturer = undefined;
      throw new Error(`设置播放音频混音策略失败：${error instanceof Error ? error.message : String(error)}`);
    }
    this.interruptHandler = (event: audio.InterruptEvent): void => {
      this.onStatus(
        `播放音频采集焦点事件：force=${event.forceType}, hint=${event.hintType}, ` +
          `captureRunning=${this.started}`
      );
    };
    this.readHandler = (data: ArrayBuffer): void => {
      if (this.capturer !== capturer || !this.started) {
        return;
      }
      const pcm = new Uint8Array(data);
      if (!this.firstPcmLogged && pcm.length > 0) {
        this.firstPcmLogged = true;
        this.onStatus(`播放音频捕获已收到 PCM：${pcm.length} 字节，${this.sampleRate}Hz`);
      }
      this.onPcmData(scalePlaybackPcm(pcm, AppStorage.get<number>('carplayRemoteVolume') ?? 100));
    };
    try {
      capturer.on('audioInterrupt', this.interruptHandler);
      capturer.on('readData', this.readHandler);
      this.onStatus('等待系统授权播放音频捕获');
      await new Promise<void>((resolve, reject) => {
        this.cancelStart = (): void => reject(new Error('播放音频捕获启动已取消'));
        capturer.requestPlaybackCaptureStart((state: audio.PlaybackCaptureStartState): void => {
          if (this.capturer !== capturer || generation !== this.generation) {
            return;
          }
          this.cancelStart = undefined;
          if (state !== audio.PlaybackCaptureStartState.STATE_SUCCESS) {
            reject(new Error(state === audio.PlaybackCaptureStartState.STATE_NOT_AUTHORIZED
              ? '播放音频捕获未获用户授权' : '播放音频捕获启动失败'));
            return;
          }
          this.started = true;
          this.onStatus('已授权捕获播放音频，正在推送 PCM 到车机');
          resolve();
        });
      });
      if (generation === this.generation && this.capturer === capturer) {
        try {
          await this.carOutput.start();
          if (generation !== this.generation || this.capturer !== capturer) {
            await this.carOutput.stop();
          } else {
            this.onStatus('手机系统媒体音量已接管投屏音频增益');
          }
        } catch (error) {
          this.onStatus(`手机音量同步不可用：${error instanceof Error ? error.message : String(error)}`);
        }
      }
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      await this.stop();
      throw new Error(`请求播放音频捕获失败：${message}`);
    }
  }

  async stop(): Promise<void> {
    this.generation++;
    const cancelStart = this.cancelStart;
    this.cancelStart = undefined;
    cancelStart?.();
    const failures: string[] = [];
    try {
      await this.carOutput.stop();
    } catch (error) {
      failures.push(`释放手机音量监听失败：${error instanceof Error ? error.message : String(error)}`);
    }
    const capturer = this.capturer;
    if (!capturer) {
      if (failures.length > 0) {
        throw new Error(failures.join('; '));
      }
      return;
    }
    if (this.readHandler) {
      try {
        capturer.off('readData', this.readHandler);
      } catch (error) {
        failures.push(error instanceof Error ? error.message : String(error));
      }
    }
    this.readHandler = undefined;
    if (this.interruptHandler) {
      try {
        capturer.off('audioInterrupt');
      } catch (error) {
        failures.push(`取消音频焦点监听：${error instanceof Error ? error.message : String(error)}`);
      }
    }
    this.interruptHandler = undefined;
    this.capturer = undefined;
    if (this.started) {
      try {
        await capturer.stop();
      } catch (error) {
        failures.push(error instanceof Error ? error.message : String(error));
      }
    }
    this.started = false;
    try {
      await capturer.release();
    } catch (error) {
      failures.push(error instanceof Error ? error.message : String(error));
    }
    if (failures.length > 0) {
      throw new Error(`音频采集资源释放失败：${failures.join('; ')}`);
    }
    this.onStatus('播放音频捕获已停止');
    this.firstPcmLogged = false;
  }
}
