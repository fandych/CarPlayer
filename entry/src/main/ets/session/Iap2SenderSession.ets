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
import { Iap2SenderSessionFlow } from './iap2/Iap2SenderSessionFlow';

export {
  encodeBuickB233AvailabilityBody,
  isBuickB233Identity,
  isClassicMib3Profile,
  parseMfiCertificatePayload,
  readMessageIds,
  shouldProbeLegacyWifi
} from './iap2/Iap2SessionProtocol';

export {
  parseWirelessSessionCredentials,
  parseWirelessSessionEndpoint,
  WifiCredentials,
  WirelessAirPlayEndpoint
} from './iap2/WirelessSessionParser';

export class Iap2SenderSession extends Iap2SenderSessionFlow {
  get isAccessoryVerified(): boolean {
    return this.mfiVerified;
  }

  get isAuthenticationComplete(): boolean {
    return this.authenticated;
  }

  protected async onControlMessageReceived(messageId: number, body: Uint8Array): Promise<void> {
    await this.receiveControlMessage(messageId, body);
  }

  protected async onIdentificationRequested(): Promise<void> {
    await this.sendControl(MESSAGE.IDENTIFICATION_START);
    this.log('已发送 iAP2 IDENTIFICATION_START，等待车机识别信息');
    this.identificationTimer = setTimeout((): void => {
      this.identificationTimer = undefined;
      if (!this.validatedAccessoryCertificate && !this.authenticated) {
        this.log('等待 iAP2 0x1D01 超时：检查车机是否接受 SYN-ACK、RFCOMM 链路序号与识别消息');
      }
    }, 8000);
  }

  protected onLinkResetDiagnostic(): void {
    if (this.buickB233Receiver && this.buickWaitingForStartSession) {
      this.log(
        `Buick B233 T21：iAP2 link reset while waiting 0x4301；${this.controlAckSnapshot()} ` +
          `frameSHA256prefix=${this.buickAvailabilityFrameDigest}`
      );
    }
  }

  protected onBuickRetransmissionFailure(): boolean {
    return this.buickB233Receiver && this.buickWaitingForStartSession;
  }

  protected onFrameSentWhileBuickWaiting(): boolean {
    return this.buickB233Receiver && this.buickWaitingForStartSession;
  }

  protected getBuickAvailabilityFrameDigest(): string {
    return this.buickAvailabilityFrameDigest;
  }

  setMib3WirelessSessionUuid(sessionUuid: string): void {
    if (!/^[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}$/.test(sessionUuid)) {
      throw new Error('MIB3 virtual iAP2 requires the AirPlay wireless session UUID');
    }
    this.mib3WirelessSessionUuid = sessionUuid;
  }

  get isClassicMib3Receiver(): boolean {
    return isClassicMib3Profile(
      this.accessoryIdentity,
      this.accessorySendMessages,
      this.accessoryReceiveMessages
    );
  }

  async start(sendDetectionMarker: boolean = true): Promise<void> {
    if (this.started) {
      return;
    }
    this.started = true;
    this.detectionRetryCount = 0;
    this.accessoryIdentity = '';
    this.buickB233Receiver = false;
    this.buickAvailabilitySent = false;
    this.buickWaitingForStartSession = false;
    this.buickReidentificationWindowOpen = false;
    this.buickMarkerEchoSent = false;
    this.buickReidentificationUsed = false;
    this.buickReauthenticationInProgress = false;
    this.pendingBuickStartSession = undefined;
    this.deviceAnnouncementSent = false;
    this.deviceAnnouncementInProgress = false;
    this.deviceStateGreetingsSent = false;
    this.accessoryEaProtocols = [];
    this.accessorySendMessages = undefined;
    this.accessoryReceiveMessages = undefined;
    this.wifiConfigurationReceived = false;
    this.startSessionReceived = false;
    this.wifiConfigurationRescueGeneration++;
    this.wifiConfigurationDeadline = -1;
    this.clearPostAuthenticationTimers();
    this.clearBuickStartSessionTimer();
    this.buickAvailabilityFrameDigest = '';
    this.buickAvailabilitySentAt = 0;
    if (sendDetectionMarker) {
      this.log(formatRawBytesDiagnostic('TX', 'RFCOMM iAP2 marker', LINK_MARKER));
      await this.sendBytes(LINK_MARKER.slice());
      this.log('已发送 iAP2 检测标记，等待车机发起链路同步');
      this.scheduleDetectionRetry();
    } else if (this.mfiOnlyVirtualLink) {
      this.log('MIB3 virtual iAP2: waiting for link synchronization on the AirPlay event channel');
      this.scheduleDetectionRetry();
    }
  }

