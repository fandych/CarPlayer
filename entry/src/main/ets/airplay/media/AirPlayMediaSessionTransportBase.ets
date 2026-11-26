import netSocket from '@ohos.net.socket';
import { AirPlayEventChannel } from '../AirPlayEventChannel';
import { AirPlayRtspClient } from '../AirPlayRtspClient';
import { PlistNode } from '../BinaryPlist';
import { AirPlayVideoStreamSender } from '../AirPlayVideoStream';
import { TouchHidDevice } from '../CarPlayTouchReport';
import { toArrayBuffer } from '../../protocol/Iap2Codec';
import { getSocketAddressFamily, WifiNetworkLease } from '../../network/WifiNetworkLease';
import { formatProtocolEvent, formatRawBytesDiagnostic } from '../../session/ProtocolLogger';
import { Iap2SenderSession } from '../../session/Iap2SenderSession';
import type { AirPlayModes } from '../AirPlayMediaSession';
import { describeNetworkError } from './AirPlayMediaHelpers';

export abstract class AirPlayMediaSessionTransportBase {
  protected readonly client: AirPlayRtspClient;
  protected readonly receiverHost: string;
  protected readonly log: (message: string) => void;
  protected readonly onTransportDisconnected: (message: string) => void;
  protected readonly wifiNetworkLease: WifiNetworkLease;
  protected videoDataSocket?: netSocket.TCPSocket;
  protected videoSocketErrorHandler?: (error: Error) => void;
  protected videoSocketCloseHandler?: () => void;
  protected videoStreamSender?: AirPlayVideoStreamSender;
  protected videoWriteQueue: Promise<void> = Promise.resolve();
  protected videoWriteFailed: boolean = false;
  protected timingRequestsReceived: number = 0;
  protected lowPowerKeepAlivesSent: number = 0;
  protected forceKeyFrameHandler?: () => void;
  protected touchReportHandler?: (report: Uint8Array) => void;
  protected nightModeHandler?: (night: boolean) => void;
  protected nightMode: boolean = false;
  protected modes: AirPlayModes = {
    screenEntity: 1,
    screenPermanentEntity: 1,
    audioEntity: 1,
    audioPermanentEntity: 1,
    speechEntity: 0,
    speechMode: -1,
    phoneCallEntity: 0,
    turnByTurnEntity: 0
  };
  protected touchHid?: TouchHidDevice;
  protected videoWidth: number = 0;
  protected videoHeight: number = 0;
  protected videoKeepAliveTimer: number = -1;
  protected videoKeepAlivePending: boolean = false;
  protected timingSocket?: netSocket.UDPSocket;
  protected timingHandler?: (info: netSocket.SocketMessageInfo) => void;
  protected keepAliveSocket?: netSocket.UDPSocket;
  protected eventChannel?: AirPlayEventChannel;
  protected virtualIap2Session?: Iap2SenderSession;
  protected keepAliveTimer: number = -1;
  protected feedbackTimer: number = -1;
  protected feedbackPending: boolean = false;
  protected feedbackEnabled: boolean = true;
  protected running: boolean = false;
  protected recorded: boolean = false;

