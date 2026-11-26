import {
  formatProtocolEvent,
  formatRawBytesDiagnostic
} from '../ProtocolLogger';
import { Iap2ControlDecoder, Iap2LinkFrame } from '../../protocol/Iap2Codec';
import { LINK_MARKER, MESSAGE } from './Iap2SessionProtocol';
import { Iap2SenderSessionMessages } from './Iap2SenderSessionMessages';

export abstract class Iap2SenderSessionTransport extends Iap2SenderSessionMessages {
  async start(sendDetectionMarker: boolean = true): Promise<void> {
    if (this.started) {
      return;
    }
    this.started = true;
    this.detectionRetryCount = 0;
    this.authenticated = false;
    this.mfiVerified = false;
    this.mfiAuthenticationFailed = false;
    this.mfiCertificateRequestCount = 0;
    this.challengeIndex = 0;
    this.validatedAccessoryCertificate = undefined;
    this.clearMfiChallenge();
    this.clearMfiCertificateTimer();
    this.accessoryIdentity = '';
    this.buickB233Receiver = false;
    this.buickAvailabilitySent = false;
    this.buickWaitingForStartSession = false;
    this.buickReidentificationWindowOpen = false;
    this.buickMarkerEchoSent = false;
    this.buickReidentificationUsed = false;
    this.buickReauthenticationInProgress = false;
    this.pendingBuickStartSession = undefined;
    this.pendingAuthenticatedMessages.length = 0;
    this.transportIdentifierSent = false;
    this.transportIdentifierPending = false;
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
      this.peerSyncPayload = undefined;
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
      this.pendingAuthenticatedMessages.length = 0;
      this.deviceAnnouncementSent = false;
      this.deviceAnnouncementInProgress = false;
      this.deviceStateGreetingsSent = false;
      this.wifiConfigurationRescueGeneration++;
      this.wifiConfigurationDeadline = -1;
      this.buickWaitingForStartSession = false;
      this.buickReidentificationWindowOpen = false;
      this.buickMarkerEchoSent = false;
      this.clearBuickStartSessionTimer();
      this.mfiAuthenticationFailed = false;
  }
}
