import abilityAccessCtrl from '@ohos.abilityAccessCtrl';
import { SessionControllerConnectionFlow } from './SessionControllerConnectionFlow';
import common from '@ohos.app.ability.common';
import bluetoothConnection from '@ohos.bluetooth.connection';
import window from '@ohos.window';
import emitter from '@ohos.events.emitter';
import {
  AirPlayPairingClient,
  AirPlayPairingResult,
  AirPlayRtspStatusError,
  supportsAirPlayPairingAndEncryption
} from '../airplay/AirPlayPairingClient';
import { AirPlayMediaSessionInfo, AirPlayMediaSessionStatusError } from '../airplay/AirPlayMediaSession';
import { EncodedH264Event } from '../airplay/AirPlayVideoStream';
import { AudioRtpSender } from '../audio/AudioRtpSender';
import { PlaybackAudioCapture } from '../audio/PlaybackAudioCapture';
import { MfiTrustPromptInfo } from '../iap2/MfiVerifier';
import { AirPlayMdnsDiscovery, AirPlayService } from '../network/AirPlayMdnsDiscovery';
import { correlateAirPlayIdentity } from '../network/AirPlayIdentityCorrelation';
import { CarPlayCtrlAdvertiser } from '../network/CarPlayCtrlAdvertiser';
import { WifiCarPlayConnector } from '../network/WifiCarPlayConnector';
import { WifiNetworkLease } from '../network/WifiNetworkLease';
import { BluetoothIap2Server, isCarPlayAdapterName } from '../transport/BluetoothIap2Server';
import { CarPlayVirtualDisplay } from '../video/CarPlayVirtualDisplay';
import { resolveProjectionRates } from '../video/ProjectionSettings';
import { CarPlayTouchInput, CARPLAY_RECEIVER_HOME_EVENT } from '../video/CarPlayTouchInput';
import { NativeH264ScreenCapture } from '../video/NativeH264ScreenCapture';
import { NativeH264VideoEncoder } from '../video/NativeH264VideoEncoder';
import { advanceSessionGeneration, isCurrentSessionGeneration } from './NativeSessionLifecycle';
import {
  isAirPlayStartReady,
  makeAirPlayServiceFromEndpoint,
  normalizeDeviceIdentifier
} from './airplay/AirPlayEndpointFactory';
import {
  Iap2SenderSession,
  WifiCredentials,
  WirelessAirPlayEndpoint
} from './Iap2SenderSession';
export { SessionEvents } from './SessionControllerConnectionFlow';
export {
  isAirPlayStartReady,
  makeAirPlayServiceFromEndpoint,
  normalizeDeviceIdentifier
} from './airplay/AirPlayEndpointFactory';