  async receive(bytes: Uint8Array): Promise<void> {
    const receivedBytes = bytes.slice();
    this.log(formatProtocolEvent('iap2.transport.rx',
      'transport', this.mfiOnlyVirtualLink ? 'AirPlay event channel' : 'RFCOMM',
      'chunkBytes', receivedBytes.length
    ));
    const receivedAt = Date.now();
    this.pendingReceiveChunks++;
    const pendingReceive = this.receiveQueue.then(async (): Promise<void> => {
      const queueWaitMs = Date.now() - receivedAt;
      const now = Date.now();
      if (queueWaitMs >= 100 && now - this.lastReceiveQueueDelayLogAt >= 1000) {
        this.lastReceiveQueueDelayLogAt = now;
        this.log(formatProtocolEvent('iap2.transport.receive.queue-delay',
          'queueWaitMs', queueWaitMs,
          'pendingChunks', this.pendingReceiveChunks,
          'meaning', 'RFCOMM 分块在 iAP2 串行接收队列中的等待时间超过 100ms'
        ));
      }
      try {
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
      } finally {
        this.pendingReceiveChunks--;
      }
    });
    this.receiveQueue = pendingReceive.catch((): void => {});
    await pendingReceive;
  }

  private async receiveDetectionMarker(): Promise<void> {
    this.log(formatRawBytesDiagnostic(
      'RX', this.mfiOnlyVirtualLink ? 'AirPlay virtual iAP2 marker' : 'RFCOMM iAP2 marker', LINK_MARKER
    ));
    if (this.buickB233Receiver && this.buickWaitingForStartSession) {
      if (!this.buickMarkerEchoSent) {
        this.buickMarkerEchoSent = true;
        this.log('Buick B233 T31：等待 0x4301 时首次收到 DETECT marker，仅回送一次 marker 并保持 iAP2 会话');
        await this.sendBytes(LINK_MARKER.slice());
      } else {
        this.log('Buick B233 T31：忽略重复 DETECT marker，保持当前 0x4300 等待，不重启链路');
      }
      return;
    }
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
      if (this.wifiConfigurationTimer !== undefined) {
        clearTimeout(this.wifiConfigurationTimer);
        this.wifiConfigurationTimer = undefined;
      }
      this.clearPostAuthenticationTimers();
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
      this.buickB233Receiver = false;
      this.buickAvailabilitySent = false;
      this.buickReidentificationUsed = false;
      this.buickReauthenticationInProgress = false;
      this.pendingBuickStartSession = undefined;
      this.deviceAnnouncementSent = false;
      this.deviceAnnouncementInProgress = false;
      this.deviceStateGreetingsSent = false;
      this.wifiConfigurationRescueGeneration++;
      this.wifiConfigurationDeadline = -1;
      this.buickWaitingForStartSession = false;
      this.buickReidentificationWindowOpen = false;
      this.buickMarkerEchoSent = false;
      this.clearBuickStartSessionTimer();
  }

