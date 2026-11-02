import {
  concatBytes,
  decodeIap2Parameters,
  decodeIap2String,
  encodeUtf8,
  encodeIap2Control,
  encodeIap2LinkFrame,
  formatIap2LinkPayloadDiagnostic,
  formatIap2MessageDiagnostic,
  formatIap2RawFrameDiagnostic,
  Iap2ControlDecoder,
  Iap2LinkDecoder,
  Iap2LinkFrame,
  numberParameter,
  stringParameter
} from '../protocol/Iap2Codec';
import cryptoFramework from '@ohos.security.cryptoFramework';
import i18n from '@ohos.i18n';
import { MfiTrustPromptInfo, MfiVerifier, ValidatedMfiCertificate } from '../iap2/MfiVerifier';
import { formatProtocolEvent, formatRawBytesDiagnostic } from './ProtocolLogger';

const LINK_MARKER: Uint8Array = new Uint8Array([0xff, 0x55, 0x02, 0x00, 0xee, 0x10]);

function formatIap2FrameInterpretation(direction: string, frame: Iap2LinkFrame): string {
  const isSync = (frame.control & 0x80) !== 0;
  const isReset = (frame.control & 0x10) !== 0;
  const payloadSummary = frame.payload.length === 0
    ? 'empty'
    : frame.payload[0] === 0x40 && frame.payload[1] === 0x40
      ? formatIap2LinkPayloadDiagnostic(direction, frame.payload)
      : `non-CSM payload omitted (${frame.payload.length}B)`;
  const meaning = isReset
    ? '链路复位帧，当前 iAP2 会话将终止'
    : isSync
      ? '链路同步帧，声明会话和传输参数'
      : frame.payload.length === 0
        ? '链路控制/确认帧，不包含控制消息'
        : '链路承载控制消息或分片';
  return formatProtocolEvent(`iap2.link.${direction.toLowerCase()}`,
    'control', `0x${frame.control.toString(16).padStart(2, '0')}`,
    'sequence', frame.sequence,
    'acknowledgement', frame.acknowledgement,
    'sessionId', frame.sessionId,
    'payloadBytes', frame.payload.length,
    'payloadSummary', payloadSummary,
    'meaning', meaning
  );
}

interface Iap2MessageIds {
  IDENTIFICATION_START: number;
  IDENTIFICATION_INFORMATION: number;
  IDENTIFICATION_ACCEPTED: number;
  WIFI_REQUEST: number;
  WIFI_CONFIGURATION: number;
  MFI_CERTIFICATE_REQUEST: number;
  MFI_CERTIFICATE: number;
  MFI_CHALLENGE: number;
  MFI_RESPONSE: number;
  MFI_AUTHENTICATION_FAILED: number;
  MFI_AUTHENTICATION_SUCCEEDED: number;
  MFI_CERTIFICATE_SERIAL: number;
  CARPLAY_AVAILABILITY: number;
  CARPLAY_START_SESSION: number;
  WIRELESS_UPDATE: number;
  TRANSPORT_IDENTIFIER: number;
  START_HID: number;
  DEVICE_INFORMATION_UPDATE: number;
  DEVICE_LANGUAGE_UPDATE: number;
  DEVICE_TIME_UPDATE: number;
  DEVICE_UUID_UPDATE: number;
}

const MESSAGE: Iap2MessageIds = {
  IDENTIFICATION_START: 0x1d00,
  IDENTIFICATION_INFORMATION: 0x1d01,
  IDENTIFICATION_ACCEPTED: 0x1d02,
  WIFI_REQUEST: 0x5702,
  WIFI_CONFIGURATION: 0x5703,
  MFI_CERTIFICATE_REQUEST: 0xaa00,
  MFI_CERTIFICATE: 0xaa01,
  MFI_CHALLENGE: 0xaa02,
  MFI_RESPONSE: 0xaa03,
  MFI_AUTHENTICATION_FAILED: 0xaa04,
  MFI_AUTHENTICATION_SUCCEEDED: 0xaa05,
  MFI_CERTIFICATE_SERIAL: 0xaa06,
  CARPLAY_AVAILABILITY: 0x4300,
  CARPLAY_START_SESSION: 0x4301,
  WIRELESS_UPDATE: 0x4e0d,
  TRANSPORT_IDENTIFIER: 0x4e0e,
  START_HID: 0x6800,
  DEVICE_INFORMATION_UPDATE: 0x4e09,
  DEVICE_LANGUAGE_UPDATE: 0x4e0a,
  DEVICE_TIME_UPDATE: 0x4e0b,
  DEVICE_UUID_UPDATE: 0x4e0c
};

function currentDeviceLanguage(): string {
  try {
    return i18n.System.getSystemLanguage() || 'zh-Hans';
  } catch (_error) {
    return 'zh-Hans';
  }
}

export function readMessageIds(value: Uint8Array | undefined): number[] | undefined {
  if (!value || value.length % 2 !== 0) {
    return undefined;
  }
  const messageIds: number[] = [];
  for (let offset = 0; offset < value.length; offset += 2) {
    messageIds.push((value[offset] << 8) | value[offset + 1]);
  }
  return messageIds;
}

export function shouldProbeLegacyWifi(accessorySends?: number[], accessoryReceives?: number[]): boolean {
  if (accessorySends === undefined || accessoryReceives === undefined) {
    return true;
  }
  const declaredCount = accessorySends.length + accessoryReceives.length;
  return accessoryReceives.includes(MESSAGE.WIFI_REQUEST) ||
    accessorySends.includes(MESSAGE.WIFI_CONFIGURATION) ||
    (declaredCount > 0 && declaredCount < 10);
}

export function parseMfiCertificatePayload(body: Uint8Array): Uint8Array {
  const parameters = decodeIap2Parameters(body);
  const certificate = parameters.find((parameter) => parameter.id === 0)?.value;
  const baaMarker = parameters.find((parameter) => parameter.id === 1)?.value;
  const intermediate = parameters.find((parameter) => parameter.id === 2)?.value;
  if (!certificate || certificate.length === 0) {
    throw new Error('AA01 is missing certificate parameter 0');
  }
  if (baaMarker) {
    if (baaMarker.length !== 1 || baaMarker[0] !== 1 || !intermediate || intermediate.length === 0) {
      throw new Error('AA01 BAA certificate package has an invalid marker or intermediate certificate');
    }
    return concatBytes(certificate, intermediate);
  }
  if (intermediate) {
    throw new Error('AA01 has an intermediate certificate without the supported BAA marker');
  }
  return certificate;
}

