import netSocket from '@ohos.net.socket';
import { MediaPacketCipher } from '../crypto/MediaPacketCipher';
import { settleSocketWithin } from '../network/SocketDeadline';
import { concatBytes, toArrayBuffer } from '../protocol/Iap2Codec';
import { getSocketAddressFamily, WifiNetworkLease } from '../network/WifiNetworkLease';
import { formatProtocolEvent } from '../session/ProtocolLogger';
import { swapPcmS16 } from './AudioPcm';

export interface AudioRtpSession {
  host: string;
  dataPort: number;
  controlPort: number;
  streamKey: Uint8Array;
  sampleRate: number;
}

const CHANNELS: number = 2;
export const SAMPLES_PER_PACKET: number = 352;
const PCM_BYTES_PER_PACKET: number = SAMPLES_PER_PACKET * CHANNELS * 2;
const MAX_QUEUED_PACKETS: number = 32;
const MAX_AUDIO_QUEUE_AGE_MS: number = 100;

export function advanceAudioRtpTimestamp(timestamp: number, packets: number): number {
  return (timestamp + packets * SAMPLES_PER_PACKET) >>> 0;
}

export function buildAudioRtpHeader(sequence: number, timestamp: number, marker: boolean): Uint8Array {
  const header = new Uint8Array(12);
  header[0] = 0x80;
  header[1] = (marker ? 0x80 : 0) | 100;
  writeBe16(header, 2, sequence);
  writeBe32(header, 4, timestamp);
  writeBe32(header, 8, 0);
  return header;
}

export function buildAudioRtpSyncPacket(
  sequence: number,
  rtpTimestamp: number,
  nowMillis: number,
  first: boolean
): Uint8Array {
  if (!Number.isInteger(sequence) || sequence < 0 || sequence > 0xffff ||
    !Number.isInteger(rtpTimestamp) || rtpTimestamp < 0 || rtpTimestamp > 0xffffffff ||
    !Number.isFinite(nowMillis) || nowMillis < 0) {
    throw new Error('Invalid AirPlay audio sync time');
  }
  const packet = new Uint8Array(20);
  packet[0] = first ? 0x90 : 0x80;
  packet[1] = 0xd4;
  writeBe16(packet, 2, sequence);
  writeBe32(packet, 4, rtpTimestamp);
  const ntpTimestamp = createNtpTimestamp(nowMillis);
  packet.set(ntpTimestamp, 8);
  writeBe32(packet, 16, advanceAudioRtpTimestamp(rtpTimestamp, 1));
  return packet;
}

export class AudioRtpSender {
  private socket?: netSocket.UDPSocket;
  private readonly log: (message: string) => void;
  private readonly onError: (message: string) => void;
  private readonly wifiNetworkLease?: WifiNetworkLease;
  private session?: AudioRtpSession;
  private cipher?: MediaPacketCipher;
  private pendingPcm: Uint8Array = new Uint8Array(0);
  private sendQueue: Promise<void> = Promise.resolve();
  private sequence: number = 0;
  private timestamp: number = 0;
  private nonceCounter: number = 0;
  private syncSequence: number = 0;
  private firstPacket: boolean = true;
  private firstSync: boolean = true;
  private packetsSent: number = 0;
  private queuedPackets: number = 0;
  private queuePacketLimit: number = MAX_QUEUED_PACKETS;
  private droppedPackets: number = 0;
  private pendingSkippedPackets: number = 0;
  private running: boolean = false;
  private failed: boolean = false;
  private hasStarted: boolean = false;
  private syncTimer: number = -1;
  private syncPending: boolean = false;

  constructor(
    log: (message: string) => void,
    onError: (message: string) => void,
    wifiNetworkLease?: WifiNetworkLease
  ) {
    this.log = log;
    this.onError = onError;
    this.wifiNetworkLease = wifiNetworkLease;
  }