  private async receiveControlMessage(messageId: number, body: Uint8Array): Promise<void> {
    this.log(formatIap2MessageDiagnostic('RX', messageId, body));
    if (this.mfiOnlyVirtualLink && this.authenticated) {
      if (this.mfiVerified) {
        await this.handleMib3PostAuthenticationMessage(messageId);
      } else {
        this.log(`MIB3 virtual iAP2: suppress message 0x${messageId.toString(16)} before strict MFi verification`);
      }
      return;
    }
    if (messageId === MESSAGE.IDENTIFICATION_INFORMATION) {
      if (this.identificationTimer !== undefined) {
        clearTimeout(this.identificationTimer);
        this.identificationTimer = undefined;
      }
      if (this.buickB233Receiver && this.buickReidentificationUsed) {
        this.log('Buick B233 已使用本轮唯一一次二次识别机会；忽略额外 0x1D01');
        return;
      }
      if (this.buickB233Receiver && this.authenticated && this.buickAvailabilitySent &&
        (!this.buickWaitingForStartSession || !this.buickReidentificationWindowOpen)) {
        this.log('Buick B233 收到 T20 重识别窗口外的 0x1D01；不重置认证状态或重启握手');
        return;
      }
      if (this.buickB233Receiver && this.authenticated && this.buickAvailabilitySent &&
        this.buickWaitingForStartSession && this.buickReidentificationWindowOpen) {
        const repeatedIdentity = readAccessoryIdentity(body);
        if (!isBuickB233Identity(repeatedIdentity) ||
          normalizeAccessoryIdentity(repeatedIdentity) !== normalizeAccessoryIdentity(this.accessoryIdentity)) {
          this.log('Buick B233 0x4300 后收到身份不匹配的 0x1D01；拒绝重置当前会话');
          return;
        }
        this.buickReidentificationUsed = true;
        this.buickReauthenticationInProgress = true;
        this.authenticated = false;
        this.mfiVerified = false;
        this.mfiAuthenticationFailed = false;
        this.validatedAccessoryCertificate = undefined;
        this.clearMfiChallenge();
        this.clearMfiCertificateTimer();
        this.mfiCertificateRequestCount = 0;
        this.challengeIndex = 0;
        this.deviceAnnouncementSent = false;
        this.buickAvailabilitySent = false;
        this.buickWaitingForStartSession = false;
        this.buickReidentificationWindowOpen = false;
        this.buickMarkerEchoSent = false;
        this.clearBuickStartSessionTimer();
        this.deviceStateGreetingsSent = false;
        this.transportIdentifierSent = false;
        this.transportIdentifierPending = false;
        this.log('Buick B233 在 0x4301 等待期间重新发送同一 0x1D01；按实机握手重做一次 MFi');
      }
      this.chooseChallengeLength(body);
      this.logMfiMessageCapabilities(body);
      try {
        this.accessoryEaProtocols = readEaProtocols(body);
      } catch (error) {
        this.accessoryEaProtocols = [];
        this.log(`解析 iAP2 ExternalAccessoryProtocol 失败：${this.errorDetails(error)}`);
      }
      await this.sendControl(MESSAGE.IDENTIFICATION_ACCEPTED);
      this.log('认证消息属于 iAP2 清单例外；即使 1D01 未列出 AA00/AA01，也按标准发起证书请求');
      await this.sendControl(MESSAGE.MFI_CERTIFICATE_REQUEST);
      this.mfiCertificateRequestCount = 1;
      this.startMfiCertificateTimer();
      return;
    }
    if (messageId === MESSAGE.EA_SESSION_STATUS) {
      if (this.eaSessionWaitTimer !== undefined) {
        clearTimeout(this.eaSessionWaitTimer);
        this.eaSessionWaitTimer = undefined;
        this.log(`收到 iAP2 EA_SESSION_STATUS（${body.length}B）`);
        await this.startOptionalHidWait(this.sessionGeneration);
      } else {
        this.log(`收到非等待阶段的 iAP2 EA_SESSION_STATUS（${body.length}B）`);
      }
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
      await this.prioritizeStoredChallengeLength();
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
      this.wifiConfigurationDeadline = -1;
      this.wifiConfigurationRescueGeneration++;
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
      this.wifiConfigurationReceived = true;
      this.clearOptionalHandshakeWaits();
      this.onWifi(credentials);
      await this.sendDeviceAnnouncement();
      if (!this.startSessionReceived) {
        this.startStartSessionWaitTimer(this.sessionGeneration);
      }
      return;
    }
    if (messageId === MESSAGE.CARPLAY_START_SESSION) {
      if (!this.authenticated) {
        if (this.buickReauthenticationInProgress && this.buickB233Receiver) {
          this.pendingBuickStartSession = body.slice();
          this.buickWaitingForStartSession = false;
          this.buickReidentificationWindowOpen = false;
          this.clearBuickStartSessionTimer();
          this.log('Buick B233 二次 MFi 尚未完成；暂存提前到达的 0x4301');
          return;
        }
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
      this.clearWifiConfigurationTimer();
      this.clearStartSessionWaitTimer();
      this.startSessionReceived = true;
      if (this.buickB233Receiver && this.buickWaitingForStartSession) {
        this.buickWaitingForStartSession = false;
        this.buickReidentificationWindowOpen = false;
        this.clearBuickStartSessionTimer();
        this.log(
          `Buick B233 T21：收到 0x4301，等待耗时=${Date.now() - this.buickAvailabilitySentAt}ms；` +
            `${this.controlAckSnapshot()} frameSHA256prefix=${this.buickAvailabilityFrameDigest}`
        );
      }
      try {
        const credentials = parseWirelessSessionCredentials(body);
        if (credentials) {
          this.wifiConfigurationReceived = true;
          this.log(
            `从 0x4301 wireless group 解析网络：SSID=${credentials.ssid}，` +
              `security=${credentials.securityType}，channel=${credentials.channel}，密码已隐藏`
          );
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
      if (this.hidStartWaitTimer !== undefined) {
        clearTimeout(this.hidStartWaitTimer);
        this.hidStartWaitTimer = undefined;
        await this.sendControl(
          MESSAGE.DEVICE_HID_REPORT,
          concatBytes(numberParameter(0, 0, 2), this.parameter(1, new Uint8Array([0])))
        );
        this.log('收到 iAP2 StartHID；已发送 DeviceHIDReport 应答');
        await this.requestWifiConfiguration();
      } else {
        this.log('收到等待窗口外的 iAP2 StartHID；未发送 DeviceHIDReport');
      }
      return;
    }
    if (messageId === MESSAGE.CARPLAY_AVAILABILITY && !this.authenticated) {
      this.log('车机请求开始 CarPlay，但 iAP2 认证尚未完成');
    }
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