export interface WifiCredentials {
  ssid: string;
  password: string;
  securityType: number;
  channel: number;
}

export interface WirelessAirPlayEndpoint {
  addresses: string[];
  port: number;
  deviceIdentifier: string;
  publicKey: string;
  unrecognizedIdentity?: string;
  sourceVersion: string;
}

export function parseWirelessSessionEndpoint(body: Uint8Array): WirelessAirPlayEndpoint | undefined {
  const parameters = decodeIap2Parameters(body);
  const values = new Map<number, Uint8Array>();
  for (const parameter of parameters) {
    values.set(parameter.id, parameter.value);
  }
  const wirelessGroup = values.get(1);
  const portBytes = values.get(2);
  const deviceIdentifier = decodeIap2String(values.get(3) ?? new Uint8Array(0));
  const identity = decodeIap2String(values.get(4) ?? new Uint8Array(0));
  const publicKey = /^(?:0x)?[0-9a-fA-F]{64}$/.test(identity) ? identity : '';
  const sourceVersion = decodeIap2String(values.get(5) ?? new Uint8Array(0));
  if (!wirelessGroup || !portBytes || portBytes.length !== 4 || !deviceIdentifier || !sourceVersion) {
    return undefined;
  }
  const port = (((portBytes[0] * 256 + portBytes[1]) * 256 + portBytes[2]) * 256) + portBytes[3];
  if (port < 1 || port > 65535) {
    return undefined;
  }
  const addresses = decodeIap2Parameters(wirelessGroup)
    .filter((parameter) => parameter.id === 3)
    .map((parameter) => decodeIap2String(parameter.value).trim())
    .filter((address) => address.length > 0);
  if (addresses.length === 0) {
    return undefined;
  }
  const result: WirelessAirPlayEndpoint = {
    addresses,
    port,
    deviceIdentifier,
    publicKey,
    unrecognizedIdentity: publicKey ? undefined : identity,
    sourceVersion
  };
  return result;
}

export function parseWirelessSessionCredentials(body: Uint8Array): WifiCredentials | undefined {
  const wirelessGroup = decodeIap2Parameters(body).find((parameter) => parameter.id === 1);
  if (!wirelessGroup) {
    return undefined;
  }
  const values = new Map<number, Uint8Array>();
  for (const parameter of decodeIap2Parameters(wirelessGroup.value)) {
    values.set(parameter.id, parameter.value);
  }
  const ssid = decodeIap2String(values.get(0) ?? new Uint8Array(0));
  if (!ssid) {
    return undefined;
  }
  return {
    ssid,
    password: decodeIap2String(values.get(1) ?? new Uint8Array(0)),
    channel: values.get(2)?.[0] ?? 0,
    securityType: values.get(4)?.[0] ?? 0
  };
}

export class Iap2SenderSession {
  private readonly linkDecoder: Iap2LinkDecoder = new Iap2LinkDecoder();
  private controlDecoder: Iap2ControlDecoder = new Iap2ControlDecoder();
  private readonly sendBytes: (bytes: Uint8Array) => Promise<void>;
  private readonly log: (message: string) => void;
  private readonly onWifi: (credentials: WifiCredentials) => void;
  private readonly onEndpoint: (endpoint: WirelessAirPlayEndpoint | undefined) => void;
  private readonly mfiVerifier: MfiVerifier;
  private receiveQueue: Promise<void> = Promise.resolve();
  private readonly deviceAddress: string;
  private readonly deviceName: string;
  private readonly deviceUuid: string;
  private nextSequence: number = 99;
  private readonly unacknowledgedFrames: Map<number, Iap2LinkFrame> = new Map();
  private readonly outOfOrderFrames: Map<number, Iap2LinkFrame> = new Map();
  private lastReceivedSequence: number = 0;
  private controlSessionId: number = 10;
  private started: boolean = false;
  private sessionGeneration: number = 0;
  private authenticated: boolean = false;
  private mfiVerified: boolean = false;
  private mfiAuthenticationFailed: boolean = false;
  private identificationRequested: boolean = false;
  private lastDetectionResponseAt: number = 0;
  private peerSyncSequence?: number;
  private peerSyncResponse?: Iap2LinkFrame;
  private peerMaxOutstanding: number = 1;
  private peerMaxPacketLength: number = 1024;
  private peerRetransmitTimeoutMs: number = 1500;
  private peerMaxRetransmissions: number = 3;
  private readonly outboundQueue: Iap2LinkFrame[] = [];
  private readonly retransmitCounts: Map<number, number> = new Map();
  private retransmitTimer?: number;
  private detectionRetryTimer?: number;
  private detectionRetryCount: number = 0;
  private accessorySendMessages?: number[];
  private accessoryReceiveMessages?: number[];
  private deviceAnnouncementSent: boolean = false;
  private challengeLength: number = 32;
  private challengeLengths: number[] = [32, 20, 16];
  private challengeIndex: number = 0;
  private validatedAccessoryCertificate?: ValidatedMfiCertificate;
  private pendingMfiChallenge?: Uint8Array;
  private transportIdentifierSent: boolean = false;
  private transportIdentifierPending: boolean = false;
  private transportIdentifierTimer?: number;
  private identificationTimer?: number;
  private challengeTimer?: number;
  private mfiCertificateTimer?: number;
  private mfiCertificateRequestCount: number = 0;
  private wifiConfigurationTimer?: number;

  constructor(
    sendBytes: (bytes: Uint8Array) => Promise<void>,
    log: (message: string) => void,
    onWifi: (credentials: WifiCredentials) => void,
    onEndpoint: (endpoint: WirelessAirPlayEndpoint | undefined) => void,
    deviceAddress: string,
    deviceName: string,
    deviceUuid: string,
    allowMfiIntermediateDownload: boolean = false,
    trustedMfiFingerprints: string[] = [],
    requestMfiTrust?: (info: MfiTrustPromptInfo) => Promise<boolean>,
    persistMfiFingerprint?: (fingerprint: string) => Promise<void>,
    skipMfiChallengeVerification: boolean = false
  ) {
    this.sendBytes = sendBytes;
    this.log = log;
    this.onWifi = onWifi;
    this.onEndpoint = onEndpoint;
    this.deviceAddress = deviceAddress;
    this.deviceName = deviceName;
    this.deviceUuid = deviceUuid;
    this.mfiVerifier = new MfiVerifier(
      log,
      allowMfiIntermediateDownload,
      trustedMfiFingerprints,
      requestMfiTrust,
      persistMfiFingerprint,
      skipMfiChallengeVerification
    );
  }