export class SessionController extends SessionControllerConnectionFlow {
  async start(): Promise<void> {
    if (this.running) {
      return;
    }
    const generation = advanceSessionGeneration();
    await this.requestPermissions(['ohos.permission.ACCESS_BLUETOOTH']);
    if (!isCurrentSessionGeneration(generation)) {
      this.events.onLog('CarPlayer 已在权限请求期间停止；取消迟到的监听启动');
      return;
    }
    this.running = true;
    this.inviteReceived = false;
    this.wifiJoinInProgress = false;
    this.wifiJoinGeneration++;
    this.airPlayConnectInProgress = false;
    this.airPlayConnectAttempted = false;
    this.airPlayStartSessionReceived = false;
    this.airPlayInviteWaitElapsed = false;
    this.airPlayEndpointResolveElapsed = false;
    this.airPlayPairingDeadline = -1;
    this.vehicleWifiConnected = false;
    this.wifiReconnectAttempts = 0;
    this.clearWifiReconnectTimer();
    this.discoveredAirPlay = undefined;
    this.mdnsAirPlayService = undefined;
    this.iap2AirPlayEndpoint = undefined;
    this.airPlayIdentityConflict = false;
    this.clearAirPlayWaitTimers();
    this.clearPendingStartSessionTimer();
    try {
      if (this.hasValidDeviceAddress()) {
        try {
          await this.startControlAdvertisement();
        } catch (error) {
          this.events.onLog(
            `蓝牙启动前控制广播未能发布；入网后将重试：${error instanceof Error ? error.message : String(error)}`
          );
        }
      } else {
        this.events.onLog('真实蓝牙 MAC 未配置；暂不发布 CarPlay 控制广播');
      }
      this.adapterMode = this.detectAdapterMode();
      this.events.onLog(
        this.adapterMode
          ? '检测到已配对 CarPlay 无线适配器；启用 Wireless iAP SDP 和交接重拨处理'
          : '未检测到已配对 CarPlay 无线适配器；使用标准 iAP2 SDP'
      );
      await this.bluetooth.start(
        () => this.handleBluetoothConnected(),
        (bytes: Uint8Array) => this.handleBluetoothData(bytes),
        (message: string) => this.reportError(message),
        this.adapterMode
      );
      if (!this.running || !isCurrentSessionGeneration(generation)) {
        this.bluetooth.stop();
        this.events.onLog('RFCOMM 启动完成时会话已停止；已立即关闭监听');
        return;
      }
      await this.setKeepScreenOn(true);
      this.events.onStatus('等待车机 iAP2 握手');
      this.events.onLog('CarPlay 已开启：等待蓝牙 RFCOMM / iAP2 连接');
    } catch (error) {
      if (!isCurrentSessionGeneration(generation)) {
        this.bluetooth.stop();
        return;
      }
      this.running = false;
      this.adapterMode = false;
      this.bluetooth.stop();
      const advertiser = this.ctrlAdvertiser;
      this.ctrlAdvertiser = undefined;
      if (advertiser) {
        try {
          await advertiser.stop();
        } catch (cleanupError) {
          this.events.onLog(
            `蓝牙启动失败后的控制广播清理失败：${cleanupError instanceof Error ? cleanupError.message : String(cleanupError)}`
          );
        }
      }
      throw error instanceof Error ? error : new Error(String(error));
    }
  }

  async stop(): Promise<void> {
    advanceSessionGeneration();
    this.running = false;
    this.airPlayGeneration++;
    this.wifiJoinGeneration++;
    this.clearAirPlayTimers();
    this.clearWifiReconnectTimer();
    this.pendingAirPlayDisconnect = '';
    this.airPlayConnectAttempted = false;
    this.airPlayPairingDeadline = -1;
    this.wifiJoinInProgress = false;
    this.vehicleWifiConnected = false;
    this.clearPendingStartSessionTimer();
    const failures: string[] = [];
    try {
      await this.wifi.cancelPendingJoin();
    } catch (error) {
      failures.push(`取消 Wi-Fi 加入失败：${error instanceof Error ? error.message : String(error)}`);
    }
    try {
      await this.stopProjection();
    } catch (error) {
      failures.push(`投屏资源清理失败：${error instanceof Error ? error.message : String(error)}`);
    }
    try {
      this.discovery?.stop();
    } catch (error) {
      failures.push(`mDNS 停止失败：${error instanceof Error ? error.message : String(error)}`);
    }
    this.discovery = undefined;
    try {
      await this.stopAirPlayRawMonitor();
    } catch (error) {
      failures.push(`mDNS RAW 监听停止失败：${error instanceof Error ? error.message : String(error)}`);
    }
    if (this.ctrlAdvertiser) {
      try {
        await this.ctrlAdvertiser.stop();
      } catch (error) {
        failures.push(`控制广播停止失败：${error instanceof Error ? error.message : String(error)}`);
      }
      this.ctrlAdvertiser = undefined;
    }
    this.iap2?.cancel();
    const pairing = this.activePairing;
    this.activePairing = undefined;
    if (pairing) {
      try {
        await pairing.close();
      } catch (error) {
        failures.push(`AirPlay 会话清理失败：${error instanceof Error ? error.message : String(error)}`);
      }
    }
    try {
      await this.wifiNetworkLease.release();
    } catch (error) {
      failures.push(`指定 Wi-Fi 网络监听清理失败：${error instanceof Error ? error.message : String(error)}`);
    }
    try {
      this.bluetooth.stop();
    } catch (error) {
      failures.push(`蓝牙监听停止失败：${error instanceof Error ? error.message : String(error)}`);
    }
    this.iap2 = undefined;
    this.adapterMode = false;
    this.credentials = undefined;
    this.discoveredAirPlay = undefined;
    this.mdnsAirPlayService = undefined;
    this.iap2AirPlayEndpoint = undefined;
    this.airPlayIdentityConflict = false;
    this.inviteReceived = false;
    this.airPlayStartSessionReceived = false;
    this.airPlayInviteWaitElapsed = false;
    this.airPlayEndpointResolveElapsed = false;
    await this.setKeepScreenOn(false);
    this.events.onStatus(failures.length > 0 ? '已停止，但部分资源清理失败' : '已停止');
    this.events.onLog(failures.length > 0 ? `会话停止时出现错误：${failures.join('；')}` : '会话已停止');
    if (failures.length > 0) {
      throw new Error(failures.join('；'));
    }
  }

