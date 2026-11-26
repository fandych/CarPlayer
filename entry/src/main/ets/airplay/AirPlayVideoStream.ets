import { MediaPacketCipher } from '../crypto/MediaPacketCipher';
import cryptoFramework from '@ohos.security.cryptoFramework';
import { concatBytes } from '../protocol/Iap2Codec';
import { formatProtocolEvent } from '../session/ProtocolLogger';
import {
  AirPlayVideoEncryptionMode,
  EncodedH264Event,
  CHACHA_TAG_SIZE,
  ENCRYPTED_VIDEO_FLAG,
  H264_SYNC_FRAME_FLAG,
  VIDEO_CONFIG_OPCODE,
  VIDEO_FRAME_OPCODE,
  buildAirPlayVideoConfigHeader,
  buildAirPlayVideoFrameHeader,
  buildAvcConfigurationRecord,
  buildVideoFrameNonce,
  containsH264Idr,
  packH264Nals,
  patchH264SpsLevel,
  sameNalUnit,
  splitH264NalUnits,
  validateVideoShape
} from './AirPlayVideoPackets';
import { finishLegacyVideoCipher, initializeLegacyVideoCipher } from './AirPlayVideoLegacyCipher';
import { AirPlayVideoFrameQueue } from './AirPlayVideoFrameQueue';

export class AirPlayVideoStreamSender {
  private readonly cipher?: MediaPacketCipher;
  private readonly encryption: AirPlayVideoEncryptionMode;
  private readonly streamKey: Uint8Array;
  private readonly streamIv?: Uint8Array;
  private legacyCipher?: cryptoFramework.Cipher;
  private readonly width: number;
  private readonly height: number;
  private readonly sendBytes: (data: Uint8Array) => Promise<void>;
  private readonly log: (message: string) => void;
  private readonly eventQueue: AirPlayVideoFrameQueue;
  private frameCounter: bigint = BigInt(0);
  private configSent: boolean = false;
  private pendingSps?: Uint8Array;
  private pendingPps?: Uint8Array;
  private framesSent: number = 0;
  private awaitingConfigKeyFrame: boolean = true;

  constructor(
    streamKey: Uint8Array,
    width: number,
    height: number,
    sendBytes: (data: Uint8Array) => Promise<void>,
    log: (message: string) => void,
    requestKeyFrame: () => void = (): void => {},
    encryption: AirPlayVideoEncryptionMode = AirPlayVideoEncryptionMode.CHACHA20_POLY1305,
    streamIv?: Uint8Array
  ) {
    validateVideoShape(width, height);
    if (encryption === AirPlayVideoEncryptionMode.CHACHA20_POLY1305 && streamKey.length !== 32) {
      throw new Error('AirPlay ChaCha20-Poly1305 screen-stream key must be 32 bytes');
    }
    if (encryption === AirPlayVideoEncryptionMode.AES_128_CTR &&
      (streamKey.length !== 16 || streamIv?.length !== 16)) {
      throw new Error('AirPlay AES-128-CTR screen stream requires a 16-byte key and IV');
    }
    this.encryption = encryption;
    this.streamKey = streamKey.slice();
    this.streamIv = streamIv?.slice();
    if (encryption === AirPlayVideoEncryptionMode.CHACHA20_POLY1305) {
      this.cipher = new MediaPacketCipher(streamKey, true, log);
    }
    this.width = width;
    this.height = height;
    this.sendBytes = sendBytes;
    this.log = log;
    this.eventQueue = new AirPlayVideoFrameQueue(
      (event: EncodedH264Event): Promise<void> => this.processEvent(event),
      log,
      requestKeyFrame
    );
  }

  async initialize(): Promise<void> {
    if (this.encryption === AirPlayVideoEncryptionMode.AES_128_CTR) {
      this.legacyCipher = await initializeLegacyVideoCipher(this.streamKey, this.streamIv);
    }
  }

  async finish(): Promise<void> {
    const cipher = this.legacyCipher;
    this.legacyCipher = undefined;
    await finishLegacyVideoCipher(cipher);
  }

  handleEncoderEvent(event: EncodedH264Event): Promise<void> {
    return this.eventQueue.handleEncoderEvent(event);
  }

  async flush(): Promise<void> {
    await this.eventQueue.flush();
  }

  private async processEvent(event: EncodedH264Event): Promise<void> {
    if (event.type === 'error' || event.type === 'overflow') {
      throw new Error(event.message || `Native H.264 encoder reported ${event.type}`);
    }
    if (event.type === 'streamChanged') {
      this.log('H.264 encoder output format changed; awaiting codec configuration');
      this.configSent = false;
      this.pendingSps = undefined;
      this.pendingPps = undefined;
      this.awaitingConfigKeyFrame = true;
      this.eventQueue.requestRecoveryKeyFrame();
      return;
    }
    const data = event.data;
    if (!data || data.length === 0) {
      return;
    }
    const units = splitH264NalUnits(data);
    if (event.type === 'codecConfig') {
      await this.collectCodecConfiguration(units);
      if (!units.some((unit: Uint8Array): boolean =>
        unit.length > 0 && (unit[0] & 0x1f) >= 1 && (unit[0] & 0x1f) <= 5)) {
        return;
      }
    }
    if (!this.configSent || units.some((unit: Uint8Array): boolean =>
      unit.length > 0 && ((unit[0] & 0x1f) === 7 || (unit[0] & 0x1f) === 8))) {
      await this.collectCodecConfiguration(units);
      if (!this.configSent) {
        return;
      }
    }
    if (this.awaitingConfigKeyFrame) {
      if ((event.flags & H264_SYNC_FRAME_FLAG) === 0 && !containsH264Idr(units)) {
        return;
      }
      this.awaitingConfigKeyFrame = false;
    }
    await this.sendFrame(units);
  }

