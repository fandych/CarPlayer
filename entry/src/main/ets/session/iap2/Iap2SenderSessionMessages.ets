import {
  concatBytes,
  decodeIap2Parameters,
  decodeIap2String,
  encodeUtf8,
  formatIap2MessageDiagnostic,
  numberParameter
} from '../../protocol/Iap2Codec';
import { MESSAGE } from './Iap2SessionProtocol';
import {
  parseWirelessSessionCredentials,
  parseWirelessSessionEndpoint,
  WifiCredentials,
  WirelessAirPlayEndpoint
} from './WirelessSessionParser';
import { Iap2SenderSessionMfiMessages } from './Iap2SenderSessionMfiMessages';

export abstract class Iap2SenderSessionMessages extends Iap2SenderSessionMfiMessages {
  protected async receiveControlMessage(messageId: number, body: Uint8Array): Promise<void> {
    this.log(formatIap2MessageDiagnostic('RX', messageId, body));
    if (this.mfiOnlyVirtualLink && this.authenticated) {
      if (this.mfiVerified) {
        await this.handleMib3PostAuthenticationMessage(messageId);
      } else {
        this.log(`MIB3 virtual iAP2: suppress message 0x${messageId.toString(16)} before strict MFi verification`);
      }
      return;
    }
    if (await this.handleMfiAuthenticationMessage(messageId, body)) {
      return;
    }
    if (messageId === MESSAGE.WIFI_CONFIGURATION) {
      if (!this.authenticated) {
        this.deferAuthenticatedMessage(messageId, body);
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
        this.deferAuthenticatedMessage(messageId, body);
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
      if (!this.authenticated) {
        this.deferAuthenticatedMessage(messageId, body);
        return;
      }
      if (this.hidStartWaitTimer !== undefined) {
        clearTimeout(this.hidStartWaitTimer);
        this.hidStartWaitTimer = undefined;
      }
      await this.sendControl(
        MESSAGE.DEVICE_HID_REPORT,
        concatBytes(numberParameter(0, 0, 2), this.parameter(1, new Uint8Array([0])))
      );
      this.log('收到 iAP2 StartHID；已发送 DeviceHIDReport 应答');
      if (!this.wifiConfigurationReceived) {
        await this.requestWifiConfiguration();
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