  async disconnectAirPlay(): Promise<void> {
    this.airPlayGeneration++;
    this.clearAirPlayTimers();
    this.pendingAirPlayDisconnect = '';
    this.airPlayConnectAttempted = false;
    this.airPlayConnectInProgress = false;
    this.inviteReceived = false;
    this.airPlayStartSessionReceived = false;
    this.airPlayInviteWaitElapsed = false;
    this.airPlayEndpointResolveElapsed = false;
    this.airPlayPairingDeadline = -1;
    this.clearAirPlayWaitTimers();
    const pairing = this.activePairing;
    this.activePairing = undefined;
    const failures: string[] = [];
    try {
      await this.stopProjection();
    } catch (error) {
      failures.push(`投屏资源清理失败：${error instanceof Error ? error.message : String(error)}`);
    }
    if (pairing) {
      try {
        await pairing.close();
      } catch (error) {
        failures.push(`AirPlay 会话断开失败：${error instanceof Error ? error.message : String(error)}`);
      }
    }
    const result = failures.length > 0
      ? `AirPlay 已断开，但清理不完整：${failures.join('；')}`
      : 'AirPlay 已断开，iAP2 监听继续运行';
    this.events.onStatus(result);
    this.events.onLog(result);
    if (failures.length > 0) {
      throw new Error(failures.join('；'));
    }
  }

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

  private clearWifiReconnectTimer(): void {
    if (this.wifiReconnectTimer >= 0) {
      clearTimeout(this.wifiReconnectTimer);
      this.wifiReconnectTimer = -1;
    }
  }

  async retryAirPlay(): Promise<void> {
    if (!this.running) {
      throw new Error('CarPlayer 已关闭，不能重试 AirPlay');
    }
    if (this.airPlayConnectInProgress) {
      this.events.onLog('AirPlay 配对或会话建立仍在进行，忽略重复重试');
      return;
    }
    this.clearAirPlayTimers();
    this.pendingAirPlayDisconnect = '';
    this.airPlayReconnectAttempts = 0;
    this.airPlayPairingDeadline = -1;
    const stalePairing = this.activePairing;
    try {
      await this.stopProjection();
    } catch (error) {
      this.events.onLog(`重试前清理本地投屏资源失败：${error instanceof Error ? error.message : String(error)}`);
    }
    this.activePairing = undefined;
    if (stalePairing) {
      try {
        await stalePairing.close();
      } catch (error) {
        this.events.onLog(`重试前关闭旧 AirPlay 会话失败：${error instanceof Error ? error.message : String(error)}`);
      }
    }
    this.airPlayConnectAttempted = false;
    if (!this.vehicleWifiConnected || !this.discoveredAirPlay) {
      this.events.onLog(
        `AirPlay 重试暂不可执行：车机 Wi-Fi${this.vehicleWifiConnected ? '已连接' : '未连接'}，` +
          `mDNS 服务${this.discoveredAirPlay ? '已发现' : '未发现'}`
      );
      return;
    }
    this.airPlayEndpointResolveElapsed = true;
    this.events.onStatus('正在重试 AirPlay 配对和 RTSP 会话');
    await this.connectAirPlay();
  }