  async start(session: AudioRtpSession): Promise<void> {
    if (this.running || this.hasStarted) {
      throw new Error('Audio RTP sender cannot be reused; create a sender for the new session');
    }
    if (!session.host || session.dataPort < 1 || session.dataPort > 65535 ||
      session.controlPort < 0 || session.controlPort > 65535 || session.streamKey.length !== 32 ||
      (session.sampleRate !== 44100 && session.sampleRate !== 48000)) {
      throw new Error('Invalid AirPlay audio stream configuration');
    }
    this.hasStarted = true;
    const socket = netSocket.constructUDPSocketInstance();
    try {
      if (this.wifiNetworkLease && await this.wifiNetworkLease.bindSocket(
        socket, 'AirPlay audio RTP UDP', getSocketAddressFamily(session.host))) {
        this.log('AirPlay audio UDP socket 已绑定指定车机 Wi-Fi 网络');
      }
    } catch (error) {
      try {
        await socket.close();
      } catch (cleanupError) {
        this.onError(`Audio RTP socket cleanup failed: ${cleanupError instanceof Error ?
          cleanupError.message : String(cleanupError)}`);
      }
      throw new Error(`Audio RTP socket bind failed: ${error instanceof Error ? error.message : String(error)}`);
    }
    this.socket = socket;
    this.session = session;
    this.cipher = new MediaPacketCipher(session.streamKey, true, this.log);
    this.queuePacketLimit = MAX_QUEUED_PACKETS;
    this.running = true;
    this.syncTimer = setInterval((): void => {
      void this.sendSync().catch((error: Error): void => this.onError(`AirPlay audio sync failed: ${error.message}`));
    }, 1000);
    this.log(`Audio RTP sender ready for ${session.host}:${session.dataPort}`);
  }

  pushPcm(data: Uint8Array): void {
    if (!this.running) {
      if (this.failed) {
        return;
      }
      throw new Error('Audio RTP sender is not running');
    }
    if (data.length + this.pendingPcm.length > 1024 * 1024) {
      this.pendingPcm = new Uint8Array(0);
      throw new Error('Audio input exceeded the 1 MiB safety limit');
    }
    const available = concatBytes(this.pendingPcm, data);
    let offset = 0;
    while (available.length - offset >= PCM_BYTES_PER_PACKET) {
      const pcm = available.subarray(offset, offset + PCM_BYTES_PER_PACKET);
      offset += PCM_BYTES_PER_PACKET;
      if (this.queuedPackets >= this.queuePacketLimit) {
        this.droppedPackets++;
        this.pendingSkippedPackets++;
        if (this.droppedPackets === 1 || this.droppedPackets % 200 === 0) {
          this.log(`WARN: AirPlay audio send queue full; dropped ${this.droppedPackets} packets`);
        }
        continue;
      }
      const bigEndianPcm = swapPcmS16(pcm);
      const skippedPackets = this.pendingSkippedPackets;
      const enqueuedAt = Date.now();
      this.pendingSkippedPackets = 0;
      this.queuedPackets++;
      this.sendQueue = this.sendQueue
        .then((): Promise<void> => {
          this.sequence = (this.sequence + skippedPackets) & 0xffff;
          this.timestamp = advanceAudioRtpTimestamp(this.timestamp, skippedPackets);
          if (Date.now() - enqueuedAt > MAX_AUDIO_QUEUE_AGE_MS) {
            this.sequence = (this.sequence + 1) & 0xffff;
            this.timestamp = advanceAudioRtpTimestamp(this.timestamp, 1);
            this.droppedPackets++;
            return Promise.resolve();
          }
          return this.sendPacket(bigEndianPcm);
        })
        .catch((error: Error): void => {
          if (this.failed) {
            return;
          }
          this.failed = true;
          this.running = false;
          this.pendingPcm = new Uint8Array(0);
          if (this.syncTimer >= 0) {
            clearInterval(this.syncTimer);
            this.syncTimer = -1;
          }
          this.onError(`AirPlay audio packet failed: ${error.message}`);
        })
        .finally((): void => {
          this.queuedPackets--;
        });
    }
    this.pendingPcm = available.slice(offset);
  }

  async stop(): Promise<void> {
    this.running = false;
    if (this.syncTimer >= 0) {
      clearInterval(this.syncTimer);
      this.syncTimer = -1;
    }
    const socket = this.socket;
    this.socket = undefined;
    this.session = undefined;
    this.cipher = undefined;
    this.pendingPcm = new Uint8Array(0);
    try {
      if (socket) {
        await settleSocketWithin(socket.close(), 1500, 'audio socket close timed out');
      }
    } finally {
      await settleSocketWithin(this.sendQueue, 1500, 'audio queue shutdown timed out');
    }
    this.log('Audio RTP sender stopped');
  }

