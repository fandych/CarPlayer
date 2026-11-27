import { concatBytes, numberParameter, stringParameter } from '../../protocol/Iap2Codec';
import { MESSAGE, shouldProbeLegacyWifi, WIFI_CONFIGURATION_WINDOW_MS } from './Iap2SessionProtocol';
import { Iap2SenderSessionAuthenticationFlow } from './Iap2SenderSessionAuthenticationFlow';

export abstract class Iap2SenderSessionPostAuthenticationFlow extends Iap2SenderSessionAuthenticationFlow {
  protected abstract sendDeviceAnnouncement(): Promise<void>;
  protected abstract sendDeviceStateGreetings(force?: boolean): Promise<void>;
  protected abstract sendTransportIdentifier(): Promise<void>;
  protected abstract startStartSessionWaitTimer(generation: number): void;
  protected abstract clearStartSessionWaitTimer(): void;

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
}