  protected async startProjection(
    media: AirPlayMediaSessionInfo,
    pairing: AirPlayPairingClient,
    generation: number
  ): Promise<void> {
    if (!this.isCurrentAirPlaySession(pairing, generation)) {
      return;
    }
    AppStorage.setOrCreate('carplayVehicleDisplayUuid', media.displayUuid);
    AppStorage.setOrCreate('carplayProjectionNativeWidth', media.nativeDisplayWidth);
    AppStorage.setOrCreate('carplayProjectionNativeHeight', media.nativeDisplayHeight);
    AppStorage.setOrCreate('carplayProjectionOutputWidth', media.displayWidth);
    AppStorage.setOrCreate('carplayProjectionOutputHeight', media.displayHeight);
    AppStorage.setOrCreate('carplayProjectionViewAreaX', media.viewArea.originX);
    AppStorage.setOrCreate('carplayProjectionViewAreaY', media.viewArea.originY);
    AppStorage.setOrCreate('carplayProjectionViewAreaWidth', media.viewArea.width);
    AppStorage.setOrCreate('carplayProjectionViewAreaHeight', media.viewArea.height);
    this.events.onLog(
      `显示尺寸计算：DiPlay type=${media.displayType} canvas=${media.nativeDisplayWidth}x${media.nativeDisplayHeight}, ` +
        `H.264=${media.displayWidth}x${media.displayHeight}, ` +
        `activeViewArea=${media.viewArea.width}x${media.viewArea.height}@${media.viewArea.originX},${media.viewArea.originY}`
    );
    AppStorage.setOrCreate('carplayProjectionDisplayModes', media.availableDisplayModes);
    AppStorage.setOrCreate('carplayProjectionActiveModeId', media.displayModeId);
    AppStorage.setOrCreate('carplayProjectionResolutionMessage', media.resolutionMessage);
    const rates = resolveProjectionRates(media.maxFrameRate,
      AppStorage.get<number>('carplayEncoderFps') ?? 30, AppStorage.get<number>('carplayCaptureFps') ?? 60);
    const bitrate = Math.max(1_500_000, Math.min(10_000_000, media.displayWidth * media.displayHeight * 5));
    this.videoFrameCount = 0;
    this.videoCodecConfigCount = 0;
    this.events.onLog(
      `指定屏幕 H.264 采集请求：size=${media.displayWidth}x${media.displayHeight}, ` +
        `fps=${rates.encode}, captureFps=${rates.capture}, bitrate=${bitrate}, format=video/avc`
    );
    let displayId = -1;
    try {
      await this.requestPermissions(['ohos.permission.CUSTOM_SCREEN_CAPTURE']);
      if (!this.isCurrentAirPlaySession(pairing, generation)) {
        return;
      }
      displayId = await this.projectionDisplay.create('', {
        width: media.displayWidth,
        height: media.displayHeight
      }, (message: string): void => this.events.onLog(message));
      if (!this.isCurrentAirPlaySession(pairing, generation)) {
        await this.stopProjection();
        return;
      }
      await this.events.onProjectionReady(displayId, media.displayWidth, media.displayHeight);
      if (!this.isCurrentAirPlaySession(pairing, generation)) {
        await this.stopProjection();
        return;
      }
      if (!this.isCurrentAirPlaySession(pairing, generation)) {
        await this.stopProjection();
        return;
      }
      this.touchInput.start(displayId, media.displayWidth, media.displayHeight);
      pairing.setTouchReportHandler((report: Uint8Array): void => this.touchInput.handleReport(report));
      pairing.setNightModeHandler((night: boolean): void => {
        if (this.isCurrentAirPlaySession(pairing, generation)) {
          AppStorage.setOrCreate('carplayNightMode', night);
        }
      });
      emitter.on(CARPLAY_RECEIVER_HOME_EVENT, this.receiverHomeHandler);
      this.events.onLog('车机触摸事件仅路由至 CarPlayer Shell；Phone 端第三方 APP 输入未验证，保持禁用');
      let videoSendFailed = false;
      const onVideoEvent = (event: EncodedH264Event): void => {
        if (!this.isCurrentAirPlaySession(pairing, generation) || videoSendFailed) {
          return;
        }
        if (event.type === 'diagnostic') {
          this.events.onLog(`AVScreenCapture native 阶段：${event.message ?? 'no detail'}`);
          return;
        }
        if (event.type === 'overflow') {
          this.events.onLog('AVScreenCapture 回调队列过载；停止发送以避免视频不同步');
        }
        const byteLength = event.data?.length ?? 0;
        if (event.type === 'codecConfig') {
          this.videoCodecConfigCount++;
          this.events.onLog(
            `H.264 编码配置回调 #${this.videoCodecConfigCount}：bytes=${byteLength}, ` +
              `pts=${event.timestampUs}, flags=0x${event.flags.toString(16)}`
          );
        } else if (event.type === 'frame') {
          this.videoFrameCount++;
          if (this.videoFrameCount <= 3 || this.videoFrameCount % 120 === 0) {
            this.events.onLog(
              `H.264 输出帧 #${this.videoFrameCount}：bytes=${byteLength}, ` +
                `pts=${event.timestampUs}, flags=0x${event.flags.toString(16)}`
            );
          }
        } else if (event.type === 'error') {
          this.events.onLog(`ERROR: AVScreenCapture 异步错误：${event.message ?? 'no detail'}`);
        }
        void pairing.pushEncodedVideo(event).catch((error: Error): void => {
          if (!this.isCurrentAirPlaySession(pairing, generation) || videoSendFailed) {
            return;
          }
          videoSendFailed = true;
          this.reportError(new Error(`AirPlay H.264 帧发送失败：${error.message}\n${error.stack ?? ''}`));
          void this.stopProjection().catch((cleanupError: Error): void => {
            this.reportError(`H.264 失败后清理投屏资源失败：${cleanupError.message}`);
          });
        });
      };
      this.videoEncoder.start({
        width: media.displayWidth,
        height: media.displayHeight,
        frameRate: rates.encode,
        bitrate
      }, onVideoEvent);
      pairing.setForceKeyFrameHandler((): void => {
        try {
          this.videoEncoder.requestKeyFrame();
        } catch (error) {
          this.events.onLog(`H.264 关键帧请求失败：${error instanceof Error ? error.message : String(error)}`);
        }
      });
      this.videoCapture.start({
        displayId,
        width: media.displayWidth,
        height: media.displayHeight,
        frameRate: rates.capture,
        bitrate,
        encoderHandle: this.videoEncoder.handle
      }, onVideoEvent);
      AppStorage.setOrCreate('carplayActiveEncoderFps', rates.encode);
      AppStorage.setOrCreate('carplayActiveCaptureFps', rates.capture);
      this.events.onLog(`指定屏幕 H.264 采集已启动：displayId=${displayId}`);
      this.events.onLog(
        `CarPlay 虚拟屏编码输出已建立：id=${displayId}, ${media.displayWidth}x${media.displayHeight}, ` +
          `${rates.encode}fps, capture=${rates.capture}fps`
      );
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      this.events.onLog(`ERROR: 投影启动流程失败：displayId=${displayId}, error=${message}`);
      const failures: string[] = [];
      this.touchInput.stop();
      pairing.setTouchReportHandler(undefined);
      try {
        this.videoCapture.stop();
      } catch (cleanupError) {
        failures.push(cleanupError instanceof Error ? cleanupError.message : String(cleanupError));
      }
      try {
        this.videoEncoder.stop();
      } catch (cleanupError) {
        failures.push(cleanupError instanceof Error ? cleanupError.message : String(cleanupError));
      }
      try {
        await this.projectionDisplay.destroy();
      } catch (cleanupError) {
        failures.push(cleanupError instanceof Error ? cleanupError.message : String(cleanupError));
      }
      pairing.setForceKeyFrameHandler(undefined);
      if (failures.length > 0) {
        throw new Error(`${message}; cleanup failed: ${failures.join('; ')}`);
      }
      throw error instanceof Error ? error : new Error(message);
    }
  }