  get isAccessoryVerified(): boolean {
    return this.mfiVerified;
  }

  get isAuthenticationComplete(): boolean {
    return this.authenticated;
  }

  async start(): Promise<void> {
    if (this.started) {
      return;
    }
    this.started = true;
    this.detectionRetryCount = 0;
    this.log(formatRawBytesDiagnostic('TX', 'RFCOMM iAP2 marker', LINK_MARKER));
    await this.sendBytes(LINK_MARKER.slice());
    this.log('已发送 iAP2 检测标记，等待车机发起链路同步');
    this.scheduleDetectionRetry();
  }

  async receive(bytes: Uint8Array): Promise<void> {
    const receivedBytes = bytes.slice();
    this.log(formatProtocolEvent('iap2.transport.rx',
      'transport', 'RFCOMM',
      'chunkBytes', receivedBytes.length
    ));
    const pendingReceive = this.receiveQueue.then(async (): Promise<void> => {
      if (!this.started) {
        return;
      }
      const events: (Iap2LinkFrame | undefined)[] = [];
      this.linkDecoder.push(receivedBytes, (frame: Iap2LinkFrame | undefined): void => { events.push(frame); });
      for (const frame of events) {
        if (frame) {
          await this.receiveLinkFrame(frame);
        } else {
          await this.receiveDetectionMarker();
        }
      }
    });
    this.receiveQueue = pendingReceive.catch((): void => {});
    await pendingReceive;
  }

  private async receiveDetectionMarker(): Promise<void> {
    this.log(formatRawBytesDiagnostic('RX', 'RFCOMM iAP2 marker', LINK_MARKER));
    const now = Date.now();
    if (this.lastDetectionResponseAt > 0 && now - this.lastDetectionResponseAt < 500) {
      this.log('忽略短时间内重复的 iAP2 检测标记，避免回声循环');
      return;
    }
    this.lastDetectionResponseAt = now;
    if (this.identificationRequested) {
      this.log('车机重新发送 iAP2 检测标记；清除旧认证状态并重新协商链路');
      this.cancel();
      this.controlDecoder = new Iap2ControlDecoder();
      this.nextSequence = 99;
      this.lastReceivedSequence = 0;
      this.controlSessionId = 10;
      this.identificationRequested = false;
      this.peerSyncSequence = undefined;
      this.peerSyncResponse = undefined;
      this.mfiAuthenticationFailed = false;
      this.accessorySendMessages = undefined;
      this.accessoryReceiveMessages = undefined;
      this.deviceAnnouncementSent = false;
      this.challengeIndex = 0;
      this.mfiCertificateRequestCount = 0;
      this.transportIdentifierSent = false;
      this.transportIdentifierPending = false;
      await this.start();
      return;
    }
    this.log('准备检测确认，等待车机发送 SYN');
    this.log(formatRawBytesDiagnostic('TX', 'RFCOMM iAP2 marker', LINK_MARKER));
    await this.sendBytes(LINK_MARKER.slice());
  }

  private scheduleDetectionRetry(): void {
    if (!this.started || this.identificationRequested || this.detectionRetryTimer !== undefined) {
      return;
    }
    const generation = this.sessionGeneration;
    this.detectionRetryTimer = setTimeout((): void => {
      this.detectionRetryTimer = undefined;
      const retry = this.receiveQueue.then(async (): Promise<void> => {
        if (!this.started || generation !== this.sessionGeneration || this.identificationRequested) {
          return;
        }
        if (this.detectionRetryCount >= 15) {
          this.log('iAP2 检测重试已达上限；继续监听迟到的车机响应');
          return;
        }
        this.detectionRetryCount++;
        this.log(`iAP2 检测重试 ${this.detectionRetryCount}/15`);
        await this.sendBytes(LINK_MARKER.slice());
        this.scheduleDetectionRetry();
      });
      this.receiveQueue = retry.catch((error: Error): void => {
        this.log(`iAP2 检测重试失败：${error.message}`);
      });
    }, 1000);
  }

  async onWifiConnected(): Promise<void> {
    if (!this.authenticated) {
      throw new Error('未完成车机 MFi 证书/签名验证；不会发送 CarPlay 会话启动消息');
    }
    if (!this.hasValidDeviceAddress()) {
      throw new Error('缺少有效真实蓝牙 MAC；已阻止发送 CarPlay 设备身份');
    }
    await this.sendDeviceAnnouncement();
    this.transportIdentifierTimer = setTimeout((): void => {
      this.transportIdentifierTimer = undefined;
      void this.sendTransportIdentifier().catch((error: Error): void => {
        this.log(`发送 iAP2 传输标识失败：${error.message}`);
      });
    }, 3000);
  }

  cancel(): void {
      this.sessionGeneration++;
      if (this.detectionRetryTimer !== undefined) {
        clearTimeout(this.detectionRetryTimer);
        this.detectionRetryTimer = undefined;
      }
      if (this.identificationTimer !== undefined) {
        clearTimeout(this.identificationTimer);
        this.identificationTimer = undefined;
      }
      if (this.transportIdentifierTimer !== undefined) {
        clearTimeout(this.transportIdentifierTimer);
        this.transportIdentifierTimer = undefined;
      }
      if (this.wifiConfigurationTimer !== undefined) {
        clearTimeout(this.wifiConfigurationTimer);
        this.wifiConfigurationTimer = undefined;
      }
      this.clearMfiCertificateTimer();
      this.clearMfiChallenge();
      this.clearRetransmitTimer();
      this.unacknowledgedFrames.clear();
      this.outboundQueue.length = 0;
      this.retransmitCounts.clear();
      this.outOfOrderFrames.clear();
      this.validatedAccessoryCertificate = undefined;
      this.authenticated = false;
      this.mfiVerified = false;
      this.started = false;
  }

