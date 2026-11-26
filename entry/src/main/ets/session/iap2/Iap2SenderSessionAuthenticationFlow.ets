import preferences from '@ohos.data.preferences';
import cryptoFramework from '@ohos.security.cryptoFramework';
import { decodeIap2Parameters, encodeUtf8 } from '../../protocol/Iap2Codec';
import {
  isBuickB233Identity,
  MESSAGE,
  normalizeAccessoryIdentity,
  readAccessoryIdentity,
  readMessageIds
} from './Iap2SessionProtocol';
import { Iap2SenderSessionState } from './Iap2SenderSessionState';

export abstract class Iap2SenderSessionAuthenticationFlow extends Iap2SenderSessionState {
  protected abstract startPostAuthenticationSequence(generation: number): Promise<void>;
  protected abstract requestWifiConfiguration(): Promise<void>;
  protected abstract sendMib3InitializationBurst(): Promise<void>;

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
        await this.replayAuthenticatedMessages();
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
    await this.replayAuthenticatedMessages();
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
}