  protected async stopProjection(): Promise<void> {
    const displayId = this.projectionDisplay.id;
    const failures: string[] = [];
    if (displayId >= 0 && this.events.onProjectionStopping) {
      try {
        await this.events.onProjectionStopping();
      } catch (error) {
        this.events.onLog(`离车时暂停音乐失败：${error instanceof Error ? error.message : String(error)}`);
      }
    }
    this.touchInput.stop();
    emitter.off(CARPLAY_RECEIVER_HOME_EVENT, this.receiverHomeHandler);
    this.activePairing?.setTouchReportHandler(undefined);
    const audioCapture = this.playbackAudioCapture;
    this.playbackAudioCapture = undefined;
    if (audioCapture) {
      try {
        await audioCapture.stop();
      } catch (error) {
        failures.push(`播放音频采集：${error instanceof Error ? error.message : String(error)}`);
      }
    }
    const audioSender = this.audioRtpSender;
    this.audioRtpSender = undefined;
    if (audioSender) {
      try {
        await audioSender.stop();
      } catch (error) {
        failures.push(`音频 RTP sender：${error instanceof Error ? error.message : String(error)}`);
      }
    }
    try {
      this.videoCapture.stop();
    } catch (error) {
      failures.push(`H.264 屏幕采集：${error instanceof Error ? error.message : String(error)}`);
    }
    try {
      this.videoEncoder.stop();
    } catch (error) {
      failures.push(`H.264 编码器：${error instanceof Error ? error.message : String(error)}`);
    }
    try {
      await this.projectionDisplay.destroy();
    } catch (error) {
      failures.push(error instanceof Error ? error.message : String(error));
    }
    this.activePairing?.setForceKeyFrameHandler(undefined);
    if (displayId >= 0) {
      this.events.onProjectionStopped();
      this.events.onLog(`CarPlay 虚拟屏已停止：id=${displayId}`);
    }
    if (failures.length > 0) {
      throw new Error(failures.join('; '));
    }
  }

