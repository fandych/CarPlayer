import bluetoothConnection from '@ohos.bluetooth.connection';
import { isCarPlayAdapterName } from '../transport/BluetoothIap2Server';
import { Iap2SenderSession, WifiCredentials, WirelessAirPlayEndpoint } from './Iap2SenderSession';
import { SessionControllerConnectionFlow } from './SessionControllerConnectionFlow';

export abstract class SessionControllerIap2Flow extends SessionControllerConnectionFlow {
  protected abstract handleIap2AirPlayEndpoint(endpoint: WirelessAirPlayEndpoint | undefined): void;
  protected abstract clearAirPlayWaitTimers(): void;
  protected abstract hasSelfContainedAirPlayEndpoint(): boolean;
  protected abstract startAirPlayPrerequisiteWait(): void;
  protected abstract startAirPlayEndpointResolutionWait(): void;
  protected abstract connectAirPlay(): Promise<void>;

  protected handleBluetoothConnected(): void {
    if (!this.running) {
      this.events.onLog('CarPlay 已关闭，忽略迟到的 Bluetooth RFCOMM 连接');
      this.bluetooth.stop();
      return;
    }
    this.events.onStatus('车机已连接，正在协商 iAP2');
    this.events.onLog('已接受 RFCOMM 连接');
    this.clearPendingStartSessionTimer();
    this.clearAirPlayWaitTimers();
    this.iap2?.cancel();
    this.discoveredAirPlay = undefined;
    this.mdnsAirPlayService = undefined;
    this.iap2AirPlayEndpoint = undefined;
    this.airPlayIdentityConflict = false;
    this.airPlayStartSessionReceived = false;
    this.airPlayInviteWaitElapsed = false;
    this.airPlayEndpointResolveElapsed = false;
    this.airPlayPairingDeadline = -1;
    this.iap2 = new Iap2SenderSession(
      (bytes: Uint8Array): Promise<void> => this.bluetooth.send(bytes),
      (message: string): void => this.events.onLog(message),
      (credentials: WifiCredentials): void => {
        this.clearPendingStartSessionTimer();
        this.credentials = credentials;
        this.events.onWifiCredentials(credentials);
        this.events.onStatus(`iAP2 已收到热点 ${credentials.ssid}，正在自动连接`);
      },
      (endpoint: WirelessAirPlayEndpoint | undefined): void => this.handleIap2AirPlayEndpoint(endpoint),
      this.deviceAddress,
      this.deviceName,
      this.deviceUuid,
      this.allowMfiIntermediateDownload,
      this.trustedMfiFingerprints,
      this.events.requestMfiTrust,
      this.events.persistMfiFingerprint,
      this.skipMfiChallengeVerification,
      this.context,
      (): void => this.handleIap2EndpointPending()
    );
    void this.iap2.start().catch((error: Error): void => this.reportError(error));
  }
  protected handleBluetoothData(bytes: Uint8Array): void {
    if (!this.running || !this.iap2) {
      this.events.onLog('CarPlay 非活动状态，忽略 iAP2 数据');
      return;
    }
    const session = this.iap2;
    void session.receive(bytes).catch((error: Error): void => {
      if (!this.running || this.iap2 !== session) {
        return;
      }
      void this.stop().then((): void => this.reportError(error)).catch((cleanupError: Error): void => {
        this.reportError(`${error.message}；会话清理失败：${cleanupError.message}`);
      });
    });
  }
  protected hasValidDeviceAddress(): boolean {
    return /^(?!02:00:00:00:00:00$)([0-9A-F]{2}:){5}[0-9A-F]{2}$/.test(this.deviceAddress);
  }
  protected detectAdapterMode(): boolean {
    let deviceIds: string[];
    try {
      deviceIds = bluetoothConnection.getPairedDevices();
    } catch (error) {
      this.events.onLog(
        `读取已配对蓝牙设备失败；使用标准 iAP2 SDP：${error instanceof Error ? error.message : String(error)}`
      );
      return false;
    }
    for (const deviceId of deviceIds) {
      try {
        const name = bluetoothConnection.getRemoteDeviceName(deviceId).toLowerCase();
        if (isCarPlayAdapterName(name)) {
          return true;
        }
      } catch (error) {
        this.events.onLog(
          `读取已配对设备名称失败；跳过一个设备：${error instanceof Error ? error.message : String(error)}`
        );
      }
    }
    return false;
  }
  protected handleIap2EndpointPending(): void {
    if (!this.running || this.credentials || this.pendingStartSessionTimer >= 0) {
      return;
    }
    const session = this.iap2;
    this.events.onStatus('等待车机发送无线 CarPlay 端点（0x4301）');
    this.events.onLog('未收到 Wi-Fi 凭据；按 Cardeck 流程保活等待晚到 0x4301，最长 5 分钟');
    this.pendingStartSessionTimer = setTimeout((): void => {
      this.pendingStartSessionTimer = -1;
      if (!this.running || this.iap2 !== session || this.credentials) {
        return;
      }
      this.events.onStatus('等待 0x4301 超时；蓝牙恢复监听，等待车机重连');
      this.events.onLog('等待车机无线端点达到 5 分钟；关闭当前 RFCOMM 会话，保留蓝牙监听');
      this.iap2 = undefined;
      session?.cancel();
      this.bluetooth.disconnectClient();
    }, 5 * 60 * 1000);
  }
  protected clearPendingStartSessionTimer(): void {
    if (this.pendingStartSessionTimer >= 0) {
      clearTimeout(this.pendingStartSessionTimer);
      this.pendingStartSessionTimer = -1;
    }
  }
}
