import cryptoFramework from '@ohos.security.cryptoFramework';
import {
  concatBytes,
  encodeIap2Control,
  encodeUtf8,
  numberParameter,
  stringParameter
} from '../../protocol/Iap2Codec';
import { currentDeviceLanguage, encodeBuickB233AvailabilityBody, MESSAGE } from './Iap2SessionProtocol';
import { Iap2SenderSessionPostAuthenticationFlow } from './Iap2SenderSessionPostAuthenticationFlow';

export abstract class Iap2SenderSessionAnnouncements extends Iap2SenderSessionPostAuthenticationFlow {
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
