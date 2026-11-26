import { decodeIap2Parameters, formatIap2MessageDiagnostic } from '../../protocol/Iap2Codec';
import {
  isBuickB233Identity,
  MESSAGE,
  normalizeAccessoryIdentity,
  parseMfiCertificatePayload,
  readAccessoryIdentity,
  readEaProtocols
} from './Iap2SessionProtocol';
import { Iap2SenderSessionFlow } from './Iap2SenderSessionFlow';

export abstract class Iap2SenderSessionMfiMessages extends Iap2SenderSessionFlow {
  protected async handleMfiAuthenticationMessage(messageId: number, body: Uint8Array): Promise<boolean> {
    if (messageId === MESSAGE.IDENTIFICATION_INFORMATION) {
      if (this.identificationTimer !== undefined) {
        clearTimeout(this.identificationTimer);
        this.identificationTimer = undefined;
      }
      if (this.buickB233Receiver && this.buickReidentificationUsed) {
        this.log('Buick B233 已使用本轮唯一一次二次识别机会；忽略额外 0x1D01');
        return true;
      }
      if (this.buickB233Receiver && this.authenticated && this.buickAvailabilitySent &&
        (!this.buickWaitingForStartSession || !this.buickReidentificationWindowOpen)) {
        this.log('Buick B233 收到 T20 重识别窗口外的 0x1D01；不重置认证状态或重启握手');
        return true;
      }
      if (this.buickB233Receiver && this.authenticated && this.buickAvailabilitySent &&
        this.buickWaitingForStartSession && this.buickReidentificationWindowOpen) {
        const repeatedIdentity = readAccessoryIdentity(body);
        if (!isBuickB233Identity(repeatedIdentity) ||
          normalizeAccessoryIdentity(repeatedIdentity) !== normalizeAccessoryIdentity(this.accessoryIdentity)) {
          this.log('Buick B233 0x4300 后收到身份不匹配的 0x1D01；拒绝重置当前会话');
          return true;
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
      if (this.mfiAuthenticationFailed && !this.authenticated) {
        this.mfiAuthenticationFailed = false;
        this.validatedAccessoryCertificate = undefined;
        this.clearMfiChallenge();
        this.clearMfiCertificateTimer();
        this.mfiCertificateRequestCount = 0;
        this.challengeIndex = 0;
        this.log('MFi 认证失败后收到新的 0x1D01；清理旧认证状态并重新开始认证');
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
      return true;
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
      return true;
    }
    if (messageId === MESSAGE.MFI_CERTIFICATE_SERIAL) {
      if (this.mfiAuthenticationFailed || this.authenticated || this.validatedAccessoryCertificate) {
        this.log('忽略 MFi 认证阶段之外收到的 AA06 certificate serial 通知');
        return true;
      }
      this.log('收到车机 AA06 AuthenticationCertificateSerial');
      if (this.mfiCertificateRequestCount >= 2) {
        this.log('AA06 后的 AA00 已重发；忽略重复 AA06，避免无限重发');
        return true;
      }
      this.clearMfiCertificateTimer();
      await this.sendControl(MESSAGE.MFI_CERTIFICATE_REQUEST);
      this.mfiCertificateRequestCount++;
      this.startMfiCertificateTimer();
      this.log('已按 AA06 认证变体重新发送 AA00，等待 AA01 证书');
      return true;
    }
    if (messageId === MESSAGE.MFI_CERTIFICATE) {
      if (this.mfiAuthenticationFailed || this.authenticated) {
        this.log('忽略当前 iAP2 会话中的重复或已失败 MFi 证书消息');
        return true;
      }
      this.clearMfiCertificateTimer();
      let certificatePayload: Uint8Array;
      try {
        certificatePayload = parseMfiCertificatePayload(body);
      } catch (error) {
        this.failMfiAuthentication(`车机 MFi AA01 证书布局无效：${this.errorDetails(error)}`);
        return true;
      }
      this.log(
        `收到 MFi AA01 证书消息：body=${body.length}B, certificateChain=${certificatePayload.length}B`
      );
      const generation = this.sessionGeneration;
      try {
        this.log('开始解析 MFi 证书链并执行系统 PKIX/本地 pin 校验');
        const certificate = await this.mfiVerifier.validateAccessoryCertificate(certificatePayload);
        if (!this.started || generation !== this.sessionGeneration) {
          return true;
        }
        this.validatedAccessoryCertificate = certificate;
        this.log(
          `MFi 证书校验完成：format=${this.validatedAccessoryCertificate.encodingName}, ` +
            `certificates=${this.validatedAccessoryCertificate.certificateCount}, ` +
            `candidates=${this.validatedAccessoryCertificate.candidates.length}`
        );
      } catch (error) {
        if (!this.started || generation !== this.sessionGeneration) {
          return true;
        }
        this.failMfiAuthentication(
          `MFi 证书验证失败：${this.errorDetails(error)}`
        );
        return true;
      }
      await this.prioritizeStoredChallengeLength();
      this.challengeIndex = 0;
      await this.sendMfiChallenge();
      return true;
    }
    if (messageId === MESSAGE.MFI_AUTHENTICATION_FAILED) {
      this.log('忽略车机发送的 AA04：AuthenticationFailed 只由设备发往配件');
      return true;
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
      if (!certificate || !challenge) {
        this.log('当前证书或 challenge 尚未就绪；忽略可能来自较早阶段的 AA03，继续等待有效认证响应');
        if (!certificate && this.mfiCertificateRequestCount === 0 &&
          !this.mfiAuthenticationFailed && !this.authenticated) {
          await this.sendControl(MESSAGE.MFI_CERTIFICATE_REQUEST);
          this.mfiCertificateRequestCount = 1;
          this.startMfiCertificateTimer();
          this.log('已因提前收到 AA03 发起 AA00 证书请求，按正常证书与签名校验流程继续');
        }
        return true;
      }
      if (!signature) {
        this.failMfiAuthentication('MFi challenge 响应缺少证书、挑战或签名数据');
        return true;
      }
      this.clearChallengeTimer();
      let challengeVerified: boolean = false;
      const generation = this.sessionGeneration;
      try {
        this.log('开始验证 MFi challenge 签名；暂不发送认证成功消息');
        challengeVerified = await this.mfiVerifier.verifyChallenge(certificate, challenge, signature);
      } catch (error) {
        if (!this.started || generation !== this.sessionGeneration) {
          return true;
        }
        this.failMfiAuthentication(
          `MFi challenge 签名验证失败：${this.errorDetails(error)}`
        );
        return true;
      }
      if (!this.started || generation !== this.sessionGeneration) {
        return true;
      }
      await this.finishMfiAuthentication(challengeVerified);
      return true;
    }
    return false;
  }
}
