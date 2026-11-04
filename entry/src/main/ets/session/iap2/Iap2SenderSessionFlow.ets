import common from '@ohos.app.ability.common';
import preferences from '@ohos.data.preferences';
import {
  concatBytes,
  decodeIap2Parameters,
  decodeIap2String,
  encodeUtf8,
  encodeIap2Control,
  groupedParameter,
  formatIap2MessageDiagnostic,
  formatIap2RawFrameDiagnostic,
  Iap2ControlDecoder,
  Iap2LinkFrame,
  numberParameter,
  stringParameter
} from '../protocol/Iap2Codec';
import cryptoFramework from '@ohos.security.cryptoFramework';
import { MfiTrustPromptInfo, MfiVerifier, ValidatedMfiCertificate } from '../iap2/MfiVerifier';
import { formatProtocolEvent, formatRawBytesDiagnostic } from './ProtocolLogger';
import {
  currentDeviceLanguage,
  EaProtocol,
  encodeBuickB233AvailabilityBody,
  isBuickB233Identity,
  isClassicMib3Profile,
  LINK_MARKER,
  MESSAGE,
  MIB3_COMMUNICATIONS_IDLE_BODY,
  MIB3_NOW_PLAYING_IDLE_BODY,
  normalizeAccessoryIdentity,
  parseMfiCertificatePayload,
  readAccessoryIdentity,
  readEaProtocols,
  readMessageIds,
  shouldProbeLegacyWifi,
  WIFI_CONFIGURATION_WINDOW_MS
} from './iap2/Iap2SessionProtocol';
import {
  parseWirelessSessionCredentials,
  parseWirelessSessionEndpoint,
  WifiCredentials,
  WirelessAirPlayEndpoint
} from './iap2/WirelessSessionParser';
import { Iap2LinkLayer } from './iap2/Iap2LinkLayer';