  private async receiveLinkFrame(frame: Iap2LinkFrame): Promise<void> {
    this.log(formatIap2RawFrameDiagnostic('RX', frame));
    this.log(formatIap2FrameInterpretation('RX', frame));
    if ((frame.control & 0x10) !== 0) {
      this.cancel();
      throw new Error('车机发送 iAP2 链路复位，已终止当前认证会话');
    }
    if ((frame.control & 0x80) !== 0 && frame.payload.length >= 10) {
      if (this.identificationRequested && this.peerSyncSequence === frame.sequence) {
        if ((frame.control & 0x40) === 0 && this.peerSyncResponse) {
          await this.sendLinkFrame(this.peerSyncResponse);
        }
        this.log(`收到重复 iAP2 SYN：seq=${frame.sequence}，保持现有协商状态`);
        return;
      }
      const peerControlSession = this.readControlSessionId(frame.payload);
      if (peerControlSession === undefined) {
        throw new Error('iAP2 同步包没有声明控制会话，无法发送 IDENTIFICATION_START');
      }
      this.lastReceivedSequence = frame.sequence;
      this.controlSessionId = peerControlSession;
      this.peerSyncSequence = frame.sequence;
      this.applyPeerLinkParameters(frame.payload);
      if (this.detectionRetryTimer !== undefined) {
        clearTimeout(this.detectionRetryTimer);
        this.detectionRetryTimer = undefined;
      }
      const isSynAck = (frame.control & 0x40) !== 0;
      if (isSynAck) {
        this.log(`收到 iAP2 SYN-ACK，控制会话 ${this.controlSessionId}`);
      } else {
        const acknowledgement: Iap2LinkFrame = {
          control: 0xc0,
          sequence: this.takeSequence(),
          acknowledgement: frame.sequence,
          sessionId: 0,
          payload: frame.payload.slice()
        };
        this.peerSyncResponse = acknowledgement;
        await this.sendLinkFrame(acknowledgement);
        this.log(`收到 iAP2 同步包，控制会话 ${this.controlSessionId}`);
      }
      if (!this.identificationRequested) {
        this.identificationRequested = true;
        await this.sendControl(MESSAGE.IDENTIFICATION_START);
        this.log('已发送 iAP2 IDENTIFICATION_START，等待车机识别信息');
        this.identificationTimer = setTimeout((): void => {
          this.identificationTimer = undefined;
          if (!this.validatedAccessoryCertificate && !this.authenticated) {
            this.log('等待 iAP2 0x1D01 超时：检查车机是否接受 SYN-ACK、RFCOMM 链路序号与识别消息');
          }
        }, 8000);
      }
      return;
    }
    if ((frame.control & 0x40) !== 0) {
      for (const sequence of Array.from(this.unacknowledgedFrames.keys())) {
        const distance = (frame.acknowledgement - sequence + 256) & 0xff;
        if (distance < 128) {
          this.unacknowledgedFrames.delete(sequence);
          this.retransmitCounts.delete(sequence);
        }
      }
      if (this.unacknowledgedFrames.size === 0) {
        this.clearRetransmitTimer();
      }
      await this.transmitPending();
    }
    if ((frame.control & 0x20) !== 0) {
      this.log(`收到 iAP2 EAK，acknowledgement=${frame.acknowledgement}，selectiveAckBytes=${frame.payload.length}`);
      for (const sequence of frame.payload) {
        const pending = this.unacknowledgedFrames.get(sequence);
        if (pending) {
          this.log(`按 EAK 重发 iAP2 序号 ${sequence}`);
          await this.sendLinkFrame({
              control: pending.control,
              sequence: pending.sequence,
              acknowledgement: this.lastReceivedSequence,
              sessionId: pending.sessionId,
              payload: pending.payload
          });
        }
      }
      return;
    }
    if ((frame.control & 0x40) === 0 || frame.payload.length === 0) {
      return;
    }
    const distance = (frame.sequence - this.lastReceivedSequence + 256) & 0xff;
    if (distance === 0 || distance >= 128) {
      await this.sendLinkFrame({
        control: 0x40,
        sequence: (this.nextSequence - 1) & 0xff,
        acknowledgement: this.lastReceivedSequence,
        sessionId: 0,
        payload: new Uint8Array(0)
      });
      return;
    }
    if (distance > 1) {
      if (distance > 16 || this.outOfOrderFrames.size >= 16) {
        throw new Error('iAP2 乱序帧超过接收窗口');
      }
      this.outOfOrderFrames.set(frame.sequence, frame);
      const missing: number[] = [];
      for (let offset = 1; offset < distance; offset++) {
        const sequence = (this.lastReceivedSequence + offset) & 0xff;
        if (!this.outOfOrderFrames.has(sequence)) {
          missing.push(sequence);
        }
      }
      await this.sendLinkFrame({
        control: 0x60,
        sequence: (this.nextSequence - 1) & 0xff,
        acknowledgement: this.lastReceivedSequence,
        sessionId: 0,
        payload: new Uint8Array(missing)
      });
      return;
    }
    let current: Iap2LinkFrame | undefined = frame;
    while (current) {
      this.lastReceivedSequence = current.sequence;
      await this.acceptDataFrame(current);
      const next = (this.lastReceivedSequence + 1) & 0xff;
      current = this.outOfOrderFrames.get(next);
      this.outOfOrderFrames.delete(next);
    }
  }

  private async acceptDataFrame(frame: Iap2LinkFrame): Promise<void> {
    const acknowledgement: Iap2LinkFrame = {
      control: 0x40,
      sequence: (this.nextSequence - 1) & 0xff,
      acknowledgement: frame.sequence,
      sessionId: 0,
      payload: new Uint8Array(0)
    };
    await this.sendLinkFrame(acknowledgement);
    if (frame.sessionId !== this.controlSessionId) {
      this.log(`忽略非控制会话 ${frame.sessionId} 上的 iAP2 数据`);
      return;
    }
    for (const message of this.controlDecoder.push(frame.payload)) {
      await this.receiveControlMessage(message.messageId, message.body);
    }
  }

  private readControlSessionId(payload: Uint8Array): number | undefined {
    for (let offset = 10; offset + 2 < payload.length; offset += 3) {
      const sessionId = payload[offset];
      const sessionKind = payload[offset + 1];
      if (sessionId !== undefined && sessionId > 0 && sessionKind === 0) {
        return sessionId;
      }
    }
    return undefined;
  }

