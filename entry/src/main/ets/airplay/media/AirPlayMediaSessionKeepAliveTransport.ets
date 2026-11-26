import netSocket from '@ohos.net.socket';
import { AirPlayRtspResponse } from '../AirPlayRtspClient';
import { toArrayBuffer } from '../../protocol/Iap2Codec';
import { getSocketAddressFamily } from '../../network/WifiNetworkLease';
import { formatProtocolEvent, formatRawBytesDiagnostic } from '../../session/ProtocolLogger';
import { requireSuccess } from './AirPlayMediaHelpers';
import { AirPlayMediaSessionEventTransport } from './AirPlayMediaSessionEventTransport';

export abstract class AirPlayMediaSessionKeepAliveTransport extends AirPlayMediaSessionEventTransport {
  protected async startKeepAlive(port: number): Promise<void> {
    if (port === 0) {
      this.log('Receiver did not advertise a keep-alive UDP port');
      return;
    }
    const socket = netSocket.constructUDPSocketInstance();
    try {
      const boundToCarWifi = await this.wifiNetworkLease.bindSocket(
        socket, 'AirPlay keep-alive UDP', getSocketAddressFamily(this.receiverHost));
      this.log(boundToCarWifi ? 'AirPlay keep-alive UDP socket 已绑定指定车机 Wi-Fi 网络' :
        'AirPlay keep-alive UDP socket 使用系统默认网络路由');
      this.keepAliveSocket = socket;
      this.keepAliveTimer = setInterval((): void => {
        void this.sendKeepAlive(port).catch((error: Error): void => {
          this.log(`AirPlay UDP keep-alive failed: ${error.message}`);
        });
      }, 5000);
      await this.sendKeepAlive(port);
    } catch (error) {
      try {
        await socket.close();
      } catch (cleanupError) {
        this.log(`AirPlay keep-alive socket cleanup failed: ${cleanupError instanceof Error ?
          cleanupError.message : String(cleanupError)}`);
      }
      this.keepAliveSocket = undefined;
      throw new Error(`Unable to start AirPlay keep-alive: ${error instanceof Error ? error.message : String(error)}`);
    }
  }

  protected async sendKeepAlive(port: number): Promise<void> {
    const socket = this.keepAliveSocket;
    if (!socket || !this.running) {
      return;
    }
    const socketHost = this.wifiNetworkLease.scopeLinkLocalAddress(this.receiverHost);
    const beacon = this.createLowPowerKeepAliveBeacon();
    const options: netSocket.UDPSendOptions = {
      data: toArrayBuffer(beacon),
      address: {
        address: socketHost,
        family: getSocketAddressFamily(socketHost),
        port
      }
    };
    await socket.send(options);
    const packetNumber = ++this.lowPowerKeepAlivesSent;
    this.log(formatRawBytesDiagnostic('TX', 'AirPlay low-power keep-alive UDP', beacon, 64));
    this.log(formatProtocolEvent('airplay.keep_alive.tx',
      'packet', packetNumber,
      'destination', `${this.receiverHost}:${port}`,
      'bytes', beacon.length,
      'meaning', '向接收端发送低功耗会话保活信标，避免控制会话因空闲被回收'
    ));
  }

  protected startFeedbackLoop(): void {
    const run = async (): Promise<void> => {
      this.feedbackTimer = -1;
      if (!this.running || this.feedbackPending) {
        return;
      }
      this.feedbackPending = true;
      try {
        const response = await this.client.request(
          'POST',
          '/feedback',
          new Uint8Array(0),
          { contentType: 'application/x-apple-binary-plist' }
        );
        if (response.statusCode !== 200) {
          this.log(`AirPlay feedback returned ${response.statusLine}`);
          this.feedbackEnabled = false;
        }
      } catch (error) {
        this.log(`AirPlay feedback failed: ${error instanceof Error ? error.message : String(error)}`);
        this.feedbackEnabled = false;
      } finally {
        this.feedbackPending = false;
        if (this.running && this.feedbackEnabled) {
          this.feedbackTimer = setTimeout((): void => {
            void run();
          }, 1000);
        }
      }
    };
    this.feedbackTimer = setTimeout((): void => {
      void run();
    }, 1000);
  }

  protected async request(method: string, path: string, body: Uint8Array, label: string):
    Promise<AirPlayRtspResponse> {
    const response = await this.client.request(method, path, body, {
      contentType: 'application/x-apple-binary-plist'
    });
    requireSuccess(response, label);
    return response;
  }
}