export class Iap2SenderSessionFlow extends Iap2LinkLayer {
  protected readonly onWifi: (credentials: WifiCredentials) => void;
  protected readonly onEndpoint: (endpoint: WirelessAirPlayEndpoint | undefined) => void;
  protected readonly onEndpointPending: () => void;
  protected readonly mfiVerifier: MfiVerifier;
  protected readonly mfiOnlyVirtualLink: boolean;
  protected mib3WirelessSessionUuid: string = '';
  protected pendingReceiveChunks: number = 0;
  protected lastReceiveQueueDelayLogAt: number = 0;
  protected readonly deviceAddress: string;
  protected readonly deviceName: string;
  protected readonly deviceUuid: string;
  protected readonly context?: common.UIAbilityContext;
  protected authenticated: boolean = false;
  protected mfiVerified: boolean = false;
  protected mfiAuthenticationFailed: boolean = false;
  protected accessoryIdentity: string = '';
  protected buickB233Receiver: boolean = false;
  protected buickAvailabilitySent: boolean = false;
  protected buickWaitingForStartSession: boolean = false;
  protected buickReidentificationWindowOpen: boolean = false;
  protected buickMarkerEchoSent: boolean = false;
  protected buickReidentificationUsed: boolean = false;
  protected buickReauthenticationInProgress: boolean = false;
  protected pendingBuickStartSession?: Uint8Array;
  protected lastDetectionResponseAt: number = 0;
  protected detectionRetryCount: number = 0;
  protected accessorySendMessages?: number[];
  protected accessoryReceiveMessages?: number[];
  protected accessoryEaProtocols: EaProtocol[] = [];
  protected deviceAnnouncementSent: boolean = false;
  protected deviceAnnouncementInProgress: boolean = false;
  protected challengeLength: number = 32;
  protected challengeLengths: number[] = [32, 20, 16];
  protected challengeIndex: number = 0;
  protected validatedAccessoryCertificate?: ValidatedMfiCertificate;
  protected pendingMfiChallenge?: Uint8Array;
  protected transportIdentifierSent: boolean = false;
  protected transportIdentifierPending: boolean = false;
  protected challengeTimer?: number;
  protected mfiCertificateTimer?: number;
  protected mfiCertificateRequestCount: number = 0;
  protected wifiConfigurationTimer?: number;
  protected wifiConfigurationRescueGeneration: number = 0;
  protected wifiConfigurationDeadline: number = -1;
  protected eaSessionWaitTimer?: number;
  protected hidStartWaitTimer?: number;
  protected startSessionWaitTimer?: number;
  protected wifiConfigurationReceived: boolean = false;
  protected startSessionReceived: boolean = false;
  protected deviceStateGreetingsSent: boolean = false;
  protected buickStartSessionWaitTimer?: number;
  protected buickAvailabilitySentAt: number = 0;
  protected buickAvailabilityFrameDigest: string = '';

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
    skipMfiChallengeVerification: boolean = false,
    context?: common.UIAbilityContext,
    onEndpointPending: () => void = (): void => {},
    mfiOnlyVirtualLink: boolean = false
  ) {
    super(sendBytes, log);
    this.onWifi = onWifi;
    this.onEndpoint = onEndpoint;
    this.onEndpointPending = onEndpointPending;
    this.mfiOnlyVirtualLink = mfiOnlyVirtualLink;
    this.deviceAddress = deviceAddress;
    this.deviceName = deviceName;
    this.deviceUuid = deviceUuid;
    this.context = context;
    this.mfiVerifier = new MfiVerifier(
      log,
      allowMfiIntermediateDownload,
      trustedMfiFingerprints,
      requestMfiTrust,
      persistMfiFingerprint,
      skipMfiChallengeVerification
    );
  }
  protected async handleMib3PostAuthenticationMessage(messageId: number): Promise<void> {
    let responseId: number | undefined;
    let responseBody: Uint8Array = new Uint8Array(0);
    if (messageId === MESSAGE.MIB3_START_CALL_STATE_UPDATES) {
      responseId = MESSAGE.MIB3_CALL_STATE_UPDATE;
      responseBody = this.parameter(0x0002, new Uint8Array([0]));
    } else if (messageId === MESSAGE.MIB3_START_COMMUNICATIONS_UPDATES) {
      responseId = MESSAGE.MIB3_COMMUNICATIONS_UPDATE;
      responseBody = MIB3_COMMUNICATIONS_IDLE_BODY.slice();
    } else if (messageId === MESSAGE.MIB3_START_LIST_UPDATES) {
      responseId = MESSAGE.MIB3_LIST_UPDATE;
      responseBody = concatBytes(
        this.parameter(0x0000, new Uint8Array([0])),
        this.parameter(0x0002, new Uint8Array([0, 0])),
        this.parameter(0x0005, new Uint8Array([0])),
        this.parameter(0x0007, new Uint8Array([0, 0]))
      );
    } else if (messageId === MESSAGE.MIB3_START_NOW_PLAYING_UPDATES) {
      responseId = MESSAGE.MIB3_NOW_PLAYING_UPDATE;
      responseBody = MIB3_NOW_PLAYING_IDLE_BODY.slice();
    }
    if (responseId === undefined) {
      this.log(`MIB3 virtual iAP2: suppress unrelated post-auth message 0x${messageId.toString(16)}`);
      return;
    }
    await this.sendControl(responseId, responseBody);
    this.log(
      `MIB3 virtual iAP2: answered subscription 0x${messageId.toString(16)} ` +
        `with idle response 0x${responseId.toString(16)}`
    );
  }

  protected parameter(id: number, value: Uint8Array): Uint8Array {
    const result = new Uint8Array(4 + value.length);
    result[0] = (result.length >>> 8) & 0xff;
    result[1] = result.length & 0xff;
    result[2] = (id >>> 8) & 0xff;
    result[3] = id & 0xff;
    result.set(value, 4);
    return result;
  }

  protected chooseChallengeLength(body: Uint8Array): void {
    const identity = readAccessoryIdentity(body);
    const normalized = normalizeAccessoryIdentity(identity);
    this.accessoryIdentity = normalized;
    this.buickB233Receiver = isBuickB233Identity(identity);
    if (this.buickB233Receiver) {
      this.challengeLengths = [32];
      this.challengeLength = 32;
      this.challengeIndex = 0;
      this.log('识别为 Buick B233；本车只尝试 32B MFi challenge');
      return;
    }
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

  protected async prioritizeStoredChallengeLength(): Promise<void> {
    if (!this.context || !this.accessoryIdentity || this.buickB233Receiver) {
      return;
    }
    try {
      const digest = cryptoFramework.createMd('SHA256');
      await digest.update({ data: encodeUtf8(this.accessoryIdentity) });
      const identityKey = Array.from((await digest.digest()).data.slice(0, 12))
        .map((value: number): string => value.toString(16).padStart(2, '0')).join('');
      const store = await preferences.getPreferences(this.context, 'carplayer_mfi_challenge_memory');
      const rememberedValue: preferences.ValueType = await store.get(`receiver_${identityKey}`, 0);
      const rememberedLength: number = typeof rememberedValue === 'number' ? rememberedValue : 0;
      if (typeof rememberedLength !== 'number' || !this.challengeLengths.includes(rememberedLength)) {
        return;
      }
      this.challengeLengths = [rememberedLength, ...this.challengeLengths.filter((length) => length !== rememberedLength)];
      this.challengeLength = rememberedLength;
      this.log(`按车机身份记忆优先使用 MFi challenge ${rememberedLength}B`);
    } catch (error) {
      this.log(`读取车机 MFi challenge 记忆失败：${this.errorDetails(error)}`);
    }
  }

  protected async persistSuccessfulChallengeLength(length: number): Promise<void> {
    if (!this.context || !this.accessoryIdentity || this.buickB233Receiver ||
      (length !== 16 && length !== 20 && length !== 32)) {
      return;
    }
    try {
      const digest = cryptoFramework.createMd('SHA256');
      await digest.update({ data: encodeUtf8(this.accessoryIdentity) });
      const identityKey = Array.from((await digest.digest()).data.slice(0, 12))
        .map((value: number): string => value.toString(16).padStart(2, '0')).join('');
      const store = await preferences.getPreferences(this.context, 'carplayer_mfi_challenge_memory');
      await store.put(`receiver_${identityKey}`, length);
      await store.flush();
      this.log(`已为当前车机记忆成功的 ${length}B MFi challenge 长度`);
    } catch (error) {
      this.log(`保存车机 MFi challenge 记忆失败：${this.errorDetails(error)}`);
    }
  }

  protected async sendMfiChallenge(): Promise<void> {
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

  protected async retryMfiChallenge(reason: string): Promise<void> {
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

  protected clearChallengeTimer(): void {
    if (this.challengeTimer !== undefined) {
      clearTimeout(this.challengeTimer);
      this.challengeTimer = undefined;
    }
  }

  protected startMfiCertificateTimer(): void {
    this.clearMfiCertificateTimer();
    this.mfiCertificateTimer = setTimeout((): void => {
      this.mfiCertificateTimer = undefined;
      this.log(
        `等待车机 AA01 证书超时：AA00 请求次数=${this.mfiCertificateRequestCount}；` +
          '检查车机 1D01 能力声明及是否返回 AA06'
      );
    }, 6000);
  }

  protected clearMfiCertificateTimer(): void {
    if (this.mfiCertificateTimer !== undefined) {
      clearTimeout(this.mfiCertificateTimer);
      this.mfiCertificateTimer = undefined;
    }
  }

  protected logMfiMessageCapabilities(body: Uint8Array): void {
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

  protected async finishMfiAuthentication(challengeVerified: boolean): Promise<void> {
    if (!this.started) {
      return;
    }
    if (!this.mfiVerifier.canContinueAfterChallengeVerification(challengeVerified)) {
      this.failMfiAuthentication('未完成 MFi challenge 签名验证；不会发送 AA05 或继续无线初始化');
      return;
    }
    const generation = this.sessionGeneration;
    const successfulChallengeLength = this.pendingMfiChallenge?.length ?? 0;
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
    void this.persistSuccessfulChallengeLength(successfulChallengeLength);
    this.log(challengeVerified
      ? 'MFi 证书信任校验及 challenge 签名验证均已通过；已发送 AA05'
      : 'WARN: 诊断模式跳过 challenge 验签；已发送 AA05 继续联调，但不会记录为已验证');
    if (this.mfiOnlyVirtualLink) {
      if (challengeVerified) {
        await this.sendMib3InitializationBurst();
        this.log('MIB3 virtual iAP2: strict MFi exchange complete; sent runtime device and wireless status');
      } else {
        this.log('MIB3 virtual iAP2: diagnostic MFi bypass did not authorize initialization traffic');
      }
      return;
    }
    if (this.buickReauthenticationInProgress) {
      this.buickReauthenticationInProgress = false;
      const pendingStartSession = this.pendingBuickStartSession;
      this.pendingBuickStartSession = undefined;
      if (pendingStartSession) {
        this.deviceAnnouncementSent = true;
        this.buickAvailabilitySent = true;
        this.log('Buick B233 二次认证期间收到 0x4301；认证完成后继续处理该启动请求');
        await this.receiveControlMessage(MESSAGE.CARPLAY_START_SESSION, pendingStartSession);
        return;
      }
    }
    try {
      if (this.buickB233Receiver) {
        await this.requestWifiConfiguration();
      } else {
        await this.startPostAuthenticationSequence(generation);
      }
    } catch (error) {
      this.log(`MFi 认证流程已结束，但启动车机无线配置流程失败：${this.errorDetails(error)}`);
    }
  }

  protected async startPostAuthenticationSequence(generation: number): Promise<void> {
    await this.sendDeviceStateGreetings();
    if (!this.started || generation !== this.sessionGeneration) {
      return;
    }
    for (const protocol of this.accessoryEaProtocols) {
      await this.sendControl(
        MESSAGE.EA_OPEN_SESSION,
        concatBytes(numberParameter(0, protocol.protocolId, 1), stringParameter(1, protocol.name))
      );
      this.log(`已请求 iAP2 EA 会话：protocol=${protocol.protocolId} name=${protocol.name}`);
    }
    if (this.wifiConfigurationReceived) {
      await this.sendDeviceAnnouncement();
      return;
    }
    if (this.accessoryEaProtocols.length > 0 &&
      this.accessorySendMessages?.includes(MESSAGE.EA_SESSION_STATUS) !== false) {
      this.eaSessionWaitTimer = setTimeout((): void => {
        this.eaSessionWaitTimer = undefined;
        if (!this.started || generation !== this.sessionGeneration) {
          return;
        }
        this.log('等待 iAP2 EA_SESSION_STATUS 超时（500ms）；继续后续启动流程');
        void this.startOptionalHidWait(generation).catch((error: Error): void => {
          this.log(`iAP2 StartHID 等待失败：${this.errorDetails(error)}`);
        });
      }, 500);
      return;
    }
    await this.startOptionalHidWait(generation);
  }

  protected async startOptionalHidWait(generation: number): Promise<void> {
    if (!this.started || !this.authenticated || generation !== this.sessionGeneration) {
      return;
    }
    if (this.wifiConfigurationReceived) {
      await this.sendDeviceAnnouncement();
      return;
    }
    if (this.accessorySendMessages?.includes(MESSAGE.START_HID) === false) {
      this.log('车机未声明会发送 0x6800；跳过可选 StartHID 等待');
      await this.requestWifiConfiguration();
      return;
    }
    this.hidStartWaitTimer = setTimeout((): void => {
      this.hidStartWaitTimer = undefined;
      if (!this.started || !this.authenticated || generation !== this.sessionGeneration) {
        return;
      }
      this.log('等待 iAP2 StartHID 超时（2s）；继续 Wi-Fi 配置交换');
      void this.requestWifiConfiguration().catch((error: Error): void => {
        this.log(`启动 iAP2 Wi-Fi 配置交换失败：${this.errorDetails(error)}`);
      });
    }, 2000);
  }

  protected clearPostAuthenticationTimers(): void {
    this.clearOptionalHandshakeWaits();
    this.clearStartSessionWaitTimer();
  }

  protected clearOptionalHandshakeWaits(): void {
    if (this.eaSessionWaitTimer !== undefined) {
      clearTimeout(this.eaSessionWaitTimer);
      this.eaSessionWaitTimer = undefined;
    }
    if (this.hidStartWaitTimer !== undefined) {
      clearTimeout(this.hidStartWaitTimer);
      this.hidStartWaitTimer = undefined;
    }
  }

  protected async requestWifiConfiguration(): Promise<void> {
    if (this.wifiConfigurationReceived) {
      await this.sendDeviceAnnouncement();
      return;
    }
    if (this.buickB233Receiver) {
      this.log('识别为 Buick B233：跳过不兼容的 0x5702/0x5703 流程，直接发送 B233 格式 0x4300');
      void this.sendDeviceAnnouncement().catch((error: Error): void => {
        this.log(`Buick B233 0x4300 启动失败：${this.errorDetails(error)}`);
      });
      return;
    }
    const accessorySends = this.accessorySendMessages;
    const accessoryReceives = this.accessoryReceiveMessages;
    const maySupportLegacyExchange = shouldProbeLegacyWifi(accessorySends, accessoryReceives);

    if (!maySupportLegacyExchange) {
      this.log('两份完整能力清单均未声明旧式 Wi-Fi；按新协议发送 0x4300/0x4301');
      await this.sendDeviceAnnouncement();
      this.log('CarPlay 已声明可用，等待车机自动启动或用户选择 CarPlay；保持 iAP2 监听');
      return;
    }
    if (maySupportLegacyExchange) {
      if (this.wifiConfigurationDeadline < 0) {
        this.wifiConfigurationDeadline = Date.now() + WIFI_CONFIGURATION_WINDOW_MS;
      }
      await this.sendControl(MESSAGE.WIFI_REQUEST);
      this.startWifiConfigurationTimer('0x5703', true);
      this.log('已发送 iAP2 0x5702 Wi-Fi 配置请求，进入分段等待 0x5703');
      return;
    }
    this.log('车机能力表未声明可用的无线凭据流程；不发送未声明的 0x5702');
  }

  protected startWifiConfigurationTimer(
    expected: string,
    fallbackToWirelessSession: boolean = false,
    stage: number = 0
  ): void {
    if (this.wifiConfigurationTimer !== undefined) {
      clearTimeout(this.wifiConfigurationTimer);
      this.wifiConfigurationTimer = undefined;
    }
    const generation = ++this.wifiConfigurationRescueGeneration;
    const delayMs = stage === 0
      ? 1500
      : stage === 1
        ? 1300
        : Math.max(0, this.wifiConfigurationDeadline - Date.now());
    this.wifiConfigurationTimer = setTimeout((): void => {
      this.wifiConfigurationTimer = undefined;
      if (!this.started || !this.authenticated || generation !== this.wifiConfigurationRescueGeneration) {
        return;
      }
      if (stage === 0) {
        void this.sendDeviceStateGreetings(true).then((): void => {
          if (this.started && this.authenticated && generation === this.wifiConfigurationRescueGeneration) {
            this.log(`车机 ${expected} 首段等待超时；已补发设备状态问候，再等待一次`);
            this.startWifiConfigurationTimer(expected, fallbackToWirelessSession, 1);
          }
        }).catch((error: Error): void => {
          this.log(`补发车机设备状态问候失败：${this.errorDetails(error)}`);
        });
        return;
      }
      if (stage === 1) {
        void this.sendControl(MESSAGE.WIFI_REQUEST).then((): void => {
          if (this.started && this.authenticated && generation === this.wifiConfigurationRescueGeneration) {
            this.log('设备状态问候后仍未收到 0x5703；已重发一次 0x5702');
            this.startWifiConfigurationTimer(expected, fallbackToWirelessSession, 2);
          }
        }).catch((error: Error): void => {
          this.log(`重发 0x5702 失败：${this.errorDetails(error)}`);
        });
        return;
      }
      if (fallbackToWirelessSession && !this.deviceAnnouncementSent) {
        this.wifiConfigurationDeadline = -1;
        this.log(`重发 0x5702 后仍未收到 ${expected}；尝试一次 0x4300/0x4301 无线会话分支`);
        void this.sendDeviceAnnouncement()
          .then((): void => this.log('CarPlay 已声明可用，继续等待车机启动请求'))
          .catch((error: Error): void => {
            this.log(`发送 0x4300 无线会话回退失败：${this.errorDetails(error)}`);
          });
        return;
      }
      this.wifiConfigurationDeadline = -1;
      this.log(`设备问候和一次 0x5702 重发后仍未收到 ${expected}；保持 iAP2 监听，迟到响应仍会处理`);
    }, delayMs);
  }

  protected clearWifiConfigurationTimer(): void {
    this.wifiConfigurationRescueGeneration++;
    this.wifiConfigurationDeadline = -1;
    if (this.wifiConfigurationTimer !== undefined) {
      clearTimeout(this.wifiConfigurationTimer);
      this.wifiConfigurationTimer = undefined;
    }
  }

  protected async sendDeviceAnnouncement(): Promise<void> {
    if (this.deviceAnnouncementSent || this.deviceAnnouncementInProgress) {
      return;
    }
    this.deviceAnnouncementInProgress = true;
    const generation = this.sessionGeneration;
    try {
      await this.sendDeviceStateGreetings(this.buickReidentificationUsed);

      if (this.buickB233Receiver) {
        if (!await this.waitForControlQueueDrain(3000)) {
          throw new Error('B233 device-information ACK timed out before 0x4300');
        }
        await new Promise<void>((resolve): void => { setTimeout(resolve, 1500); });
        if (!this.started || generation !== this.sessionGeneration || !this.authenticated) {
          return;
        }
        const identifier = await this.buickCarPlayDeviceIdentifier();
        const availability = encodeBuickB233AvailabilityBody(identifier, this.deviceAddress.toUpperCase());
        this.buickAvailabilityFrameDigest = await this.controlFrameDigest(
          MESSAGE.CARPLAY_AVAILABILITY, availability
        );
        if (!this.started || generation !== this.sessionGeneration || !this.authenticated) {
          return;
        }
        this.log(
          `Buick B233 T21：发送 0x4300 frameSHA256prefix=${this.buickAvailabilityFrameDigest} ` +
            `preSend=${this.controlAckSnapshot()}`
        );
        await this.sendControl(MESSAGE.CARPLAY_AVAILABILITY, availability);
        this.buickAvailabilitySent = true;
        this.buickWaitingForStartSession = true;
        this.buickReidentificationWindowOpen = true;
        this.buickMarkerEchoSent = false;
        this.buickAvailabilitySentAt = Date.now();
        this.startBuickStartSessionWaitTimer(generation);
        this.log(`Buick B233 双组 0x4300 已发送：bytes=${availability.length}，等待 0x4301`);
      } else {
        await this.sendControl(MESSAGE.CARPLAY_AVAILABILITY, this.parameter(1, concatBytes(
          numberParameter(0, 1, 1),
          stringParameter(1, this.deviceAddress)
        )));
        this.startStartSessionWaitTimer(generation);
      }
      this.deviceAnnouncementSent = true;
      this.log('已上报设备信息并发送 CarPlay 可用通知');
    } finally {
      if (generation === this.sessionGeneration) {
        this.deviceAnnouncementInProgress = false;
      }
    }
  }

  protected startStartSessionWaitTimer(generation: number): void {
    this.clearStartSessionWaitTimer();
    if (this.accessorySendMessages?.includes(MESSAGE.CARPLAY_START_SESSION) === false) {
      this.log('车机未声明会发送 0x4301；按 mDNS AirPlay 路径继续');
      void this.sendTransportIdentifier().catch((error: Error): void => {
        this.log(`发送 iAP2 传输标识失败：${error.message}`);
      });
      return;
    }
    const timeoutMs = this.wifiConfigurationReceived ? 3000 : 8000;
    this.startSessionWaitTimer = setTimeout((): void => {
      this.startSessionWaitTimer = undefined;
      if (!this.started || generation !== this.sessionGeneration || this.startSessionReceived) {
        return;
      }
      this.log(`等待 iAP2 0x4301 超时（${timeoutMs}ms）；保留晚到消息处理`);
      void this.sendTransportIdentifier().catch((error: Error): void => {
        this.log(`发送 iAP2 传输标识失败：${error.message}`);
      });
      if (!this.wifiConfigurationReceived) {
        this.onEndpointPending();
      }
    }, timeoutMs);
  }

  protected clearStartSessionWaitTimer(): void {
    if (this.startSessionWaitTimer !== undefined) {
      clearTimeout(this.startSessionWaitTimer);
      this.startSessionWaitTimer = undefined;
    }
  }

  protected async sendDeviceStateGreetings(force: boolean = false): Promise<void> {
    if (this.deviceStateGreetingsSent && !force) {
      return;
    }
    if (!this.buickB233Receiver) {
      await this.sendControl(MESSAGE.WIRELESS_UPDATE, numberParameter(0, 1, 1));
    }
    const now = new Date();
    const epochSeconds = Math.floor(now.getTime() / 1000);
    const time = new Uint8Array(8);
    let remaining = epochSeconds;
    for (let index = 7; index >= 0; index--) {
      time[index] = remaining & 0xff;
      remaining = Math.floor(remaining / 256);
    }
    const timeZoneMinutes = 0 - now.getTimezoneOffset();
    const timeBody = concatBytes(
      this.parameter(0, time),
      numberParameter(1, timeZoneMinutes, 2),
      numberParameter(2, 0, 1)
    );
    const deviceUuid = this.mfiOnlyVirtualLink && this.mib3WirelessSessionUuid.length > 0
      ? this.mib3WirelessSessionUuid
      : this.deviceUuid;
    if (this.buickB233Receiver && this.buickReidentificationUsed) {
      await this.sendControl(MESSAGE.DEVICE_UUID_UPDATE, stringParameter(0, deviceUuid));
      await this.sendControl(MESSAGE.DEVICE_LANGUAGE_UPDATE, stringParameter(0, currentDeviceLanguage()));
      await this.sendControl(MESSAGE.DEVICE_TIME_UPDATE, timeBody);
      await this.sendControl(MESSAGE.DEVICE_INFORMATION_UPDATE, stringParameter(0, this.deviceName));
    } else {
      await this.sendControl(MESSAGE.DEVICE_LANGUAGE_UPDATE, stringParameter(0, currentDeviceLanguage()));
      await this.sendControl(MESSAGE.DEVICE_INFORMATION_UPDATE, stringParameter(0, this.deviceName));
      await this.sendControl(MESSAGE.DEVICE_TIME_UPDATE, timeBody);
      await this.sendControl(MESSAGE.DEVICE_UUID_UPDATE, stringParameter(0, deviceUuid));
    }
    this.deviceStateGreetingsSent = true;
  }

  protected async sendMib3InitializationBurst(): Promise<void> {
    const sessionUuid = this.mib3WirelessSessionUuid;
    if (!sessionUuid) {
      throw new Error('MIB3 virtual iAP2 initialization requires an AirPlay wireless session UUID');
    }
    const now = new Date();
    const epochSeconds = Math.floor(now.getTime() / 1000);
    const time = new Uint8Array(8);
    let remaining = epochSeconds;
    for (let index = 7; index >= 0; index--) {
      time[index] = remaining & 0xff;
      remaining = Math.floor(remaining / 256);
    }
    const januaryOffset = new Date(now.getFullYear(), 0, 1).getTimezoneOffset();
    const julyOffset = new Date(now.getFullYear(), 6, 1).getTimezoneOffset();
    const standardOffset = Math.max(januaryOffset, julyOffset);
    const daylightSaving = now.getTimezoneOffset() < standardOffset ? 1 : 0;
    const timeBody = concatBytes(
      this.parameter(0, time),
      numberParameter(1, 0 - now.getTimezoneOffset(), 2),
      numberParameter(2, daylightSaving, 1)
    );
    await this.sendControl(MESSAGE.DEVICE_UUID_UPDATE, stringParameter(0, sessionUuid));
    await this.sendControl(
      MESSAGE.AUX_STATUS_NOTIFICATION,
      this.parameter(0x0006, new Uint8Array(0))
    );
    await this.sendControl(MESSAGE.DEVICE_LANGUAGE_UPDATE, stringParameter(0, 'zh'));
    await this.sendControl(MESSAGE.DEVICE_TIME_UPDATE, timeBody);
    await this.sendControl(MESSAGE.DEVICE_INFORMATION_UPDATE, stringParameter(0, 'iPhone'));
  }

  protected async controlFrameDigest(messageId: number, body: Uint8Array): Promise<string> {
    try {
      const digest = cryptoFramework.createMd('SHA256');
      await digest.update({ data: encodeIap2Control(messageId, body) });
      return Array.from((await digest.digest()).data.slice(0, 8))
        .map((value: number): string => value.toString(16).padStart(2, '0')).join('');
    } catch (error) {
      this.log(`Buick B233 T21：计算 0x4300 脱敏摘要失败，不影响发送：${this.errorDetails(error)}`);
      return 'unavailable';
    }
  }

  protected startBuickStartSessionWaitTimer(generation: number): void {
    this.clearBuickStartSessionTimer();
    this.buickStartSessionWaitTimer = setTimeout((): void => {
      this.buickStartSessionWaitTimer = undefined;
      if (!this.started || generation !== this.sessionGeneration || !this.buickWaitingForStartSession) {
        return;
      }
      this.log(
        `Buick B233 T21：0x4301 等待超时，耗时=${Date.now() - this.buickAvailabilitySentAt}ms；` +
          `${this.controlAckSnapshot()} frameSHA256prefix=${this.buickAvailabilityFrameDigest} ` +
          `markerEchoSent=${this.buickMarkerEchoSent} reidentificationWindow=closed`
      );
      this.buickReidentificationWindowOpen = false;
    }, 30000);
  }

  protected clearBuickStartSessionTimer(): void {
    if (this.buickStartSessionWaitTimer !== undefined) {
      clearTimeout(this.buickStartSessionWaitTimer);
      this.buickStartSessionWaitTimer = undefined;
    }
  }

  protected async buickCarPlayDeviceIdentifier(): Promise<string> {
    const digest = cryptoFramework.createMd('SHA256');
    await digest.update({ data: encodeUtf8(`CarDeck-CarPlay:${this.deviceAddress.toUpperCase()}`) });
    const bytes = (await digest.digest()).data.slice(0, 12);
    return Array.from(bytes).map((value: number): string => value.toString(16).padStart(2, '0')).join('').toUpperCase();
  }

  protected clearMfiChallenge(): void {
    this.clearChallengeTimer();
    this.pendingMfiChallenge?.fill(0);
    this.pendingMfiChallenge = undefined;
  }

  protected failMfiAuthentication(message: string): void {
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

  protected errorDetails(error: Error | Object): string {
    if (error instanceof Error) {
      return error.stack ? `${error.message}\n${error.stack}` : error.message;
    }
    return String(error);
  }

  protected async sendTransportIdentifier(): Promise<void> {
    if (!this.hasValidDeviceAddress()) {
      this.log('真实蓝牙 MAC 未配置；跳过 iAP2 传输标识发送');
      return;
    }
    if (this.transportIdentifierSent || this.transportIdentifierPending) {
      return;
    }
    this.transportIdentifierPending = true;
    try {
      await this.sendControl(MESSAGE.TRANSPORT_IDENTIFIER, stringParameter(0, this.deviceAddress));
      this.transportIdentifierSent = true;
    } finally {
      this.transportIdentifierPending = false;
    }
  }

  protected hasValidDeviceAddress(): boolean {
    return /^(?!02:00:00:00:00:00$)([0-9A-F]{2}:){5}[0-9A-F]{2}$/.test(this.deviceAddress);
  }

}