  private async receiveControlMessage(messageId: number, body: Uint8Array): Promise<void> {
    this.log(formatIap2MessageDiagnostic('RX', messageId, body));
    if (messageId === MESSAGE.IDENTIFICATION_INFORMATION) {
      if (this.identificationTimer !== undefined) {
        clearTimeout(this.identificationTimer);
        this.identificationTimer = undefined;
      }
      this.chooseChallengeLength(body);
      this.logMfiMessageCapabilities(body);
      await this.sendControl(MESSAGE.IDENTIFICATION_ACCEPTED);
      this.log('认证消息属于 iAP2 清单例外；即使 1D01 未列出 AA00/AA01，也按标准发起证书请求');
      await this.sendControl(MESSAGE.MFI_CERTIFICATE_REQUEST);
      this.mfiCertificateRequestCount = 1;
      this.startMfiCertificateTimer();
      return;
    }
    if (messageId === MESSAGE.MFI_CERTIFICATE_SERIAL) {
      if (this.mfiAuthenticationFailed || this.authenticated || this.validatedAccessoryCertificate) {
        this.log('忽略 MFi 认证阶段之外收到的 AA06 certificate serial 通知');
        return;
      }
      this.log('收到车机 AA06 AuthenticationCertificateSerial');
      if (this.mfiCertificateRequestCount >= 2) {
        this.log('AA06 后的 AA00 已重发；忽略重复 AA06，避免无限重发');
        return;
      }
      this.clearMfiCertificateTimer();
      await this.sendControl(MESSAGE.MFI_CERTIFICATE_REQUEST);
      this.mfiCertificateRequestCount++;
      this.startMfiCertificateTimer();
      this.log('已按 AA06 认证变体重新发送 AA00，等待 AA01 证书');
      return;
    }
    if (messageId === MESSAGE.MFI_CERTIFICATE) {
      if (this.mfiAuthenticationFailed || this.authenticated) {
        this.log('忽略当前 iAP2 会话中的重复或已失败 MFi 证书消息');
        return;
      }
      this.clearMfiCertificateTimer();
      let certificatePayload: Uint8Array;
      try {
        certificatePayload = parseMfiCertificatePayload(body);
      } catch (error) {
        this.failMfiAuthentication(`车机 MFi AA01 证书布局无效：${this.errorDetails(error)}`);
        return;
      }
      this.log(
        `收到 MFi AA01 证书消息：body=${body.length}B, certificateChain=${certificatePayload.length}B`
      );
      const generation = this.sessionGeneration;
      try {
        this.log('开始解析 MFi 证书链并执行系统 PKIX/本地 pin 校验');
        const certificate = await this.mfiVerifier.validateAccessoryCertificate(certificatePayload);
        if (!this.started || generation !== this.sessionGeneration) {
          return;
        }
        this.validatedAccessoryCertificate = certificate;
        this.log(
          `MFi 证书校验完成：format=${this.validatedAccessoryCertificate.encodingName}, ` +
            `certificates=${this.validatedAccessoryCertificate.certificateCount}, ` +
            `candidates=${this.validatedAccessoryCertificate.candidates.length}`
        );
      } catch (error) {
        if (!this.started || generation !== this.sessionGeneration) {
          return;
        }
        this.failMfiAuthentication(
          `MFi 证书验证失败：${this.errorDetails(error)}`
        );
        return;
      }
      this.challengeIndex = 0;
      await this.sendMfiChallenge();
      return;
    }
    if (messageId === MESSAGE.MFI_AUTHENTICATION_FAILED) {
      this.log('忽略车机发送的 AA04：AuthenticationFailed 只由设备发往配件');
      return;
    }
    if (messageId === MESSAGE.MFI_RESPONSE) {
      const certificate = this.validatedAccessoryCertificate;
      const challenge = this.pendingMfiChallenge;
      const responseParameters = decodeIap2Parameters(body);
      const signature = responseParameters.find((param) => param.id === 0)?.value;
      this.log(
        `收到 MFi AA03 challenge 响应：body=${body.length}B, parameters=${responseParameters.length}, ` +
          `challenge=${challenge?.length ?? 0}B, signature=${signature?.length ?? 0}B`
      );
      if (!certificate || !challenge || !signature) {
        this.failMfiAuthentication('MFi challenge 响应缺少证书、挑战或签名数据');
        return;
      }
      this.clearChallengeTimer();
      let challengeVerified: boolean = false;
      const generation = this.sessionGeneration;
      try {
        this.log('开始验证 MFi challenge 签名；暂不发送认证成功消息');
        challengeVerified = await this.mfiVerifier.verifyChallenge(certificate, challenge, signature);
      } catch (error) {
        if (!this.started || generation !== this.sessionGeneration) {
          return;
        }
        this.failMfiAuthentication(
          `MFi challenge 签名验证失败：${this.errorDetails(error)}`
        );
        return;
      }
      if (!this.started || generation !== this.sessionGeneration) {
        return;
      }
      await this.finishMfiAuthentication(challengeVerified);
      return;
    }
    if (messageId === MESSAGE.WIFI_CONFIGURATION) {
      if (!this.authenticated) {
        this.log('忽略 MFi 认证完成前收到的 Wi-Fi 配置');
        return;
      }
      if (this.wifiConfigurationTimer !== undefined) {
        clearTimeout(this.wifiConfigurationTimer);
        this.wifiConfigurationTimer = undefined;
      }
      let credentials: WifiCredentials;
      try {
        credentials = this.parseWifi(body);
      } catch (error) {
        this.log(`车机 0x5703 Wi-Fi 配置解析失败：${this.errorDetails(error)}`);
        return;
      }
      this.log(
        `解析车机 Wi-Fi 配置成功：ssidBytes=${encodeUtf8(credentials.ssid).length}, ` +
          `passwordPresent=${credentials.password.length > 0}, security=${credentials.securityType}, ` +
          `channel=${credentials.channel}`
      );
      if (!credentials.ssid) {
        this.log('车机 0x5703 配置缺少 SSID；不会尝试加入网络');
        throw new Error('车机返回的 iAP2 Wi-Fi 配置中没有 SSID');
      }
      this.onWifi(credentials);
      return;
    }
    if (messageId === MESSAGE.CARPLAY_START_SESSION) {
      if (!this.authenticated) {
        this.log('忽略 MFi 认证完成前收到的 CarPlay 会话请求');
        return;
      }
      try {
        decodeIap2Parameters(body);
      } catch (error) {
        this.log(`忽略参数结构无效的 0x4301：${this.errorDetails(error)}`);
        return;
      }
      if (!this.hasValidDeviceAddress()) {
        this.log('收到 CarPlay 会话请求，但真实蓝牙 MAC 未配置；不发送空传输身份');
        return;
      }
      try {
        const credentials = parseWirelessSessionCredentials(body);
        if (credentials) {
          this.log(
            `从 0x4301 wireless group 解析网络：SSID=${credentials.ssid}，` +
              `security=${credentials.securityType}，channel=${credentials.channel}，密码已隐藏`
          );
          this.clearWifiConfigurationTimer();
          this.onWifi(credentials);
        } else {
          this.log('0x4301 未包含有效 wireless group SSID；继续使用端点和 mDNS 信息');
        }
      } catch (error) {
        this.log(`解析 0x4301 wireless group 失败：${this.errorDetails(error)}`);
      }
      let endpoint: WirelessAirPlayEndpoint | undefined;
      try {
        endpoint = parseWirelessSessionEndpoint(body);
      } catch (error) {
        this.log(`解析 0x4301 AirPlay endpoint 失败：${this.errorDetails(error)}`);
      }
      if (!endpoint) {
        this.log('0x4301 未提供可用的 AirPlay 地址、端口或设备信息；启动请求仍交由会话处理');
      }
      this.onEndpoint(endpoint);
      await this.sendTransportIdentifier();
      return;
    }
    if (messageId === MESSAGE.START_HID) {
      this.log('收到 iAP2 StartHID；未声明设备 HID 组件，不发送 DeviceHIDReport');
      return;
    }
    if (messageId === MESSAGE.CARPLAY_AVAILABILITY && !this.authenticated) {
      this.log('车机请求开始 CarPlay，但 iAP2 认证尚未完成');
    }
  }

