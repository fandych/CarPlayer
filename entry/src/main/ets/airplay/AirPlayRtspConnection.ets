import netSocket from '@ohos.net.socket';
import { settleSocketWithin } from '../network/SocketDeadline';
import { toArrayBuffer } from '../protocol/Iap2Codec';
import {
  formatNetworkError,
  getSocketAddressFamily,
  WifiNetworkLease
} from '../network/WifiNetworkLease';

export class AirPlayRtspConnection {
  private socket?: netSocket.TCPSocket;
  private messageHandler?: (info: netSocket.SocketMessageInfo) => void;
  private errorHandler?: (error: Error) => void;
  private closeHandler?: () => void;
  private disconnectNotified: boolean = false;
  private readonly onMessage: (data: Uint8Array) => void;
  private readonly onError: (error: Error) => void;
  private readonly onDisconnected: (message: string) => void;
  private readonly onBound: () => void;
  private readonly onConnectFailure: () => void;
  private readonly wifiNetworkLease: WifiNetworkLease;

  constructor(
    onMessage: (data: Uint8Array) => void,
    onError: (error: Error) => void,
    onDisconnected: (message: string) => void,
    onBound: () => void,
    onConnectFailure: () => void,
    wifiNetworkLease: WifiNetworkLease
  ) {
    this.onMessage = onMessage;
    this.onError = onError;
    this.onDisconnected = onDisconnected;
    this.onBound = onBound;
    this.onConnectFailure = onConnectFailure;
    this.wifiNetworkLease = wifiNetworkLease;
  }

  get isConnected(): boolean {
    return this.socket !== undefined && !this.disconnectNotified;
  }

  get hasSocket(): boolean {
    return this.socket !== undefined;
  }

  async connect(host: string, port: number): Promise<void> {
    if (this.socket) {
      throw new Error('AirPlay RTSP client is already connected');
    }
    if (!host || port < 1 || port > 65535) {
      throw new Error('Invalid AirPlay RTSP endpoint');
    }
    const socket = netSocket.constructTCPSocketInstance();
    this.socket = socket;
    this.disconnectNotified = false;
    this.messageHandler = (info: netSocket.SocketMessageInfo): void => {
      this.onMessage(new Uint8Array(info.message));
    };
    this.errorHandler = (error: Error): void => {
      this.onError(error);
      this.notifyDisconnected(socket, `RTSP socket error: ${formatNetworkError(error)}`);
    };
    this.closeHandler = (): void => {
      this.notifyDisconnected(socket, 'RTSP socket closed by peer');
    };
    try {
      socket.on('message', this.messageHandler);
      socket.on('error', this.errorHandler);
      socket.on('close', this.closeHandler);
      const socketHost = this.wifiNetworkLease.scopeLinkLocalAddress(host);
      const options: netSocket.TCPConnectOptions = {
        address: { address: socketHost, family: getSocketAddressFamily(socketHost), port },
        timeout: 5000
      };
      if (await this.wifiNetworkLease.bindSocket(
        socket, 'AirPlay RTSP TCP', getSocketAddressFamily(socketHost))) {
        this.onBound();
      }
      await socket.connect(options);
    } catch (error) {
      const message = formatNetworkError(error);
      try {
        this.onConnectFailure();
        await this.close();
      } catch (cleanupError) {
        const cleanupMessage = cleanupError instanceof Error ? cleanupError.message : String(cleanupError);
        throw new Error(`AirPlay RTSP connect failed: ${message}; cleanup failed: ${cleanupMessage}`);
      }
      throw new Error(`AirPlay RTSP connect failed: ${message}`);
    }
  }

  async send(data: Uint8Array): Promise<void> {
    const socket = this.socket;
    if (!socket) {
      throw new Error('AirPlay RTSP client is not connected');
    }
    const options: netSocket.TCPSendOptions = { data: toArrayBuffer(data) };
    await socket.send(options);
  }

  async close(): Promise<void> {
    const socket = this.socket;
    this.socket = undefined;
    if (!socket) {
      return;
    }
    const failures: string[] = [];
    if (this.messageHandler) {
      try {
        socket.off('message', this.messageHandler);
      } catch (error) {
        failures.push(`message listener: ${formatNetworkError(error)}`);
      }
    }
    if (this.errorHandler) {
      try {
        socket.off('error', this.errorHandler);
      } catch (error) {
        failures.push(`error listener: ${formatNetworkError(error)}`);
      }
    }
    if (this.closeHandler) {
      try {
        socket.off('close', this.closeHandler);
      } catch (error) {
        failures.push(`close listener: ${formatNetworkError(error)}`);
      }
    }
    this.messageHandler = undefined;
    this.errorHandler = undefined;
    this.closeHandler = undefined;
    try {
      await settleSocketWithin(socket.close(), 1500, 'RTSP socket close timed out');
    } catch (error) {
      failures.push(`socket close: ${formatNetworkError(error)}`);
    }
    if (failures.length > 0) {
      throw new Error(`AirPlay RTSP cleanup failed (${failures.join('; ')})`);
    }
  }

  private notifyDisconnected(socket: netSocket.TCPSocket, message: string): void {
    if (this.socket !== socket || this.disconnectNotified) {
      return;
    }
    this.disconnectNotified = true;
    this.onDisconnected(message);
  }
}