  protected abstract createTimingResponse(request: Uint8Array, nowMillis: number): Uint8Array | undefined;
  protected abstract createVideoKeepAliveFrame(nowMillis: number): Uint8Array;
  protected abstract createAudioSetupPayload(connectionId: bigint, formatBit: bigint, latencyMs: number): Uint8Array;
  protected abstract applyModeChanges(modes: AirPlayModes, params: PlistNode | undefined): AirPlayModes;
  protected abstract createModesDictionary(modes: AirPlayModes): PlistNode;
  protected abstract createModesChangedPayload(modes: AirPlayModes): Uint8Array;
  protected abstract createLowPowerKeepAliveBeacon(): Uint8Array;
  constructor(
    client: AirPlayRtspClient,
    receiverHost: string,
    log: (message: string) => void,
    onTransportDisconnected: (message: string) => void,
    wifiNetworkLease: WifiNetworkLease
  ) {
    this.client = client;
    this.receiverHost = wifiNetworkLease.scopeLinkLocalAddress(receiverHost);
    this.log = log;
    this.onTransportDisconnected = onTransportDisconnected;
    this.wifiNetworkLease = wifiNetworkLease;
  }
  protected ensureRunning(): void {
    if (!this.running) {
      throw new Error('AirPlay media session startup was cancelled');
    }
  }
  protected async startTimingServer(): Promise<number> {
    const socket = netSocket.constructUDPSocketInstance();
    const handler = (info: netSocket.SocketMessageInfo): void => {
      const request = new Uint8Array(info.message);
      this.log(formatRawBytesDiagnostic('RX', 'AirPlay timing UDP', request, 64));
      const response = this.createTimingResponse(request, Date.now());
      if (!response) {
        this.log(formatProtocolEvent('airplay.timing.request.invalid',
          'bytes', request.length,
          'source', `${info.remoteInfo.address}:${info.remoteInfo.port}`,
          'meaning', '长度或类型不符合 AirPlay timing 请求格式，未发送响应'
        ));
        return;
      }
      const requestNumber = ++this.timingRequestsReceived;
      this.log(formatProtocolEvent('airplay.timing.request',
        'packet', requestNumber,
        'bytes', request.length,
        'source', `${info.remoteInfo.address}:${info.remoteInfo.port}`,
        'meaning', '请求本机时钟时间；已构造对应 NTP 时间戳响应'
      ));

      const options: netSocket.UDPSendOptions = {
        data: toArrayBuffer(response),
        address: {
          address: this.wifiNetworkLease.scopeLinkLocalAddress(info.remoteInfo.address),
          family: getSocketAddressFamily(info.remoteInfo.address),
          port: info.remoteInfo.port
        }
      };
      void socket.send(options).then((): void => {
        this.log(formatRawBytesDiagnostic('TX', 'AirPlay timing UDP', response, 64));
        this.log(formatProtocolEvent('airplay.timing.response',
          'requestPacket', requestNumber,
          'bytes', response.length,
          'destination', `${info.remoteInfo.address}:${info.remoteInfo.port}`,
          'meaning', '发送时钟响应，供对端校准 RTP 播放时间'
        ));
      }).catch((error: Error): void => {
        this.log(formatProtocolEvent('airplay.timing.response.failure',
          'requestPacket', requestNumber,
          'error', describeNetworkError(error),
          'meaning', '时钟响应未能通过 UDP socket 发送'
        ));
      });
    };
    try {
      socket.on('message', handler);
      const boundToCarWifi = await this.wifiNetworkLease.bindSocket(
        socket, 'AirPlay timing UDP', getSocketAddressFamily(this.receiverHost));
      this.log(boundToCarWifi ? 'AirPlay timing UDP socket 已绑定指定车机 Wi-Fi 网络' :
        'AirPlay timing UDP socket 使用系统默认网络路由');
      const localAddress = await socket.getLocalAddress();
      const localPort = localAddress.port;
      if (typeof localPort !== 'number' || localPort < 1) {
        throw new Error('System did not allocate a timing UDP port');
      }
      this.timingSocket = socket;
      this.timingHandler = handler;
      return localPort;
    } catch (error) {
      try {
        socket.off('message', handler);
      } catch (cleanupError) {
        this.log(`AirPlay timing listener cleanup failed: ${cleanupError instanceof Error ?
          cleanupError.message : String(cleanupError)}`);
      }
      try {
        await socket.close();
      } catch (cleanupError) {
        this.log(`AirPlay timing socket cleanup failed: ${cleanupError instanceof Error ?
          cleanupError.message : String(cleanupError)}`);
      }
      throw new Error(`Unable to start AirPlay timing service: ${error instanceof Error ? error.message : String(error)}`);
    }
  }

  protected async openVideoDataPort(port: number): Promise<void> {
    const socketHost = this.wifiNetworkLease.scopeLinkLocalAddress(this.receiverHost);
    const socket = netSocket.constructTCPSocketInstance();
    const errorHandler = (error: Error): void => {
      this.reportVideoSocketFailure(socket, `socket error: ${describeNetworkError(error)}`);
    };
    const closeHandler = (): void => {
      this.reportVideoSocketFailure(socket, 'socket closed by peer');
    };
    this.videoDataSocket = socket;
    this.videoSocketErrorHandler = errorHandler;
    this.videoSocketCloseHandler = closeHandler;
    socket.on('error', errorHandler);
    socket.on('close', closeHandler);
    try {
      if (await this.wifiNetworkLease.bindSocket(
        socket, 'AirPlay video TCP', getSocketAddressFamily(socketHost))) {
        this.log('AirPlay video TCP socket 已绑定指定车机 Wi-Fi 网络');
      }
      await socket.connect({
        address: { address: socketHost, family: getSocketAddressFamily(socketHost), port },
        timeout: 5000
      });
      this.log(`AirPlay screen data TCP connected: ${socketHost}:${port}`);
    } catch (error) {
      if (this.videoDataSocket === socket) {
        this.videoDataSocket = undefined;
      }
      this.videoSocketErrorHandler = undefined;
      this.videoSocketCloseHandler = undefined;
      try {
        socket.off('error', errorHandler);
        socket.off('close', closeHandler);
      } catch (_cleanupError) {
      }
      try {
        await socket.close();
      } catch (cleanupError) {
        this.log(`AirPlay screen TCP cleanup failed: ${cleanupError instanceof Error ?
          cleanupError.message : String(cleanupError)}`);
      }
      throw new Error(`Unable to connect screen data port: ${error instanceof Error ? error.message : String(error)}`);
    }
  }

}