  private async sendControl(messageId: number, body: Uint8Array = new Uint8Array(0)): Promise<void> {
    const encoded = encodeIap2Control(messageId, body);
    this.log(formatIap2MessageDiagnostic('TX', messageId, body));
    const maximumPayload = Math.max(1, this.peerMaxPacketLength - 10);
    for (let offset = 0; offset < encoded.length; offset += maximumPayload) {
      const payload = encoded.slice(offset, Math.min(encoded.length, offset + maximumPayload));
      this.outboundQueue.push({
        control: 0x40,
        sequence: 0,
        acknowledgement: 0,
        sessionId: this.controlSessionId,
        payload
      });
    }
    await this.transmitPending();
  }

  private async transmitPending(): Promise<void> {
    while (this.outboundQueue.length > 0 && this.unacknowledgedFrames.size < this.peerMaxOutstanding) {
      const queued = this.outboundQueue.shift();
      if (!queued) {
        break;
      }
      await this.sendLinkFrame({
        control: 0x40,
        sequence: this.takeSequence(),
        acknowledgement: this.lastReceivedSequence,
        sessionId: queued.sessionId,
        payload: queued.payload
      });
    }
    if (this.outboundQueue.length > 0) {
      this.log(`iAP2 发送窗口已满（${this.peerMaxOutstanding}），${this.outboundQueue.length} 个分片等待车机 ACK`);
    }
  }

  private applyPeerLinkParameters(payload: Uint8Array): void {
    if (payload.length < 10) {
      return;
    }
    this.peerMaxOutstanding = Math.max(1, payload[1]);
    this.peerMaxPacketLength = Math.max(11, (payload[2] << 8) | payload[3]);
    this.peerRetransmitTimeoutMs = Math.max(200, (payload[4] << 8) | payload[5]);
    this.peerMaxRetransmissions = payload[8];
    this.log(
      `iAP2 链路参数：maxOutstanding=${this.peerMaxOutstanding}, maxPacket=${this.peerMaxPacketLength}, ` +
        `retransmitMs=${this.peerRetransmitTimeoutMs}, maxRetransmissions=${this.peerMaxRetransmissions}`
    );
  }

  private scheduleRetransmit(): void {
    if (this.retransmitTimer !== undefined || this.unacknowledgedFrames.size === 0) {
      return;
    }
    const generation = this.sessionGeneration;
    this.retransmitTimer = setTimeout((): void => {
      this.retransmitTimer = undefined;
      const retry = this.receiveQueue.then(async (): Promise<void> => {
        if (!this.started || generation !== this.sessionGeneration) {
          return;
        }
        await this.retransmitUnacknowledged();
      });
      this.receiveQueue = retry.catch((error: Error): void => {
        this.log(`iAP2 重传失败：${error.message}`);
      });
    }, this.peerRetransmitTimeoutMs);
  }

  private async retransmitUnacknowledged(): Promise<void> {
    for (const pending of Array.from(this.unacknowledgedFrames.values())) {
      const attempts = (this.retransmitCounts.get(pending.sequence) ?? 0) + 1;
      if (attempts > this.peerMaxRetransmissions) {
        this.log(`ERROR: iAP2 序号 ${pending.sequence} 重传 ${this.peerMaxRetransmissions} 次仍未确认；链路视为失效`);
        this.cancel();
        return;
      }
      this.retransmitCounts.set(pending.sequence, attempts);
      this.log(`iAP2 超时重传序号 ${pending.sequence}（${attempts}/${this.peerMaxRetransmissions}）`);
      await this.sendLinkFrame({
        control: pending.control,
        sequence: pending.sequence,
        acknowledgement: this.lastReceivedSequence,
        sessionId: pending.sessionId,
        payload: pending.payload
      });
    }
  }

  private clearRetransmitTimer(): void {
    if (this.retransmitTimer !== undefined) {
      clearTimeout(this.retransmitTimer);
      this.retransmitTimer = undefined;
    }
  }

  private async sendLinkFrame(frame: Iap2LinkFrame, includeMarker: boolean = false): Promise<void> {
    const encodedFrame = encodeIap2LinkFrame(frame);
    this.log(formatIap2RawFrameDiagnostic('TX', frame, includeMarker));
    this.log(formatIap2FrameInterpretation('TX', frame));
    await this.sendBytes(includeMarker ? concatBytes(LINK_MARKER, encodedFrame) : encodedFrame);
    if (frame.control === 0x40 && frame.payload.length > 0) {
      this.unacknowledgedFrames.set(frame.sequence, {
        control: frame.control,
        sequence: frame.sequence,
        acknowledgement: frame.acknowledgement,
        sessionId: frame.sessionId,
        payload: frame.payload.slice()
      });
      this.scheduleRetransmit();
    }
  }

  private parameter(id: number, value: Uint8Array): Uint8Array {
    const result = new Uint8Array(4 + value.length);
    result[0] = (result.length >>> 8) & 0xff;
    result[1] = result.length & 0xff;
    result[2] = (id >>> 8) & 0xff;
    result[3] = id & 0xff;
    result.set(value, 4);
    return result;
  }

  private takeSequence(): number {
    const sequence = this.nextSequence;
    this.nextSequence = (this.nextSequence + 1) & 0xff;
    return sequence;
  }

  private chooseChallengeLength(body: Uint8Array): void {
    const params = decodeIap2Parameters(body);
    let identity = '';
    for (const param of params) {
      if (param.id <= 2) {
        identity += `${decodeIap2String(param.value)} `;
      }
    }
    const normalized = identity.toLowerCase();
    const prefers20ByteChallenge = normalized.includes('audi') ||
        normalized.includes('mib') ||
        normalized.includes('delphi') ||
        normalized.includes('harman') ||
      normalized.includes('porsche');
    this.challengeLengths = prefers20ByteChallenge ? [20, 32, 16] : [32, 20, 16];
    this.challengeLength = this.challengeLengths[0] ?? 32;
    this.challengeIndex = 0;
    this.log(`车机身份已读取，首选 MFi challenge ${this.challengeLength}B`);
  }

