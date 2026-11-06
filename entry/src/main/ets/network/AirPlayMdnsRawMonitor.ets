import netSocket from '@ohos.net.socket';
import { formatProtocolEvent, formatRawBytesDiagnostic } from '../session/ProtocolLogger';
import { formatNetworkError, WifiNetworkLease } from './WifiNetworkLease';

const MDNS_GROUP_ADDRESS: string = '224.0.0.251';
const MDNS_PORT: number = 5353;

export function summarizeMdnsDnsPacket(bytes: Uint8Array): string {
  if (bytes.length < 12) {
    return `malformed DNS header; received=${bytes.length}B, required=12B`;
  }
  const identifier = (bytes[0] << 8) | bytes[1];
  const flags = (bytes[2] << 8) | bytes[3];
  const questions = (bytes[4] << 8) | bytes[5];
  const answers = (bytes[6] << 8) | bytes[7];
  const authorities = (bytes[8] << 8) | bytes[9];
  const additionals = (bytes[10] << 8) | bytes[11];
  return `${(flags & 0x8000) !== 0 ? 'response' : 'query'} id=0x${identifier.toString(16).padStart(4, '0')} ` +
    `flags=0x${flags.toString(16).padStart(4, '0')} questions=${questions} answers=${answers} ` +
    `authorities=${authorities} additionals=${additionals}`;
}

export class AirPlayMdnsRawMonitor {
  private readonly wifiNetworkLease: WifiNetworkLease;
  private readonly onLog: (message: string) => void;
  private socket?: netSocket.MulticastSocket;
  private messageHandler?: (info: netSocket.SocketMessageInfo) => void;
  private errorHandler?: (error: Error) => void;
  private membershipAdded: boolean = false;
  private running: boolean = false;

  constructor(wifiNetworkLease: WifiNetworkLease, onLog: (message: string) => void) {
    this.wifiNetworkLease = wifiNetworkLease;
    this.onLog = onLog;
  }

  async start(): Promise<void> {
    if (this.socket) {
      return;
    }
    const socket = netSocket.constructMulticastSocketInstance();
    this.socket = socket;
    this.running = true;
    const messageHandler = (info: netSocket.SocketMessageInfo): void => {
      if (!this.running || this.socket !== socket) {
        return;
      }
      const bytes = new Uint8Array(info.message);
      this.onLog(formatProtocolEvent('mdns.raw.rx',
        'source', info.remoteInfo.address,
        'sourcePort', info.remoteInfo.port,
        'bytes', bytes.length,
        'dnsSummary', summarizeMdnsDnsPacket(bytes)
      ));
      this.onLog(formatRawBytesDiagnostic(
        'RX',
        `mDNS/DNS from ${info.remoteInfo.address}:${info.remoteInfo.port}`,
        bytes
      ));
    };
    const errorHandler = (error: Error): void => {
      if (this.running && this.socket === socket) {
        this.onLog(`WARN: mDNS RAW 监听 socket 错误：${error.message}`);
      }
    };
    this.messageHandler = messageHandler;
    this.errorHandler = errorHandler;
    let stage: string = 'socket-setup';
    try {
      if (typeof socket.setReuseAddress !== 'function') {
        throw new Error('当前系统未提供 MulticastSocket 地址复用能力；为避免抢占系统 mDNS 端口，跳过 RAW 监听');
      }
      socket.setReuseAddress(true);
      socket.on('message', messageHandler);
      socket.on('error', errorHandler);
      stage = 'network-bind';
      await this.wifiNetworkLease.bindSocket(socket, 'mDNS RAW UDP', 1, MDNS_PORT);
      stage = 'multicast-membership';
      await socket.addMembership({
        address: MDNS_GROUP_ADDRESS,
        family: 1,
        port: MDNS_PORT
      });
      this.membershipAdded = true;
      this.onLog(formatProtocolEvent('mdns.raw.capture.started',
        'group', MDNS_GROUP_ADDRESS,
        'port', MDNS_PORT,
        'transport', 'UDP/IPv4',
        'direction', 'RX only',
        'meaning', 'HarmonyOS mDNS discovery does not expose outgoing DNS query bytes'
      ));
    } catch (error) {
      const detail = formatNetworkError(error);
      let cleanupDetail = '';
      try {
        await this.closeSocket(socket);
      } catch (cleanupError) {
        cleanupDetail = cleanupError instanceof Error ? cleanupError.message : String(cleanupError);
      }
      const message = cleanupDetail
        ? `mDNS RAW 监听启动失败：stage=${stage}，${detail}；socket 清理失败：${cleanupDetail}`
        : `mDNS RAW 监听启动失败：stage=${stage}，${detail}`;
      throw new Error(message);
    }
  }

  async stop(): Promise<void> {
    const socket = this.socket;
    if (!socket) {
      return;
    }
    this.running = false;
    await this.closeSocket(socket);
    this.onLog(formatProtocolEvent('mdns.raw.capture.stopped',
      'group', MDNS_GROUP_ADDRESS,
      'port', MDNS_PORT
    ));
  }

  private async closeSocket(socket: netSocket.MulticastSocket): Promise<void> {
    const failures: string[] = [];
    this.running = false;
    if (this.messageHandler) {
      try {
        socket.off('message', this.messageHandler);
      } catch (error) {
        failures.push(`remove message listener: ${error instanceof Error ? error.message : String(error)}`);
      }
    }
    if (this.errorHandler) {
      try {
        socket.off('error', this.errorHandler);
      } catch (error) {
        failures.push(`remove error listener: ${error instanceof Error ? error.message : String(error)}`);
      }
    }
    if (this.membershipAdded) {
      try {
        await socket.dropMembership({
          address: MDNS_GROUP_ADDRESS,
          family: 1,
          port: MDNS_PORT
        });
      } catch (error) {
        failures.push(`dropMembership: ${error instanceof Error ? error.message : String(error)}`);
      }
    }
    try {
      await socket.close();
    } catch (error) {
      failures.push(`close: ${error instanceof Error ? error.message : String(error)}`);
    }
    if (this.socket === socket) {
      this.socket = undefined;
      this.messageHandler = undefined;
      this.errorHandler = undefined;
      this.membershipAdded = false;
    }
    if (failures.length > 0) {
      throw new Error(failures.join('; '));
    }
  }
}
