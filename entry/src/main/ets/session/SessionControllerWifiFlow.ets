import { WifiCredentials } from './Iap2SenderSession';
import { SessionControllerShutdown } from './SessionControllerShutdown';

export abstract class SessionControllerWifiFlow extends SessionControllerShutdown {
  setManualWifi(ssid: string, password: string): void {
    if (!ssid.trim()) {
      throw new Error('请输入车机热点名称');
    }
    const normalizedSsid = ssid.trim();
    if (this.credentials && this.credentials.ssid === normalizedSsid) {
      this.credentials.password = password;
      return;
    }
    this.credentials = { ssid: normalizedSsid, password, securityType: 2, channel: 0 };
  }
  async joinVehicleWifi(): Promise<void> {
    if (this.wifiLostCleanupInProgress) {
      this.events.onLog('车机 Wi-Fi 丢失清理仍在进行，暂不启动新的网络加入');
      return;
    }
    if (this.vehicleWifiConnected) {
      this.events.onLog('车机 Wi-Fi 已连接，忽略重复加入请求');
      return;
    }
    if (this.wifiJoinInProgress) {
      this.events.onLog('车机 Wi-Fi 连接已在等待系统确认');
      return;
    }
    if (!this.running) {
      throw new Error('CarPlay 已关闭，不能加入车机热点');
    }
    if (!this.credentials) {
      throw new Error('尚未收到车机热点配置，请填写热点名称和密码');
    }
    const iap2 = this.iap2;
    if (!iap2?.isAuthenticationComplete) {
      throw new Error('iAP2 MFi 验证尚未完成；拒绝启动车机 Wi-Fi/AirPlay 会话');
    }
    if (!/^(?!02:00:00:00:00:00$)([0-9A-F]{2}:){5}[0-9A-F]{2}$/.test(this.deviceAddress)) {
      const message = '蓝牙 RFCOMM 监听与 MFi 认证正常；完整 CarPlay 会话需要先在设置中填写真实蓝牙 MAC';
      this.events.onStatus(message);
      this.events.onLog(message);
      return;
    }
    this.wifiJoinInProgress = true;
    this.clearWifiReconnectTimer();
    const joinGeneration = ++this.wifiJoinGeneration;
    const credentials: WifiCredentials = {
      ssid: this.credentials.ssid,
      password: this.credentials.password,
      securityType: this.credentials.securityType,
      channel: this.credentials.channel
    };
    try {
      await this.requestPermissions(['ohos.permission.GET_WIFI_INFO']);
      if (!this.running || joinGeneration !== this.wifiJoinGeneration) {
        return;
      }
      await this.requestPermissions(['ohos.permission.SET_WIFI_INFO']);
      if (!this.running || joinGeneration !== this.wifiJoinGeneration) {
        return;
      }
      try {
        await this.requestPermissions(['ohos.permission.GET_NETWORK_INFO']);
      } catch (error) {
        this.events.onLog(
          `未获 GET_NETWORK_INFO 授权，保留原 Wi-Fi 连接流程：${error instanceof Error ? error.message : String(error)}`
        );
      }
      if (!this.running || joinGeneration !== this.wifiJoinGeneration) {
        return;
      }
      this.events.onStatus(`正在自动连接车机 Wi-Fi：${credentials.ssid}`);
      const result = await this.wifi.connect(
        credentials,
        (message: string): void => this.events.onLog(message)
      );
      if (!this.running || joinGeneration !== this.wifiJoinGeneration) {
        return;
      }
      if (this.iap2 !== iap2 || joinGeneration !== this.wifiJoinGeneration) {
        return;
      }
      await iap2.onWifiConnected();
      if (!this.running || this.iap2 !== iap2 || joinGeneration !== this.wifiJoinGeneration) {
        return;
      }
      this.events.onLog(`正在请求指定 WLAN 网络：${credentials.ssid}`);
      try {
        const handle = await this.wifiNetworkLease.acquire(
          credentials.ssid,
          (message: string): void => {
            void this.handleVehicleWifiLost(message);
          },
          (message: string): void => this.events.onLog(message),
          result.ipAddress
        );
        this.events.onLog(`指定车机 Wi-Fi 网络可用：netId=${handle.netId}`);
      } catch (error) {
        throw new Error(`车机 Wi-Fi 已连接，但无法确认 WLAN 选路：${error instanceof Error ? error.message : String(error)}`);
      }
      if (!this.running || this.iap2 !== iap2 || joinGeneration !== this.wifiJoinGeneration) {
        return;
      }
      this.vehicleWifiConnected = true;
      this.bluetooth.setAdapterHandoffCompleted(true);
      this.clearWifiReconnectTimer();
      this.wifiReconnectAttempts = 0;
      this.lastGatewayFallbackSignature = '';
      this.refreshDiscoveredAirPlay();
      this.events.onStatus(`已连接车机 Wi-Fi：${result.ssid}`);
      this.events.onLog(`车机 Wi-Fi 已连接，本机地址 ${result.ipAddress}`);
      this.startAirPlayDiscovery();
      try {
        await this.startControlAdvertisement(true);
      } catch (error) {
        this.events.onLog(
          `WARN: CarPlay 控制广播不可用，继续通过 mDNS/iAP2 端点连接：` +
            `${error instanceof Error ? error.message : String(error)}`
        );
      }
      if (!this.running || this.iap2 !== iap2 || joinGeneration !== this.wifiJoinGeneration) {
        return;
      }
      this.startAirPlayPrerequisiteWait();
      await this.connectAirPlay();
    } catch (error) {
      if (this.running && this.credentials && !this.vehicleWifiConnected && !this.wifiLostCleanupInProgress) {
        this.scheduleWifiReconnect(`Wi-Fi 加入失败：${error instanceof Error ? error.message : String(error)}`);
      }
      throw error instanceof Error ? error : new Error(String(error));
    } finally {
      if (joinGeneration === this.wifiJoinGeneration) {
        this.wifiJoinInProgress = false;
      }
    }
  }
  private async handleVehicleWifiLost(message: string): Promise<void> {
    if (!this.running || this.wifiLostCleanupInProgress) {
      return;
    }
    this.wifiLostCleanupInProgress = true;
    this.bluetooth.setAdapterHandoffCompleted(false);
    this.wifiJoinGeneration++;
    this.wifiJoinInProgress = false;
    this.clearWifiReconnectTimer();
    this.vehicleWifiConnected = false;
    this.inviteReceived = false;
    this.airPlayStartSessionReceived = false;
    this.airPlayInviteWaitElapsed = false;
    this.airPlayEndpointResolveElapsed = false;
    this.airPlayPairingDeadline = -1;
    this.clearPendingStartSessionTimer();
    this.airPlayConnectAttempted = false;
    this.airPlayConnectInProgress = false;
    const generation = ++this.airPlayGeneration;
    this.clearAirPlayTimers();
    this.discoveredAirPlay = undefined;
    this.mdnsAirPlayService = undefined;
    const pairing = this.activePairing;
    this.activePairing = undefined;
    const discovery = this.discovery;
    this.discovery = undefined;
    const advertiser = this.ctrlAdvertiser;
    this.ctrlAdvertiser = undefined;
    this.events.onStatus('车机 Wi-Fi 中断，正在清理并重连');
    this.events.onLog(`车机 WLAN 丢失：${message}`);
    try {
      if (pairing) {
        try {
          await pairing.stopMediaSession(true);
        } catch (error) {
          this.events.onLog(`Wi-Fi 丢失后停止 AirPlay 媒体失败：${error instanceof Error ? error.message : String(error)}`);
        }
      }
      try {
        await this.stopProjection();
      } catch (error) {
        this.events.onLog(`Wi-Fi 丢失后清理投屏失败：${error instanceof Error ? error.message : String(error)}`);
      }
      if (pairing) {
        try {
          await pairing.close();
        } catch (error) {
          this.events.onLog(`Wi-Fi 丢失后关闭 AirPlay 会话失败：${error instanceof Error ? error.message : String(error)}`);
        }
      }
      try {
        discovery?.stop();
      } catch (error) {
        this.events.onLog(`Wi-Fi 丢失后停止 mDNS 发现失败：${error instanceof Error ? error.message : String(error)}`);
      }
      try {
        await this.stopAirPlayRawMonitor();
      } catch (error) {
        this.events.onLog(`Wi-Fi 丢失后停止 mDNS RAW 监听失败：${error instanceof Error ? error.message : String(error)}`);
      }
      try {
        await advertiser?.stop();
      } catch (error) {
        this.events.onLog(`Wi-Fi 丢失后停止控制广播失败：${error instanceof Error ? error.message : String(error)}`);
      }
      try {
        await this.wifiNetworkLease.release();
      } catch (error) {
        this.events.onLog(`Wi-Fi 丢失后释放旧网络 lease 失败：${error instanceof Error ? error.message : String(error)}`);
      }
    } finally {
      this.wifiLostCleanupInProgress = false;
      if (this.running && generation === this.airPlayGeneration) {
        this.scheduleWifiReconnect('指定车机 WLAN 已丢失');
      }
    }
  }
  private scheduleWifiReconnect(reason: string): void {
    if (!this.running || !this.credentials || this.wifiReconnectTimer >= 0) {
      return;
    }
    if (this.wifiReconnectAttempts >= 5) {
      this.events.onStatus('车机 Wi-Fi 自动重连已暂停，请手动重试');
      this.events.onLog(`车机 Wi-Fi 自动重连达到 5 次上限；最近原因：${reason}`);
      return;
    }
    const attempt = this.wifiReconnectAttempts + 1;
    const delayMs = Math.min(15000, 1000 * (2 ** this.wifiReconnectAttempts));
    this.wifiReconnectAttempts = attempt;
    this.events.onLog(`车机 Wi-Fi ${reason}；${delayMs / 1000} 秒后重连 (${attempt}/5)`);
    this.wifiReconnectTimer = setTimeout((): void => {
      this.wifiReconnectTimer = -1;
      if (!this.running || !this.credentials) {
        return;
      }
      if (this.wifiJoinInProgress) {
        this.scheduleWifiReconnect('等待当前 Wi-Fi 加入流程结束');
        return;
      }
      void this.joinVehicleWifi().catch((error: Error): void => {
        this.events.onLog(`车机 Wi-Fi 自动重连失败：${error.message}`);
      });
    }, delayMs);
  }
}
