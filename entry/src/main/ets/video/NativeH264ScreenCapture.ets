import nativeProjection from 'libprojection.so';
import { EncodedH264Event } from '../airplay/AirPlayVideoStream';

interface NativeScreenCaptureModule {
  startScreenCapture(
    displayId: number,
    width: number,
    height: number,
    frameRate: number,
    bitrate: number,
    encoderHandle: number,
    onEvent: (event: EncodedH264Event) => void
  ): number;
  stopScreenCapture(handle: number): void;
}

const nativeApi = nativeProjection as NativeScreenCaptureModule;

export interface H264ScreenCaptureConfig {
  displayId: number;
  width: number;
  height: number;
  frameRate: number;
  bitrate: number;
  encoderHandle: number;
}

export class NativeH264ScreenCapture {
  private captureHandle?: number;

  start(config: H264ScreenCaptureConfig, onEvent: (event: EncodedH264Event) => void): void {
    if (this.captureHandle !== undefined) {
      throw new Error('H.264 screen capture is already running');
    }
    this.captureHandle = nativeApi.startScreenCapture(
      config.displayId,
      config.width,
      config.height,
      config.frameRate,
      config.bitrate,
      config.encoderHandle,
      onEvent
    );
  }

  stop(): void {
    const handle = this.captureHandle;
    this.captureHandle = undefined;
    if (handle !== undefined) {
      nativeApi.stopScreenCapture(handle);
    }
  }
}