  protected async startAudio(media: AirPlayMediaSessionInfo, generation: number): Promise<void> {
    if (!this.running || generation !== this.airPlayGeneration) {
      return;
    }
    if (AppStorage.get<boolean>('carplayUseBluetoothAudio') === true) {
      this.events.onLog('音频方式：蓝牙 A2DP；不启动内录及 RTP 推流，音频输出跟随系统路由');
      return;
    }
    const audioSession = media.audioSession;
    if (!audioSession) {
      this.events.onLog('AirPlay 未协商到 PCM media audio stream；音频推流保持关闭');
      return;
    }
    this.events.onLog('音频方式：CarPlay RTP；准备启动播放音频内录及推流');
    const sender = new AudioRtpSender(
      (message: string): void => this.events.onLog(message),
      (message: string): void => this.events.onLog(message),
      this.wifiNetworkLease
    );
    let capture: PlaybackAudioCapture | undefined;
    try {
      await sender.start(audioSession);
      if (!this.running || generation !== this.airPlayGeneration) {
        await sender.stop();
        return;
      }
      this.audioRtpSender = sender;
      capture = new PlaybackAudioCapture(
        (pcm: Uint8Array): void => {
          try {
            sender.pushPcm(pcm);
          } catch (error) {
            this.events.onLog(`播放音频 PCM 推送失败：${error instanceof Error ? error.message : String(error)}`);
          }
        },
        (status: string): void => this.events.onLog(status),
        audioSession.sampleRate
      );
      this.playbackAudioCapture = capture;
      await capture.requestStart();
      if (!this.running || generation !== this.airPlayGeneration) {
        await capture.stop();
        await sender.stop();
      }
    } catch (error) {
      this.events.onLog(`AirPlay 音频推流不可用，视频会话继续：${error instanceof Error ? error.message : String(error)}`);
      if (capture) {
        try {
          await capture.stop();
        } catch (cleanupError) {
          this.events.onLog(`音频采集清理失败：${cleanupError instanceof Error ? cleanupError.message : String(cleanupError)}`);
        }
      }
      if (this.playbackAudioCapture === capture) {
        this.playbackAudioCapture = undefined;
      }
      try {
        await sender.stop();
      } catch (cleanupError) {
        this.events.onLog(`音频 RTP 清理失败：${cleanupError instanceof Error ? cleanupError.message : String(cleanupError)}`);
      }
      if (this.audioRtpSender === sender) {
        this.audioRtpSender = undefined;
      }
    }
  }

  protected reportError(error: Error | string): void {
    const message = error instanceof Error ? error.message : error;
    const stack = error instanceof Error && error.stack && error.stack !== message
      ? `\n${error.stack}`
      : '';
    this.events.onStatus(`错误：${message}`);
    this.events.onLog(`错误：${message}${stack}`);
  }

  private async setKeepScreenOn(keepScreenOn: boolean): Promise<void> {
    if (!this.keepScreenOn) {
      return;
    }
    try {
      const appWindow = await window.getLastWindow(this.context);
      await appWindow.setWindowKeepScreenOn(keepScreenOn);
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      this.events.onLog(`常亮设置失败：${message}`);
    }
  }
}
