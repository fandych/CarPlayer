import emitter from '@ohos.events.emitter';
import { AirPlayPairingClient } from '../airplay/AirPlayPairingClient';
import { AirPlayMediaSessionInfo } from '../airplay/AirPlayMediaSession';
import { EncodedH264Event } from '../airplay/AirPlayVideoStream';
import { resolveProjectionRates } from '../video/ProjectionSettings';
import { CARPLAY_RECEIVER_HOME_EVENT } from '../video/CarPlayTouchInput';
import { SessionControllerAirPlayControl } from './SessionControllerAirPlayControl';

export abstract class SessionControllerProjectionFlow extends SessionControllerAirPlayControl {
  protected async startProjection(
    media: AirPlayMediaSessionInfo,
    pairing: AirPlayPairingClient,
    generation: number
  ): Promise<void> {
    if (!this.isCurrentAirPlaySession(pairing, generation)) {
      return;
    }
    AppStorage.setOrCreate('carplayVehicleDisplayUuid', media.displayUuid);
    AppStorage.setOrCreate('carplayProjectionNativeWidth', media.nativeDisplayWidth);
    AppStorage.setOrCreate('carplayProjectionNativeHeight', media.nativeDisplayHeight);
    AppStorage.setOrCreate('carplayProjectionOutputWidth', media.displayWidth);
    AppStorage.setOrCreate('carplayProjectionOutputHeight', media.displayHeight);
    AppStorage.setOrCreate('carplayProjectionViewAreaX', media.viewArea.originX);
    AppStorage.setOrCreate('carplayProjectionViewAreaY', media.viewArea.originY);
    AppStorage.setOrCreate('carplayProjectionViewAreaWidth', media.viewArea.width);
    AppStorage.setOrCreate('carplayProjectionViewAreaHeight', media.viewArea.height);
    this.events.onLog(
      `显示尺寸计算：DiPlay type=${media.displayType} canvas=${media.nativeDisplayWidth}x${media.nativeDisplayHeight}, ` +
        `H.264=${media.displayWidth}x${media.displayHeight}, ` +
        `activeViewArea=${media.viewArea.width}x${media.viewArea.height}@${media.viewArea.originX},${media.viewArea.originY}`
    );
    AppStorage.setOrCreate('carplayProjectionDisplayModes', media.availableDisplayModes);
    AppStorage.setOrCreate('carplayProjectionActiveModeId', media.displayModeId);
    AppStorage.setOrCreate('carplayProjectionResolutionMessage', media.resolutionMessage);
    const rates = resolveProjectionRates(media.maxFrameRate,
      AppStorage.get<number>('carplayEncoderFps') ?? 30, AppStorage.get<number>('carplayCaptureFps') ?? 60);
    const bitrate = Math.max(1_500_000, Math.min(10_000_000, media.displayWidth * media.displayHeight * 5));
    this.videoFrameCount = 0;
    this.videoCodecConfigCount = 0;
    this.events.onLog(
      `指定屏幕 H.264 采集请求：size=${media.displayWidth}x${media.displayHeight}, ` +
        `fps=${rates.encode}, captureFps=${rates.capture}, bitrate=${bitrate}, format=video/avc`
    );
    let displayId = -1;
    try {
      await this.requestPermissions(['ohos.permission.CUSTOM_SCREEN_CAPTURE']);
      if (!this.isCurrentAirPlaySession(pairing, generation)) {
        return;
      }
      displayId = await this.projectionDisplay.create('', {
        width: media.displayWidth,
        height: media.displayHeight
      }, (message: string): void => this.events.onLog(message));
      if (!this.isCurrentAirPlaySession(pairing, generation)) {
        await this.stopProjection();
        return;
      }
      await this.events.onProjectionReady(displayId, media.displayWidth, media.displayHeight);
      if (!this.isCurrentAirPlaySession(pairing, generation)) {
        await this.stopProjection();
        return;
      }
      if (!this.isCurrentAirPlaySession(pairing, generation)) {
        await this.stopProjection();
        return;
      }
      this.touchInput.start(displayId, media.displayWidth, media.displayHeight);
      pairing.setTouchReportHandler((report: Uint8Array): void => this.touchInput.handleReport(report));
      pairing.setNightModeHandler((night: boolean): void => {
        if (this.isCurrentAirPlaySession(pairing, generation)) {
          AppStorage.setOrCreate('carplayNightMode', night);
        }
      });
      emitter.on(CARPLAY_RECEIVER_HOME_EVENT, this.receiverHomeHandler);
      this.events.onLog('车机触摸事件仅路由至 CarPlayer Shell；Phone 端第三方 APP 输入未验证，保持禁用');
      let videoSendFailed = false;
      const onVideoEvent = (event: EncodedH264Event): void => {
        if (!this.isCurrentAirPlaySession(pairing, generation) || videoSendFailed) {
          return;
        }
        if (event.type === 'diagnostic') {
          this.events.onLog(`AVScreenCapture native 阶段：${event.message ?? 'no detail'}`);
          return;
        }
        if (event.type === 'overflow') {
          this.events.onLog('AVScreenCapture 回调队列过载；停止发送以避免视频不同步');
        }
        const byteLength = event.data?.length ?? 0;
        if (event.type === 'codecConfig') {
          this.videoCodecConfigCount++;
          this.events.onLog(
            `H.264 编码配置回调 #${this.videoCodecConfigCount}：bytes=${byteLength}, ` +
              `pts=${event.timestampUs}, flags=0x${event.flags.toString(16)}`
          );
        } else if (event.type === 'frame') {
          this.videoFrameCount++;
          if (this.videoFrameCount <= 3 || this.videoFrameCount % 120 === 0) {
            this.events.onLog(
              `H.264 输出帧 #${this.videoFrameCount}：bytes=${byteLength}, ` +
                `pts=${event.timestampUs}, flags=0x${event.flags.toString(16)}`
            );
          }
        } else if (event.type === 'error') {
          this.events.onLog(`ERROR: AVScreenCapture 异步错误：${event.message ?? 'no detail'}`);
        }
        void pairing.pushEncodedVideo(event).catch((error: Error): void => {
          if (!this.isCurrentAirPlaySession(pairing, generation) || videoSendFailed) {
            return;
          }
          videoSendFailed = true;
          this.reportError(new Error(`AirPlay H.264 帧发送失败：${error.message}\n${error.stack ?? ''}`));
          void this.stopProjection().catch((cleanupError: Error): void => {
            this.reportError(`H.264 失败后清理投屏资源失败：${cleanupError.message}`);
          });
        });
      };
      this.videoEncoder.start({
        width: media.displayWidth,
        height: media.displayHeight,
        frameRate: rates.encode,
        bitrate
      }, onVideoEvent);
      pairing.setForceKeyFrameHandler((): void => {
        try {
          this.videoEncoder.requestKeyFrame();
        } catch (error) {
          this.events.onLog(`H.264 关键帧请求失败：${error instanceof Error ? error.message : String(error)}`);
        }
      });
      this.videoCapture.start({
        displayId,
        width: media.displayWidth,
        height: media.displayHeight,
        frameRate: rates.capture,
        bitrate,
        encoderHandle: this.videoEncoder.handle
      }, onVideoEvent);
      AppStorage.setOrCreate('carplayActiveEncoderFps', rates.encode);
      AppStorage.setOrCreate('carplayActiveCaptureFps', rates.capture);
      this.events.onLog(`指定屏幕 H.264 采集已启动：displayId=${displayId}`);
      this.events.onLog(
        `CarPlay 虚拟屏编码输出已建立：id=${displayId}, ${media.displayWidth}x${media.displayHeight}, ` +
          `${rates.encode}fps, capture=${rates.capture}fps`
      );
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      this.events.onLog(`ERROR: 投影启动流程失败：displayId=${displayId}, error=${message}`);
      const failures: string[] = [];
      this.touchInput.stop();
      pairing.setTouchReportHandler(undefined);
      try {
        this.videoCapture.stop();
      } catch (cleanupError) {
        failures.push(cleanupError instanceof Error ? cleanupError.message : String(cleanupError));
      }
      try {
        this.videoEncoder.stop();
      } catch (cleanupError) {
        failures.push(cleanupError instanceof Error ? cleanupError.message : String(cleanupError));
      }
      try {
        await this.projectionDisplay.destroy();
      } catch (cleanupError) {
        failures.push(cleanupError instanceof Error ? cleanupError.message : String(cleanupError));
      }
      pairing.setForceKeyFrameHandler(undefined);
      if (failures.length > 0) {
        throw new Error(`${message}; cleanup failed: ${failures.join('; ')}`);
      }
      throw error instanceof Error ? error : new Error(message);
    }
  }
  protected async stopProjection(): Promise<void> {
    const displayId = this.projectionDisplay.id;
    const failures: string[] = [];
    if (displayId >= 0 && this.events.onProjectionStopping) {
      try {
        await this.events.onProjectionStopping();
      } catch (error) {
        this.events.onLog(`离车时暂停音乐失败：${error instanceof Error ? error.message : String(error)}`);
      }
    }
    this.touchInput.stop();
    emitter.off(CARPLAY_RECEIVER_HOME_EVENT, this.receiverHomeHandler);
    this.activePairing?.setTouchReportHandler(undefined);
    const audioCapture = this.playbackAudioCapture;
    this.playbackAudioCapture = undefined;
    if (audioCapture) {
      try {
        await audioCapture.stop();
      } catch (error) {
        failures.push(`播放音频采集：${error instanceof Error ? error.message : String(error)}`);
      }
    }
    const audioSender = this.audioRtpSender;
    this.audioRtpSender = undefined;
    if (audioSender) {
      try {
        await audioSender.stop();
      } catch (error) {
        failures.push(`音频 RTP sender：${error instanceof Error ? error.message : String(error)}`);
      }
    }
    try {
      this.videoCapture.stop();
    } catch (error) {
      failures.push(`H.264 屏幕采集：${error instanceof Error ? error.message : String(error)}`);
    }
    try {
      this.videoEncoder.stop();
    } catch (error) {
      failures.push(`H.264 编码器：${error instanceof Error ? error.message : String(error)}`);
    }
    try {
      await this.projectionDisplay.destroy();
    } catch (error) {
      failures.push(error instanceof Error ? error.message : String(error));
    }
    this.activePairing?.setForceKeyFrameHandler(undefined);
    if (displayId >= 0) {
      this.events.onProjectionStopped();
      this.events.onLog(`CarPlay 虚拟屏已停止：id=${displayId}`);
    }
    if (failures.length > 0) {
      throw new Error(failures.join('; '));
    }
  }
}