  private async sendPacket(pcm: Uint8Array): Promise<void> {
    const socket = this.socket;
    const session = this.session;
    const cipher = this.cipher;
    if (!socket || !session || !cipher || !this.running) {
      return;
    }
    const packetSequence = this.sequence;
    const packetTimestamp = this.timestamp;
    const packetNonceCounter = this.nonceCounter;
    const marker = this.firstPacket;
    const header = buildAudioRtpHeader(packetSequence, packetTimestamp, marker);
    const nonce = nonce64(packetNonceCounter);
    this.sequence = (this.sequence + 1) & 0xffff;
    this.timestamp = advanceAudioRtpTimestamp(this.timestamp, 1);
    this.nonceCounter++;
    const aad = header.slice(4, 12);
    const pcmLength = pcm.length;
    const encrypted = await cipher.seal(nonce, pcm, aad);
    if (!this.running || this.socket !== socket || this.session !== session) {
      return;
    }
    const suffix = nonce.slice(4, 12);
    const datagram = concatBytes(header, encrypted, suffix);
    const options: netSocket.UDPSendOptions = {
      data: toArrayBuffer(datagram),
      address: { address: session.host, port: session.dataPort }
    };
    await socket.send(options);
    this.packetsSent++;
    this.log(formatProtocolEvent('airplay.audio.rtp.tx',
      'packet', this.packetsSent,
      'sequence', packetSequence,
      'timestamp', packetTimestamp,
      'nonceCounter', packetNonceCounter,
      'marker', marker,
      'payloadType', 100,
      'pcmBytes', pcmLength,
      'encryptedBytes', encrypted.length,
      'wireBytes', datagram.length,
      'destination', `${session.host}:${session.dataPort}`
    ));
    this.log(formatProtocolEvent('protocol.interpretation',
      'transport', 'AirPlay audio RTP/UDP',
      'meaning', `已发送第 ${this.packetsSent} 个加密 PCM 包；序号/时间戳用于接收端排序与播放同步，载荷未写入日志`
    ));
    this.firstPacket = false;
  }

  private async sendSync(): Promise<void> {
    const socket = this.socket;
    const session = this.session;
    if (!socket || !session || !this.running || session.controlPort < 1 || this.syncPending) {
      return;
    }
    const sequence = this.syncSequence;
    const timestamp = this.timestamp;
    const first = this.firstSync;
    const packet = buildAudioRtpSyncPacket(sequence, timestamp, Date.now(), first);
    this.syncSequence = (this.syncSequence + 1) & 0xffff;
    const options: netSocket.UDPSendOptions = {
      data: toArrayBuffer(packet),
      address: { address: session.host, port: session.controlPort }
    };
    this.syncPending = true;
    try {
      await socket.send(options);
      this.log(formatProtocolEvent('airplay.audio.sync.tx',
        'sequence', sequence,
        'rtpTimestamp', timestamp,
        'wireBytes', packet.length,
        'destination', `${session.host}:${session.controlPort}`
      ));
      this.log(formatProtocolEvent('protocol.interpretation',
        'transport', 'AirPlay audio sync/UDP',
        'meaning', '发送 RTP/NTP 时钟同步包，帮助接收端将音频时间戳映射到播放时钟'
      ));
      this.firstSync = false;
    } finally {
      this.syncPending = false;
    }
  }
}

function nonce64(counter: number): Uint8Array {
  const nonce = new Uint8Array(12);
  let remaining = counter;
  for (let index = 4; index < 12; index++) {
    nonce[index] = remaining & 0xff;
    remaining = Math.floor(remaining / 256);
  }
  return nonce;
}

function createNtpTimestamp(nowMillis: number): Uint8Array {
  const seconds = Math.floor(nowMillis / 1000) + 2208988800;
  const fraction = Math.floor(((nowMillis % 1000) * 0x100000000) / 1000);
  const result = new Uint8Array(8);
  writeBe32(result, 0, seconds);
  writeBe32(result, 4, fraction);
  return result;
}

function writeBe16(target: Uint8Array, offset: number, value: number): void {
  target[offset] = (value >>> 8) & 0xff;
  target[offset + 1] = value & 0xff;
}

function writeBe32(target: Uint8Array, offset: number, value: number): void {
  target[offset] = (value >>> 24) & 0xff;
  target[offset + 1] = (value >>> 16) & 0xff;
  target[offset + 2] = (value >>> 8) & 0xff;
  target[offset + 3] = value & 0xff;
}