  private async sendMfiChallenge(): Promise<void> {
    if (this.mfiAuthenticationFailed || this.authenticated || !this.validatedAccessoryCertificate) {
      return;
    }
    const length = this.challengeLengths[this.challengeIndex];
    if (length === undefined) {
      this.failMfiAuthentication('没有剩余可用的 MFi challenge 长度');
      return;
    }
    this.clearMfiChallenge();
    const generation = this.sessionGeneration;
    try {
      this.log(
        `开始生成 MFi challenge：length=${length}B, attempt=${this.challengeIndex + 1}/` +
          `${this.challengeLengths.length}`
      );
      const challenge = await cryptoFramework.createRandom().generateRandom(length);
      if (!this.started || generation !== this.sessionGeneration) {
        return;
      }
      this.pendingMfiChallenge = new Uint8Array(challenge.data);
      await this.sendControl(MESSAGE.MFI_CHALLENGE, this.parameter(0, this.pendingMfiChallenge));
      if (!this.started || generation !== this.sessionGeneration) {
        return;
      }
      this.log(`已发送 ${length} 字节 MFi challenge (${this.challengeIndex + 1}/${this.challengeLengths.length})`);
      this.challengeTimer = setTimeout((): void => {
        this.challengeTimer = undefined;
        void this.retryMfiChallenge(`MFi ${length} 字节 challenge 等待响应超时`);
      }, length === 20 ? 6000 : 3000);
    } catch (error) {
      if (!this.started || generation !== this.sessionGeneration) {
        return;
      }
      this.failMfiAuthentication(
        `MFi challenge 生成或发送失败：${error instanceof Error ? error.message : String(error)}`
      );
    }
  }

  private async retryMfiChallenge(reason: string): Promise<void> {
    if (this.mfiAuthenticationFailed || this.authenticated || !this.pendingMfiChallenge) {
      return;
    }
    this.clearMfiChallenge();
    this.challengeIndex++;
    if (this.challengeIndex >= this.challengeLengths.length) {
      this.failMfiAuthentication(`${reason}；所有支持的 challenge 长度均已失败`);
      return;
    }
    this.log(`${reason}；尝试 ${this.challengeLengths[this.challengeIndex]} 字节 MFi challenge`);
    await this.sendMfiChallenge();
  }

  private clearChallengeTimer(): void {
    if (this.challengeTimer !== undefined) {
      clearTimeout(this.challengeTimer);
      this.challengeTimer = undefined;
    }
  }

  private startMfiCertificateTimer(): void {
    this.clearMfiCertificateTimer();
    this.mfiCertificateTimer = setTimeout((): void => {
      this.mfiCertificateTimer = undefined;
      this.log(
        `等待车机 AA01 证书超时：AA00 请求次数=${this.mfiCertificateRequestCount}；` +
          '检查车机 1D01 能力声明及是否返回 AA06'
      );
    }, 6000);
  }

  private clearMfiCertificateTimer(): void {
    if (this.mfiCertificateTimer !== undefined) {
      clearTimeout(this.mfiCertificateTimer);
      this.mfiCertificateTimer = undefined;
    }
  }

  private logMfiMessageCapabilities(body: Uint8Array): void {
    try {
      const params = decodeIap2Parameters(body);
      const accessorySends = readMessageIds(params.find((param) => param.id === 6)?.value);
      const accessoryReceives = readMessageIds(params.find((param) => param.id === 7)?.value);
      this.accessorySendMessages = accessorySends;
      this.accessoryReceiveMessages = accessoryReceives;
      this.log(
        `车机 MFi 能力声明：可发 AA01=${accessorySends?.includes(MESSAGE.MFI_CERTIFICATE) === true}, ` +
          `可发 AA03=${accessorySends?.includes(MESSAGE.MFI_RESPONSE) === true}, ` +
          `可收 AA00=${accessoryReceives?.includes(MESSAGE.MFI_CERTIFICATE_REQUEST) === true}, ` +
          `可发 AA06=${accessorySends?.includes(MESSAGE.MFI_CERTIFICATE_SERIAL) === true}`
      );
      this.log('iAP2 Authentication 消息不要求列入 1D01 收发清单；按标准执行证书交换');
    } catch (error) {
      this.log(`解析车机 MFi 消息能力声明失败：${error instanceof Error ? error.message : String(error)}`);
    }
  }

  private async finishMfiAuthentication(challengeVerified: boolean): Promise<void> {
    if (!this.started) {
      return;
    }
    if (!this.mfiVerifier.canContinueAfterChallengeVerification(challengeVerified)) {
      this.failMfiAuthentication('未完成 MFi challenge 签名验证；不会发送 AA05 或继续无线初始化');
      return;
    }
    const generation = this.sessionGeneration;
    try {
      await this.sendControl(MESSAGE.MFI_AUTHENTICATION_SUCCEEDED);
    } catch (error) {
      if (!this.started || generation !== this.sessionGeneration) {
        return;
      }
      this.failMfiAuthentication(`发送 MFi 认证完成通知失败：${this.errorDetails(error)}`);
      return;
    }
    if (!this.started || generation !== this.sessionGeneration) {
      return;
    }
    this.authenticated = true;
    this.mfiVerified = challengeVerified;
    this.validatedAccessoryCertificate = undefined;
    this.clearMfiChallenge();
    this.log(challengeVerified
      ? 'MFi 证书信任校验及 challenge 签名验证均已通过；已发送 AA05'
      : 'WARN: 诊断模式跳过 challenge 验签；已发送 AA05 继续联调，但不会记录为已验证');
    try {
      await this.requestWifiConfiguration();
    } catch (error) {
      this.log(`MFi 认证流程已结束，但启动车机无线配置流程失败：${this.errorDetails(error)}`);
    }
  }