  private async collectCodecConfiguration(units: Uint8Array[]): Promise<void> {
    let changed = false;
    for (const unit of units) {
      if (unit.length === 0) {
        continue;
      }
      const type = unit[0] & 0x1f;
      if (type === 7) {
        changed ||= !sameNalUnit(this.pendingSps, unit);
        this.pendingSps = unit.slice();
      } else if (type === 8) {
        changed ||= !sameNalUnit(this.pendingPps, unit);
        this.pendingPps = unit.slice();
      }
    }
    if (changed && this.configSent) {
      this.configSent = false;
      this.awaitingConfigKeyFrame = true;
      this.eventQueue.requestRecoveryKeyFrame();
    }
    if (!this.pendingSps || !this.pendingPps || this.configSent) {
      return;
    }
    const record = buildAvcConfigurationRecord([patchH264SpsLevel(this.pendingSps), this.pendingPps]);
    const header = buildAirPlayVideoConfigHeader(record.length, this.width, this.height);
    const packet = concatBytes(header, record);
    await this.sendBytes(packet);
    this.configSent = true;
    this.log(formatProtocolEvent('airplay.video.codec_config.tx',
      'width', this.width,
      'height', this.height,
      'configurationBytes', record.length,
      'wireBytes', packet.length,
      'levelIdc', record[3] ?? 0
    ));
    this.log(formatProtocolEvent('protocol.interpretation',
      'transport', 'AirPlay video/TCP',
      'meaning', '发送 H.264 SPS/PPS 配置记录；接收端用它初始化解码器，未记录媒体内容'
    ));
  }

  private async sendFrame(units: Uint8Array[]): Promise<void> {
    const filtered = units.filter((unit: Uint8Array): boolean => unit.length > 0)
      .map((unit: Uint8Array): Uint8Array => (unit[0] & 0x1f) === 7 ? patchH264SpsLevel(unit) : unit);
    if (filtered.length === 0) {
      return;
    }
    const plain = packH264Nals(filtered);
    const plainLength = plain.length;
    const timestampMs = Date.now();
    const encryptedLength = this.encryption === AirPlayVideoEncryptionMode.CHACHA20_POLY1305
      ? plainLength + CHACHA_TAG_SIZE
      : plainLength;
    const header = buildAirPlayVideoFrameHeader(encryptedLength, timestampMs);
    const frameCounter = this.frameCounter;
    const frameNumber = this.framesSent + 1;
    const nalTypes = filtered.map((unit: Uint8Array): string => String(unit[0] & 0x1f));
    const hasIdr = containsH264Idr(filtered);
    const nonce = buildVideoFrameNonce(frameCounter);
    this.frameCounter++;
    let encrypted: Uint8Array;
    if (this.encryption === AirPlayVideoEncryptionMode.CHACHA20_POLY1305) {
      const cipher = this.cipher;
      if (!cipher) {
        throw new Error('AirPlay ChaCha20-Poly1305 stream cipher is not initialized');
      }
      encrypted = await cipher.seal(nonce, plain, header);
    } else {
      encrypted = await this.encryptLegacyFrame(plain);
    }
    await this.sendBytes(concatBytes(header, encrypted));
    this.framesSent = frameNumber;
    this.log(formatProtocolEvent('airplay.video.frame.tx',
      'frame', frameNumber,
      'nonceCounter', frameCounter.toString(),
      'timestampMs', timestampMs,
      'width', this.width,
      'height', this.height,
      'nalTypes', nalTypes,
      'keyFrame', hasIdr,
      'mediaBytes', plainLength,
      'encryptedBytes', encrypted.length,
      'wireBytes', header.length + encrypted.length
    ));
    this.log(formatProtocolEvent('protocol.interpretation',
      'transport', 'AirPlay video/TCP',
      'meaning', `发送 H.264 ${hasIdr ? '关键帧' : '视频帧'}；NAL 类型和帧计数用于诊断解码/丢帧，载荷未写入日志`
    ));
  }

  private async encryptLegacyFrame(plain: Uint8Array): Promise<Uint8Array> {
    const cipher = this.legacyCipher;
    if (!cipher) {
      throw new Error('AirPlay AES-128-CTR stream cipher is not initialized');
    }
    const encrypted = (await cipher.update({ data: plain })).data;
    if (encrypted.length !== plain.length) {
      throw new Error('AirPlay AES-128-CTR changed the screen-frame length');
    }
    return encrypted;
  }
}

export {
  AIRPLAY_VIDEO_HEADER_SIZE,
  AirPlayVideoEncryptionMode,
  EncodedH264Event,
  buildAirPlayVideoConfigHeader,
  buildAirPlayVideoFrameHeader,
  buildAvcConfigurationRecord,
  buildVideoFrameNonce,
  packH264Nals,
  patchH264SpsLevel,
  splitH264NalUnits
} from './AirPlayVideoPackets';
