import { settleSocketWithin } from '../../network/SocketDeadline';
import { BinaryPlist, PlistNode } from '../BinaryPlist';
import { AirPlayMediaSessionPayloads } from './AirPlayMediaSessionPayloads';
import { AirPlayMediaSessionStart } from './AirPlayMediaSessionStart';

export abstract class AirPlayMediaSessionLifecycle extends AirPlayMediaSessionStart {
  async requestReceiverHome(): Promise<void> {
    this.ensureRunning();
    const body = BinaryPlist.encode(PlistNode.dictionary(new Map<string, PlistNode>([
      ['type', PlistNode.string('requestUI')],
      ['params', PlistNode.dictionary(new Map<string, PlistNode>([
        ['url', PlistNode.string('oem:')]
      ]))]
    ])));
    const response = await this.client.request('POST', '/command', body,
      { contentType: 'application/x-apple-binary-plist' });
    if (response.statusCode !== 200) {
      throw new Error(`车机拒绝界面切换：${response.statusCode}`);
    }
    this.log('Receiver acknowledged OEM UI request; media streams remain active');
  }

  async sendVirtualIap2Message(bytes: Uint8Array): Promise<void> {
    this.ensureRunning();
    if (!this.virtualIap2Session) {
      throw new Error('MIB3 virtual iAP2 link is not active');
    }
    await this.request(
      'POST',
      '/command',
      AirPlayMediaSessionPayloads.buildIapSendMessagePayload(bytes),
      'MIB3 virtual iAP2 message'
    );
  }

  async stop(abort: boolean = false): Promise<void> {
    this.running = false;
    this.virtualIap2Session?.cancel();
    this.virtualIap2Session = undefined;
    if (abort) {
      this.recorded = false;
    }
    this.log(
      `AirPlay heartbeat summary: timingRequests=${this.timingRequestsReceived}, ` +
        `lowPowerKeepAlivesSent=${this.lowPowerKeepAlivesSent}`
    );
    if (this.keepAliveTimer >= 0) {
      clearInterval(this.keepAliveTimer);
      this.keepAliveTimer = -1;
    }
    if (this.feedbackTimer >= 0) {
      clearTimeout(this.feedbackTimer);
      this.feedbackTimer = -1;
    }
    if (this.videoKeepAliveTimer >= 0) {
      clearInterval(this.videoKeepAliveTimer);
      this.videoKeepAliveTimer = -1;
    }
    const failures: string[] = [];
    const videoSocket = this.videoDataSocket;
    this.videoDataSocket = undefined;
    this.videoWriteFailed = true;
    if (videoSocket) {
      const errorHandler = this.videoSocketErrorHandler;
      const closeHandler = this.videoSocketCloseHandler;
      this.videoSocketErrorHandler = undefined;
      this.videoSocketCloseHandler = undefined;
      if (errorHandler) {
        try { videoSocket.off('error', errorHandler); } catch (_error) {}
      }
      if (closeHandler) {
        try { videoSocket.off('close', closeHandler); } catch (_error) {}
      }
      try {
        await settleSocketWithin(videoSocket.close(), 1500, 'video socket close timed out');
      } catch (error) {
        failures.push(`video data socket: ${error instanceof Error ? error.message : String(error)}`);
      }
    }
    const videoStreamSender = this.videoStreamSender;
    this.videoStreamSender = undefined;
    if (videoStreamSender) {
      try {
        await settleSocketWithin(videoStreamSender.flush(), 1500, 'encoder queue shutdown timed out');
      } catch (error) {
        failures.push(`screen-stream encoder queue: ${error instanceof Error ? error.message : String(error)}`);
      }
      try {
        await settleSocketWithin(videoStreamSender.finish(), 1500, 'screen-stream cipher shutdown timed out');
      } catch (error) {
        failures.push(`screen-stream cipher: ${error instanceof Error ? error.message : String(error)}`);
      }
    }
    try {
      await settleSocketWithin(this.videoWriteQueue, 1500, 'video write shutdown timed out');
    } catch (error) {
      failures.push(`screen-stream send queue: ${error instanceof Error ? error.message : String(error)}`);
    }
    const eventChannel = this.eventChannel;
    this.eventChannel = undefined;
    if (eventChannel) {
      try {
        await settleSocketWithin(eventChannel.close(), 1500, 'event channel shutdown timed out');
      } catch (error) {
        failures.push(`event channel: ${error instanceof Error ? error.message : String(error)}`);
      }
    }
    if (this.recorded) {
      this.recorded = false;
      if (this.client.isConnected) {
        try {
          await this.request(
            'TEARDOWN',
            '/',
            BinaryPlist.encode(PlistNode.dictionary(new Map<string, PlistNode>())),
            'TEARDOWN'
          );
        } catch (error) {
          const message = error instanceof Error ? error.message : String(error);
          this.log(`WARN: RTSP TEARDOWN failed during shutdown; continuing local cleanup: ${message}`);
        }
      }
    }
    if (this.timingSocket) {
      const socket = this.timingSocket;
      this.timingSocket = undefined;
      if (this.timingHandler) {
        try {
          socket.off('message', this.timingHandler);
        } catch (error) {
          failures.push(`timing listener: ${error instanceof Error ? error.message : String(error)}`);
        }
      }
      this.timingHandler = undefined;
      try {
        await settleSocketWithin(socket.close(), 1500, 'timing socket close timed out');
      } catch (error) {
        failures.push(`timing socket: ${error instanceof Error ? error.message : String(error)}`);
      }
    }
    if (this.keepAliveSocket) {
      const socket = this.keepAliveSocket;
      this.keepAliveSocket = undefined;
      try {
        await settleSocketWithin(socket.close(), 1500, 'keep-alive socket close timed out');
      } catch (error) {
        failures.push(`keep-alive socket: ${error instanceof Error ? error.message : String(error)}`);
      }
    }
    if (failures.length > 0) {
      throw new Error(failures.join('; '));
    }
  }

}