  private async requestWifiConfiguration(): Promise<void> {
    const accessorySends = this.accessorySendMessages;
    const accessoryReceives = this.accessoryReceiveMessages;
    const supportsWirelessSession = accessoryReceives?.includes(MESSAGE.CARPLAY_AVAILABILITY) === true &&
      accessorySends?.includes(MESSAGE.CARPLAY_START_SESSION) === true;
    const capabilitiesKnown = accessorySends !== undefined && accessoryReceives !== undefined;
    const maySupportLegacyExchange = shouldProbeLegacyWifi(accessorySends, accessoryReceives);
    const maySupportWirelessSession = !capabilitiesKnown || supportsWirelessSession ||
      accessoryReceives?.includes(MESSAGE.CARPLAY_AVAILABILITY) === true ||
      accessorySends?.includes(MESSAGE.CARPLAY_START_SESSION) === true;

    if (maySupportWirelessSession && !maySupportLegacyExchange) {
      this.log('车机声明新式 0x4300/0x4301 wireless session；发送设备状态与可用通知');
      await this.sendDeviceAnnouncement();
      this.log('CarPlay 已声明可用，等待车机自动启动或用户选择 CarPlay；保持 iAP2 监听');
      return;
    }
    if (maySupportLegacyExchange) {
      await this.sendControl(MESSAGE.WIFI_REQUEST);
      this.startWifiConfigurationTimer('0x5703', maySupportWirelessSession);
      this.log('已发送 iAP2 0x5702 Wi-Fi 配置请求，等待车机 0x5703');
      return;
    }
    this.log('车机能力表未声明可用的无线凭据流程；不发送未声明的 0x5702');
  }

  private startWifiConfigurationTimer(expected: string, fallbackToWirelessSession: boolean = false): void {
    this.clearWifiConfigurationTimer();
    this.wifiConfigurationTimer = setTimeout((): void => {
      this.wifiConfigurationTimer = undefined;
      if (fallbackToWirelessSession && this.started && this.authenticated && !this.deviceAnnouncementSent) {
        this.log(`车机未及时返回 ${expected}；尝试一次 0x4300/0x4301 无线会话分支`);
        void this.sendDeviceAnnouncement()
          .then((): void => this.log('CarPlay 已声明可用，继续等待车机启动请求'))
          .catch((error: Error): void => {
            this.log(`发送 0x4300 无线会话回退失败：${this.errorDetails(error)}`);
          });
        return;
      }
      this.log(`等待车机 ${expected} 超过 6 秒；仍保持 iAP2 监听，迟到响应仍会处理`);
    }, 6000);
  }

  private clearWifiConfigurationTimer(): void {
    if (this.wifiConfigurationTimer !== undefined) {
      clearTimeout(this.wifiConfigurationTimer);
      this.wifiConfigurationTimer = undefined;
    }
  }

  private async sendDeviceAnnouncement(): Promise<void> {
    if (this.deviceAnnouncementSent) {
      return;
    }
    await this.sendControl(MESSAGE.WIRELESS_UPDATE, numberParameter(0, 1, 1));
    await this.sendControl(MESSAGE.DEVICE_LANGUAGE_UPDATE, stringParameter(0, currentDeviceLanguage()));
    await this.sendControl(MESSAGE.DEVICE_INFORMATION_UPDATE, stringParameter(0, this.deviceName));
    const now = new Date();
    const epochSeconds = Math.floor(now.getTime() / 1000);
    const time = new Uint8Array(8);
    let remaining = epochSeconds;
    for (let index = 7; index >= 0; index--) {
      time[index] = remaining & 0xff;
      remaining = Math.floor(remaining / 256);
    }
    const timeZoneMinutes = 0 - now.getTimezoneOffset();
    await this.sendControl(MESSAGE.DEVICE_TIME_UPDATE, concatBytes(
      this.parameter(0, time),
      numberParameter(1, timeZoneMinutes, 2),
      numberParameter(2, 0, 1)
    ));
    await this.sendControl(MESSAGE.DEVICE_UUID_UPDATE, stringParameter(0, this.deviceUuid));
    await this.sendControl(MESSAGE.CARPLAY_AVAILABILITY, this.parameter(1, concatBytes(
      numberParameter(0, 1, 1),
      stringParameter(1, this.deviceAddress)
    )));
    this.deviceAnnouncementSent = true;
    this.log('已上报设备信息并发送 CarPlay 可用通知');
  }

  private clearMfiChallenge(): void {
    this.clearChallengeTimer();
    this.pendingMfiChallenge?.fill(0);
    this.pendingMfiChallenge = undefined;
  }

  private failMfiAuthentication(message: string): void {
    if (this.mfiAuthenticationFailed || this.authenticated) {
      return;
    }
    this.mfiAuthenticationFailed = true;
    this.authenticated = false;
    this.validatedAccessoryCertificate = undefined;
    this.clearMfiCertificateTimer();
    this.clearMfiChallenge();
    this.log(`MFi 认证失败：${message}`);
    if (this.started) {
      void this.sendControl(MESSAGE.MFI_AUTHENTICATION_FAILED).catch((error: Error): void => {
        this.log(`发送 MFi 认证失败通知 AA04 失败：${this.errorDetails(error)}`);
      });
    }
    this.log('MFi 失败清理完成：已清除 challenge 与证书状态；等待下一次 RFCOMM 会话');
  }

  private errorDetails(error: Error | Object): string {
    if (error instanceof Error) {
      return error.stack ? `${error.message}\n${error.stack}` : error.message;
    }
    return String(error);
  }

  private async sendTransportIdentifier(): Promise<void> {
    if (!this.hasValidDeviceAddress()) {
      this.log('真实蓝牙 MAC 未配置；跳过 iAP2 传输标识发送');
      return;
    }
    if (this.transportIdentifierSent || this.transportIdentifierPending) {
      return;
    }
    this.transportIdentifierPending = true;
    if (this.transportIdentifierTimer !== undefined) {
      clearTimeout(this.transportIdentifierTimer);
      this.transportIdentifierTimer = undefined;
    }
    try {
      await this.sendControl(MESSAGE.TRANSPORT_IDENTIFIER, stringParameter(0, this.deviceAddress));
      this.transportIdentifierSent = true;
    } finally {
      this.transportIdentifierPending = false;
    }
  }

  private hasValidDeviceAddress(): boolean {
    return /^(?!02:00:00:00:00:00$)([0-9A-F]{2}:){5}[0-9A-F]{2}$/.test(this.deviceAddress);
  }

  private parseWifi(body: Uint8Array): WifiCredentials {
    const params = decodeIap2Parameters(body);
    const values = new Map<number, Uint8Array>();
    for (const param of params) {
      values.set(param.id, param.value);
    }
    const result: WifiCredentials = {
      ssid: decodeIap2String(values.get(1) ?? new Uint8Array(0)),
      password: decodeIap2String(values.get(2) ?? new Uint8Array(0)),
      securityType: values.get(3)?.[0] ?? 0,
      channel: values.get(4)?.[0] ?? 0
    };
    return result;
  }
}
