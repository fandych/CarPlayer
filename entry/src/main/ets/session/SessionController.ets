import { AirPlayMediaSessionInfo } from '../airplay/AirPlayMediaSession';
import { AudioRtpSender } from '../audio/AudioRtpSender';
import { PlaybackAudioCapture } from '../audio/PlaybackAudioCapture';
import { SessionControllerProjectionFlow } from './SessionControllerProjectionFlow';
export { SessionEvents } from './SessionControllerConnectionFlow';
export {
  isAirPlayStartReady,
  makeAirPlayServiceFromEndpoint,
  normalizeDeviceIdentifier
} from './airplay/AirPlayEndpointFactory';

export class SessionController extends SessionControllerProjectionFlow {
  protected async startAudio(media: AirPlayMediaSessionInfo, generation: number): Promise<void> {
    if (!this.running || generation !== this.airPlayGeneration) {
      return;
    }
    if (AppStorage.get<boolean>('carplayUseBluetoothAudio') === true) {
      this.events.onLog('音频方式：蓝牙 A2DP；不启动内录及 RTP 推流，音频输出跟随系统路由');
      return;
    }
    const audioSession = media.audioSession;
    if (!audioSession) {
      this.events.onLog('AirPlay 未协商到 PCM media audio stream；音频推流保持关闭');
      return;
    }
    this.events.onLog('音频方式：CarPlay RTP；准备启动播放音频内录及推流');
    let capture: PlaybackAudioCapture | undefined;
    const sender = new AudioRtpSender(
      (message: string): void => this.events.onLog(message),
      (message: string): void => {
        this.events.onLog(message);
        if (this.audioRtpSender !== sender) {
          return;
        }
        this.audioRtpSender = undefined;
        const activeCapture = this.playbackAudioCapture;
        this.playbackAudioCapture = undefined;
        if (activeCapture) {
          void activeCapture.stop().catch((error: Error): void => {
            this.events.onLog(`音频发送失败后的采集停止失败：${error.message}`);
          });
        }
        void sender.stop().catch((error: Error): void => {
          this.events.onLog(`音频发送失败后的 socket 清理失败：${error.message}`);
        });
      },
      this.wifiNetworkLease
    );
    try {
      await sender.start(audioSession);
      if (!this.running || generation !== this.airPlayGeneration) {
        await sender.stop();
        return;
      }
      this.audioRtpSender = sender;
      capture = new PlaybackAudioCapture(
        (pcm: Uint8Array): void => {
          try {
            sender.pushPcm(pcm);
          } catch (error) {
            this.events.onLog(`播放音频 PCM 推送失败：${error instanceof Error ? error.message : String(error)}`);
          }
        },
        (status: string): void => this.events.onLog(status),
        audioSession.sampleRate
      );
      this.playbackAudioCapture = capture;
      await capture.requestStart();
      if (!this.running || generation !== this.airPlayGeneration) {
        await capture.stop();
        await sender.stop();
      }
    } catch (error) {
      this.events.onLog(`AirPlay 音频推流不可用，视频会话继续：${error instanceof Error ? error.message : String(error)}`);
      if (capture) {
        try {
          await capture.stop();
        } catch (cleanupError) {
          this.events.onLog(`音频采集清理失败：${cleanupError instanceof Error ? cleanupError.message : String(cleanupError)}`);
        }
      }
      if (this.playbackAudioCapture === capture) {
        this.playbackAudioCapture = undefined;
      }
      try {
        await sender.stop();
      } catch (cleanupError) {
        this.events.onLog(`音频 RTP 清理失败：${cleanupError instanceof Error ? cleanupError.message : String(cleanupError)}`);
      }
      if (this.audioRtpSender === sender) {
        this.audioRtpSender = undefined;
      }
    }
  }
}
