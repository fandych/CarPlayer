import abilityAccessCtrl from '@ohos.abilityAccessCtrl';
import common from '@ohos.app.ability.common';
import window from '@ohos.window';
import emitter from '@ohos.events.emitter';
import { AirPlayPairingClient, AirPlayRtspStatusError } from '../airplay/AirPlayPairingClient';
import { AirPlayMediaSessionInfo } from '../airplay/AirPlayMediaSession';
import { EncodedH264Event } from '../airplay/AirPlayVideoStream';
import { AudioRtpSender } from '../audio/AudioRtpSender';
import { PlaybackAudioCapture } from '../audio/PlaybackAudioCapture';
import { MfiTrustPromptInfo } from '../iap2/MfiVerifier';
import { AirPlayMdnsDiscovery, AirPlayService } from '../network/AirPlayMdnsDiscovery';
import { correlateAirPlayIdentity } from '../network/AirPlayIdentityCorrelation';
import { CarPlayCtrlAdvertiser } from '../network/CarPlayCtrlAdvertiser';
import { WifiCarPlayConnector } from '../network/WifiCarPlayConnector';
import { WifiNetworkLease } from '../network/WifiNetworkLease';
import { BluetoothIap2Server } from '../transport/BluetoothIap2Server';
import { CarPlayVirtualDisplay } from '../video/CarPlayVirtualDisplay';
import { resolveProjectionRates } from '../video/ProjectionSettings';
import { CarPlayTouchInput, CARPLAY_RECEIVER_HOME_EVENT } from '../video/CarPlayTouchInput';
import { NativeH264ScreenCapture } from '../video/NativeH264ScreenCapture';
import { NativeH264VideoEncoder } from '../video/NativeH264VideoEncoder';
import { advanceSessionGeneration, isCurrentSessionGeneration } from './NativeSessionLifecycle';
import {
  Iap2SenderSession,
  WifiCredentials,
  WirelessAirPlayEndpoint
} from './Iap2SenderSession';

export interface SessionEvents {
  onStatus: (status: string) => void;
  onLog: (message: string) => void;
  onWifiCredentials: (credentials: WifiCredentials) => void;
  onAirPlayService: (service: AirPlayService) => void;
  onAirPlayMediaSession: (info: AirPlayMediaSessionInfo) => void;
  onProjectionReady: (displayId: number, width: number, height: number) => Promise<void>;
  onProjectionStopping?: () => Promise<void>;
  onProjectionStopped: () => void;
  requestMfiTrust: (info: MfiTrustPromptInfo) => Promise<boolean>;
  persistMfiFingerprint: (fingerprint: string) => Promise<void>;
}

const AIRPLAY_CTRL_INVITE_WAIT_MS: number = 4000;
const AIRPLAY_ENDPOINT_RESOLVE_WAIT_MS: number = 3000;
const AIRPLAY_PAIRING_WINDOW_MS: number = 120000;

export function isAirPlayStartReady(
  networkReady: boolean,
  invited: boolean,
  hasCompleteEndpoint: boolean,
  hasMdnsService: boolean = false,
  endpointResolutionComplete: boolean = false
): boolean {
  return networkReady && (invited || hasCompleteEndpoint || hasMdnsService || endpointResolutionComplete);
}

export class SessionController {
  private readonly context: common.UIAbilityContext;
  private readonly events: SessionEvents;
  private readonly bluetooth: BluetoothIap2Server = new BluetoothIap2Server();
  private readonly wifi: WifiCarPlayConnector = new WifiCarPlayConnector();
  private readonly wifiNetworkLease: WifiNetworkLease = new WifiNetworkLease();
  private readonly projectionDisplay: CarPlayVirtualDisplay = new CarPlayVirtualDisplay();
  private readonly touchInput: CarPlayTouchInput = new CarPlayTouchInput();
  private readonly videoCapture: NativeH264ScreenCapture = new NativeH264ScreenCapture();
  private readonly videoEncoder: NativeH264VideoEncoder = new NativeH264VideoEncoder();
  private audioRtpSender?: AudioRtpSender;
  private playbackAudioCapture?: PlaybackAudioCapture;
  private discovery?: AirPlayMdnsDiscovery;
  private ctrlAdvertiser?: CarPlayCtrlAdvertiser;
  private activePairing?: AirPlayPairingClient;
  private discoveredAirPlay?: AirPlayService;
  private mdnsAirPlayService?: AirPlayService;
  private iap2AirPlayEndpoint?: WirelessAirPlayEndpoint;
  private airPlayIdentityConflict: boolean = false;
  private iap2?: Iap2SenderSession;
  private credentials?: WifiCredentials;
  private running: boolean = false;
  private inviteReceived: boolean = false;
  private airPlayStartSessionReceived: boolean = false;
  private airPlayInviteWaitElapsed: boolean = false;
  private airPlayEndpointResolveElapsed: boolean = false;
  private vehicleWifiConnected: boolean = false;
  private wifiJoinInProgress: boolean = false;
  private wifiJoinGeneration: number = 0;
  private airPlayConnectInProgress: boolean = false;
  private airPlayConnectAttempted: boolean = false;
  private airPlayGeneration: number = 0;
  private airPlayReconnectTimer: number = -1;
  private airPlayStableTimer: number = -1;
  private airPlayInviteWaitTimer: number = -1;
  private airPlayEndpointResolveTimer: number = -1;
  private pendingStartSessionTimer: number = -1;
  private airPlayReconnectAttempts: number = 0;
  private airPlayPairingDeadline: number = -1;
  private wifiReconnectTimer: number = -1;
  private wifiReconnectAttempts: number = 0;
  private wifiLostCleanupInProgress: boolean = false;
  private lastGatewayFallbackSignature: string = '';
  private pendingAirPlayDisconnect: string = '';
  private readonly deviceAddress: string;
  private readonly deviceName: string;
  private readonly deviceUuid: string;
  private readonly keepScreenOn: boolean;
  private readonly allowMfiIntermediateDownload: boolean;
  private readonly trustedMfiFingerprints: string[];
  private readonly skipMfiChallengeVerification: boolean;
  private videoFrameCount: number = 0;
  private videoCodecConfigCount: number = 0;
  private readonly receiverHomeHandler = (): void => {
    const pairing = this.activePairing;
    if (!pairing) {
      return;
    }
    void pairing.requestReceiverHome().then((): void => {
      AppStorage.setOrCreate('carplayReceiverHomeMessage', '已发送车机界面切换请求');
    }).catch((error: Error): void => {
      this.events.onLog(`车机主页切换失败：${error.message}`);
      AppStorage.setOrCreate('carplayReceiverHomeMessage', error.message);
    });
  };

  constructor(
    context: common.UIAbilityContext,
    events: SessionEvents,
    deviceAddress: string,
    deviceName: string,
    deviceUuid: string,
    keepScreenOn: boolean,
    allowMfiIntermediateDownload: boolean = false,
    trustedMfiFingerprints: string[] = [],
    skipMfiChallengeVerification: boolean = false
  ) {
    this.context = context;
    this.events = events;
    this.deviceAddress = deviceAddress;
    this.deviceName = deviceName;
    this.deviceUuid = deviceUuid;
    this.keepScreenOn = keepScreenOn;
    this.allowMfiIntermediateDownload = allowMfiIntermediateDownload;
    this.trustedMfiFingerprints = trustedMfiFingerprints.slice();
    this.skipMfiChallengeVerification = skipMfiChallengeVerification;
  }

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
      await this.bluetooth.start(
        () => this.handleBluetoothConnected(),
        (bytes: Uint8Array) => this.handleBluetoothData(bytes),
        (message: string) => this.reportError(message)
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
      this.clearWifiReconnectTimer();
      this.wifiReconnectAttempts = 0;
      this.lastGatewayFallbackSignature = '';
      this.refreshDiscoveredAirPlay();
      this.events.onStatus(`已连接车机 Wi-Fi：${result.ssid}`);
      this.events.onLog(`车机 Wi-Fi 已连接，本机地址 ${result.ipAddress}`);
      this.startAirPlayDiscovery();
      await this.startControlAdvertisement();
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

  private async requestPermissions(permissions: Array<
    'ohos.permission.ACCESS_BLUETOOTH' | 'ohos.permission.SET_WIFI_INFO' | 'ohos.permission.GET_WIFI_INFO' |
    'ohos.permission.GET_NETWORK_INFO' | 'ohos.permission.CUSTOM_SCREEN_CAPTURE'
  >): Promise<void> {
    const manager = abilityAccessCtrl.createAtManager();
    await new Promise<void>((resolve, reject) => {
      manager.requestPermissionsFromUser(this.context, permissions, (error, result) => {
        if (error) {
          reject(new Error(`权限请求失败 (${error.code}): ${error.message}`));
          return;
        }
        const denied: string[] = [];
        for (let index = 0; index < result.permissions.length; index++) {
          if (result.authResults[index] !== 0) {
            denied.push(result.permissions[index]);
          }
        }
        if (denied.length > 0) {
          reject(new Error(`未获授权：${denied.join('、')}。请在系统设置中授予后重试`));
          return;
        }
        resolve();
      });
    });
  }

  private handleBluetoothConnected(): void {
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

  private handleBluetoothData(bytes: Uint8Array): void {
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

  private startAirPlayDiscovery(): void {
    if (this.discovery) {
      this.discovery.stop();
    }
    this.discovery = new AirPlayMdnsDiscovery(
      this.context,
      (service: AirPlayService): void => {
        this.mdnsAirPlayService = service;
        this.refreshDiscoveredAirPlay();
        this.events.onAirPlayService(service);
        this.events.onLog(`发现 AirPlay ${service.name} · ${service.host}:${service.port}`);
        this.clearAirPlayWaitTimers();
        void this.connectAirPlay().catch((error: Error): void => this.reportError(error));
      },
      (message: string): void => this.events.onLog(message)
    );
    this.discovery.start();
    this.events.onLog('正在发现 _airplay._tcp 服务');
  }

  private handleIap2AirPlayEndpoint(endpoint: WirelessAirPlayEndpoint | undefined): void {
    if (!this.running || this.airPlayIdentityConflict) {
      return;
    }
    this.airPlayStartSessionReceived = true;
    this.clearPendingStartSessionTimer();
    if (endpoint) {
      this.iap2AirPlayEndpoint = endpoint;
      this.events.onLog(
        `已从 iAP2 0x4301 获得 AirPlay 地址候选：${endpoint.addresses.length} 个地址，port=${endpoint.port}`
      );
      if (!endpoint.publicKey) {
        this.events.onLog('0x4301 未携带可识别的公钥；仅保留地址候选，身份仍须通过配对验证');
      }
    } else {
      this.events.onLog('已收到 0x4301 启动请求，等待 mDNS 提供 AirPlay endpoint');
    }
    this.refreshDiscoveredAirPlay();
    if (this.discoveredAirPlay) {
      this.events.onAirPlayService(this.discoveredAirPlay);
    }
    this.startAirPlayPrerequisiteWait();
    void this.connectAirPlay().catch((error: Error): void => this.reportError(error));
  }

  private refreshDiscoveredAirPlay(): void {
    if (this.airPlayIdentityConflict) {
      this.discoveredAirPlay = undefined;
      return;
    }
    const endpoint = this.iap2AirPlayEndpoint;
    const mdnsService = this.mdnsAirPlayService;
    if (!endpoint) {
      this.discoveredAirPlay = mdnsService ?? this.makeAirPlayGatewayFallback();
      return;
    }

    const endpointService = endpoint.publicKey ? makeAirPlayServiceFromEndpoint(endpoint) : undefined;
    if (!mdnsService) {
      this.discoveredAirPlay = endpointService ?? this.makeAirPlayGatewayFallback(endpoint);
      return;
    }

    const identityRelation = correlateAirPlayIdentity(
      mdnsService.txt['deviceid'] ?? '',
      mdnsService.txt['pk'] ?? '',
      endpoint.deviceIdentifier,
      endpoint.publicKey
    );
    if (identityRelation === 'conflict') {
      this.rejectAirPlayIdentityConflict(
        '同一 AirPlay deviceIdentifier 的 mDNS pk 与 iAP2 0x4301 publicKey 不一致'
      );
      return;
    }
    if (identityRelation === 'different-device') {
      this.events.onLog('忽略与当前 0x4301 endpoint 身份不匹配的 mDNS AirPlay 服务');
      this.discoveredAirPlay = endpointService;
      return;
    }
    if (identityRelation === 'unlinked') {
      this.events.onLog('mDNS AirPlay 服务无法与 iAP2 endpoint 建立身份关联；使用 0x4301 地址');
      this.discoveredAirPlay = endpointService;
      return;
    }
    if (!endpoint.publicKey && !/^(?:0x)?[0-9a-fA-F]{64}$/.test(mdnsService.txt['pk'] ?? '')) {
      this.events.onLog('AirPlay 地址已发现，但仍缺少有效的接收端公钥；继续等待 mDNS');
      this.discoveredAirPlay = undefined;
      return;
    }
    if (identityRelation === 'public-key-match' &&
      normalizeDeviceIdentifier(mdnsService.txt['deviceid'] ?? '') !==
        normalizeDeviceIdentifier(endpoint.deviceIdentifier)) {
      this.events.onLog(
        'mDNS deviceid 与 iAP2 deviceIdentifier 不同，但 publicKey 一致；按公钥确认 AirPlay 接收端'
      );
    }

    const addresses = mdnsService.port === endpoint.port
      ? [mdnsService.host].concat(endpoint.addresses)
      : [mdnsService.host];
    const uniqueAddresses: string[] = [];
    for (const address of addresses) {
      if (uniqueAddresses.indexOf(address) < 0) {
        uniqueAddresses.push(address);
      }
    }
    const txt: Record<string, string> = {};
    for (const key of Object.keys(mdnsService.txt)) {
      const value = mdnsService.txt[key];
      if (value !== undefined) {
        txt[key] = value;
      }
    }
    if (!txt['deviceid']) {
      txt['deviceid'] = endpoint.deviceIdentifier;
    }
    if (!txt['pk'] && endpoint.publicKey) {
      txt['pk'] = endpoint.publicKey;
    }
    this.discoveredAirPlay = {
      name: mdnsService.name,
      host: mdnsService.host,
      addresses: uniqueAddresses,
      port: mdnsService.port,
      txt
    };
  }

  private makeAirPlayGatewayFallback(endpoint?: WirelessAirPlayEndpoint): AirPlayService | undefined {
    const gateway = this.wifiNetworkLease.defaultGatewayAddress;
    if (!gateway) {
      return undefined;
    }
    const port = endpoint?.port || 7000;
    if (port < 1 || port > 65535) {
      return undefined;
    }
    const txt: Record<string, string> = {};
    if (endpoint?.deviceIdentifier) {
      txt['deviceid'] = endpoint.deviceIdentifier;
    }
    if (endpoint?.publicKey && /^(?:0x)?[0-9a-fA-F]{64}$/.test(endpoint.publicKey)) {
      txt['pk'] = endpoint.publicKey;
    }
    const signature = `${gateway}:${port}:${txt['deviceid'] ?? ''}:${txt['pk'] ?? ''}`;
    if (signature !== this.lastGatewayFallbackSignature) {
      this.lastGatewayFallbackSignature = signature;
      this.events.onLog(
        `mDNS AirPlay 服务尚未出现；尝试已选车机 WLAN gateway ${gateway}:${port}，` +
          `receiver 公钥${txt['pk'] ? '已知' : '未知，不伪造'}`
      );
    }
    return { name: 'CarPlay gateway fallback', host: gateway, addresses: [gateway], port, txt };
  }

  private rejectAirPlayIdentityConflict(reason: string): void {
    this.airPlayIdentityConflict = true;
    this.discoveredAirPlay = undefined;
    this.inviteReceived = false;
    this.airPlayStartSessionReceived = false;
    this.airPlayInviteWaitElapsed = false;
    this.airPlayEndpointResolveElapsed = false;
    this.airPlayPairingDeadline = -1;
    this.airPlayConnectAttempted = true;
    this.airPlayConnectInProgress = false;
    this.airPlayGeneration++;
    this.clearAirPlayTimers();
    const pairing = this.activePairing;
    this.activePairing = undefined;
    void this.stopProjection().catch((error: Error): void => {
      this.events.onLog(`身份冲突后清理 AirPlay 媒体资源失败：${error.message}`);
    });
    if (pairing) {
      void pairing.close().catch((error: Error): void => {
        this.events.onLog(`身份冲突后关闭 AirPlay 会话失败：${error.message}`);
      });
    }
    this.events.onStatus('AirPlay 身份信息冲突，已拒绝配对');
    this.events.onLog(`ERROR: ${reason}；已拒绝继续 Pair-Setup/Pair-Verify`);
  }

  private async startControlAdvertisement(): Promise<void> {
    if (!this.hasValidDeviceAddress()) {
      this.events.onLog('真实蓝牙 MAC 未配置；跳过 CarPlay 控制广播');
      return;
    }
    if (this.ctrlAdvertiser) {
      await this.ctrlAdvertiser.stop();
    }
    const advertiser = new CarPlayCtrlAdvertiser(
      this.context,
      this.deviceAddress,
      (): void => {
        this.inviteReceived = true;
        this.clearAirPlayInviteWaitTimer();
        this.events.onStatus('收到车机邀请，等待 AirPlay 接收端');
        this.startAirPlayEndpointResolutionWait();
        if (this.discoveredAirPlay) {
          void this.connectAirPlay().catch((error: Error): void => this.reportError(error));
        }
      },
      (message: string): void => this.events.onLog(message)
    );
    this.ctrlAdvertiser = advertiser;
    await advertiser.start();
    this.startAirPlayPrerequisiteWait();
    if (this.inviteReceived && this.discoveredAirPlay) {
      void this.connectAirPlay().catch((error: Error): void => this.reportError(error));
    }
  }

  private hasSelfContainedAirPlayEndpoint(): boolean {
    const endpoint = this.iap2AirPlayEndpoint;
    return endpoint !== undefined && endpoint.port > 0 &&
      endpoint.addresses.some((address: string): boolean => address.trim().length > 0);
  }

  private hasAirPlayStartSignal(): boolean {
    return this.inviteReceived || this.airPlayStartSessionReceived ||
      this.mdnsAirPlayService !== undefined || this.airPlayEndpointResolveElapsed;
  }

  private startAirPlayPrerequisiteWait(): void {
    if (!this.running || !this.vehicleWifiConnected) {
      return;
    }
    if (this.hasSelfContainedAirPlayEndpoint() || this.mdnsAirPlayService) {
      this.clearAirPlayWaitTimers();
      void this.connectAirPlay().catch((error: Error): void => this.reportError(error));
      return;
    }
    if (this.inviteReceived || this.airPlayInviteWaitElapsed) {
      this.clearAirPlayInviteWaitTimer();
      this.startAirPlayEndpointResolutionWait();
      return;
    }
    if (this.airPlayInviteWaitTimer >= 0) {
      return;
    }
    this.airPlayInviteWaitTimer = setTimeout((): void => {
      this.airPlayInviteWaitTimer = -1;
      if (!this.running || !this.vehicleWifiConnected || this.mdnsAirPlayService ||
        this.hasSelfContainedAirPlayEndpoint()) {
        return;
      }
      this.airPlayInviteWaitElapsed = true;
      this.events.onLog('等待 CarPlay ctrl 邀请达到 4 秒；继续等待 AirPlay mDNS/端点解析');
      this.startAirPlayEndpointResolutionWait();
    }, AIRPLAY_CTRL_INVITE_WAIT_MS);
  }

  private startAirPlayEndpointResolutionWait(): void {
    if (!this.running || !this.vehicleWifiConnected) {
      return;
    }
    if (this.mdnsAirPlayService || this.hasSelfContainedAirPlayEndpoint()) {
      this.clearAirPlayWaitTimers();
      void this.connectAirPlay().catch((error: Error): void => this.reportError(error));
      return;
    }
    if (this.airPlayEndpointResolveTimer >= 0) {
      return;
    }
    this.airPlayEndpointResolveTimer = setTimeout((): void => {
      this.airPlayEndpointResolveTimer = -1;
      if (!this.running || !this.vehicleWifiConnected || this.mdnsAirPlayService ||
        this.hasSelfContainedAirPlayEndpoint()) {
        return;
      }
      this.airPlayEndpointResolveElapsed = true;
      this.refreshDiscoveredAirPlay();
      this.events.onLog('AirPlay mDNS 端点等待达到 3 秒；尝试已选车机网络的网关回退');
      void this.connectAirPlay().catch((error: Error): void => this.reportError(error));
    }, AIRPLAY_ENDPOINT_RESOLVE_WAIT_MS);
  }

  private clearAirPlayInviteWaitTimer(): void {
    if (this.airPlayInviteWaitTimer >= 0) {
      clearTimeout(this.airPlayInviteWaitTimer);
      this.airPlayInviteWaitTimer = -1;
    }
  }

  private clearAirPlayEndpointResolveTimer(): void {
    if (this.airPlayEndpointResolveTimer >= 0) {
      clearTimeout(this.airPlayEndpointResolveTimer);
      this.airPlayEndpointResolveTimer = -1;
    }
  }

  private clearAirPlayWaitTimers(): void {
    this.clearAirPlayInviteWaitTimer();
    this.clearAirPlayEndpointResolveTimer();
  }

  private hasValidDeviceAddress(): boolean {
    return /^(?!02:00:00:00:00:00$)([0-9A-F]{2}:){5}[0-9A-F]{2}$/.test(this.deviceAddress);
  }

  private handleIap2EndpointPending(): void {
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

  private clearPendingStartSessionTimer(): void {
    if (this.pendingStartSessionTimer >= 0) {
      clearTimeout(this.pendingStartSessionTimer);
      this.pendingStartSessionTimer = -1;
    }
  }

  private async connectAirPlay(): Promise<void> {
    const service = this.discoveredAirPlay;
    if (this.airPlayIdentityConflict) {
      this.events.onLog('AirPlay mDNS 与 iAP2 endpoint 身份冲突；拒绝连接');
      return;
    }
    if (!this.running || !service || !isAirPlayStartReady(
      this.vehicleWifiConnected,
      this.hasSelfContainedAirPlayEndpoint(),
      this.mdnsAirPlayService !== undefined,
      this.airPlayEndpointResolveElapsed
    ) || this.airPlayConnectInProgress ||
      this.airPlayConnectAttempted) {
      return;
    }
    if (!/^(?:0x)?[0-9a-fA-F]{64}$/.test(service.txt['pk'] ?? '')) {
      this.events.onStatus('AirPlay 接收端缺少有效公钥；为保持配对验证，不启动未认证会话');
      this.events.onLog('AirPlay mDNS/0x4301 endpoint 没有有效公钥；等待可验证的接收端身份');
      return;
    }
    this.clearAirPlayWaitTimers();
    if (this.airPlayPairingDeadline < 0) {
      this.airPlayPairingDeadline = Date.now() + AIRPLAY_PAIRING_WINDOW_MS;
    }
    this.airPlayConnectInProgress = true;
    this.airPlayConnectAttempted = true;
    this.pendingAirPlayDisconnect = '';
    const generation = ++this.airPlayGeneration;
    const pairing = new AirPlayPairingClient(
      (message: string): void => this.events.onLog(message),
      (message: string): void => this.handleAirPlayTransportDisconnect(generation, message),
      this.wifiNetworkLease
    );
    this.activePairing = pairing;
    try {
      this.events.onStatus('车机邀请和 AirPlay 服务已就绪，正在安全配对');
      this.events.onLog(`开始 AirPlay Pair-Setup/Verify：${service.host}:${service.port}`);
      const result = await pairing.pair(this.context, service);
      if (!this.running || generation !== this.airPlayGeneration) {
        await pairing.close();
        return;
      }
      this.events.onLog(`AirPlay 配对验证通过：${result.receiverId} · ${result.model}`);
      this.events.onStatus('AirPlay 配对通过，正在建立 RTSP 会话');
      const media = await pairing.startCarPlaySession(this.deviceAddress);
      if (!this.running || generation !== this.airPlayGeneration) {
        await pairing.close();
        return;
      }
      this.events.onAirPlayMediaSession(media);
      this.events.onLog(
        `AirPlay RTSP RECORD 已完成：screen=${media.videoDataPort}, audio=${media.audioSession?.dataPort ?? 0}`
      );
      try {
        await this.startProjection(media, pairing, generation);
        if (!this.running || generation !== this.airPlayGeneration) {
          return;
        }
        this.events.onStatus(`CarPlay 实时投屏已启动：${media.displayWidth}x${media.displayHeight}`);
      } catch (error) {
        const message = error instanceof Error ? error.message : String(error);
        this.events.onStatus(`AirPlay 控制已连接；投屏不可用：${message}`);
        this.events.onLog(`CarPlay 视频源未能启动：${message}`);
      }
      if (this.pendingAirPlayDisconnect) {
        return;
      }
      await this.startAudio(media, generation);
      this.airPlayPairingDeadline = -1;
      this.scheduleAirPlayStableReset(generation);
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      if (!this.running || generation !== this.airPlayGeneration) {
        try {
          await pairing.close();
        } catch (cleanupError) {
          this.events.onLog(`停止期间清理 AirPlay 会话失败：${cleanupError instanceof Error ?
            cleanupError.message : String(cleanupError)}`);
        }
        return;
      }
      this.events.onStatus(`AirPlay 连接失败：${message}`);
      this.events.onLog(`AirPlay 自动连接失败：${message}`);
      try {
        await pairing.close();
      } catch (cleanupError) {
        this.events.onLog(`AirPlay 失败清理异常：${cleanupError instanceof Error ?
          cleanupError.message : String(cleanupError)}`);
      }
      this.activePairing = undefined;
      if (error instanceof AirPlayRtspStatusError &&
        [404, 405, 455, 501].includes(error.statusCode)) {
        this.airPlayPairingDeadline = -1;
        this.events.onStatus('AirPlay 接收端不支持当前配对接口；未降级到明文会话');
        this.events.onLog(`AirPlay Pair-Setup 返回 ${error.statusCode}；保留认证要求，停止自动重试`);
      } else {
        this.scheduleAirPlayReconnect(`连接失败：${message}`);
      }
    } finally {
      if (generation === this.airPlayGeneration) {
        this.airPlayConnectInProgress = false;
        const disconnect = this.pendingAirPlayDisconnect;
        this.pendingAirPlayDisconnect = '';
        if (disconnect) {
          this.handleAirPlayTransportDisconnect(generation, disconnect);
        }
      }
    }
  }

  private handleAirPlayTransportDisconnect(generation: number, message: string): void {
    if (!this.running || generation !== this.airPlayGeneration) {
      return;
    }
    if (this.airPlayConnectInProgress) {
      this.pendingAirPlayDisconnect = message;
      void this.playbackAudioCapture?.stop().catch((error: Error): void => {
        this.events.onLog(`断连时取消音频授权失败：${error.message}`);
      });
      return;
    }
    const pairing = this.activePairing;
    if (!pairing) {
      return;
    }
    this.clearAirPlayStableTimer();
    const recoveryGeneration = ++this.airPlayGeneration;
    this.airPlayConnectInProgress = true;
    this.airPlayConnectAttempted = false;
    this.events.onStatus('AirPlay 连接中断，正在清理并准备重连');
    this.events.onLog(`检测到 AirPlay RTSP 断连：${message}`);
    void (async (): Promise<void> => {
      try {
        await pairing.stopMediaSession(true);
      } catch (error) {
        this.events.onLog(`断连后停止 AirPlay 媒体会话失败：${error instanceof Error ? error.message : String(error)}`);
      }
      try {
        await this.stopProjection();
      } catch (error) {
        this.events.onLog(`断连后清理投屏资源失败：${error instanceof Error ? error.message : String(error)}`);
      }
      if (this.activePairing === pairing) {
        this.activePairing = undefined;
      }
      try {
        await pairing.close();
      } catch (error) {
        this.events.onLog(`断连后关闭旧 AirPlay 会话失败：${error instanceof Error ? error.message : String(error)}`);
      }
      if (!this.running || recoveryGeneration !== this.airPlayGeneration) {
        return;
      }
      this.pendingAirPlayDisconnect = '';
      this.airPlayConnectInProgress = false;
      this.scheduleAirPlayReconnect('RTSP 会话意外关闭');
    })();
  }

  private scheduleAirPlayReconnect(reason: string): void {
    if (!this.running || !this.hasAirPlayStartSignal() || !this.discoveredAirPlay ||
      this.airPlayReconnectTimer >= 0) {
      return;
    }
    if (this.airPlayPairingDeadline < 0) {
      this.airPlayPairingDeadline = Date.now() + AIRPLAY_PAIRING_WINDOW_MS;
    }
    const remainingMs = this.airPlayPairingDeadline - Date.now();
    if (remainingMs <= 0) {
      this.events.onStatus('AirPlay 自动重连已暂停，请手动重试');
      this.events.onLog(`AirPlay 配对重试窗口已到 120 秒；最近原因：${reason}`);
      return;
    }
    const attempt = this.airPlayReconnectAttempts + 1;
    const delayMs = Math.min(2000, remainingMs);
    this.airPlayReconnectAttempts = attempt;
    this.events.onLog(`AirPlay ${reason}；${delayMs / 1000} 秒后自动重连 (${attempt}，剩余 ${Math.ceil(remainingMs / 1000)} 秒)`);
    this.airPlayReconnectTimer = setTimeout((): void => {
      this.airPlayReconnectTimer = -1;
      if (!this.running || !this.hasAirPlayStartSignal() || !this.discoveredAirPlay ||
        this.airPlayConnectInProgress) {
        return;
      }
      this.airPlayConnectAttempted = false;
      void this.connectAirPlay().catch((error: Error): void => this.reportError(error));
    }, delayMs);
  }

  private scheduleAirPlayStableReset(generation: number): void {
    this.clearAirPlayStableTimer();
    this.airPlayStableTimer = setTimeout((): void => {
      this.airPlayStableTimer = -1;
      if (this.running && generation === this.airPlayGeneration) {
        this.airPlayReconnectAttempts = 0;
        this.airPlayPairingDeadline = -1;
      }
    }, 60000);
  }

  private clearAirPlayStableTimer(): void {
    if (this.airPlayStableTimer >= 0) {
      clearTimeout(this.airPlayStableTimer);
      this.airPlayStableTimer = -1;
    }
  }

  private clearAirPlayTimers(): void {
    if (this.airPlayReconnectTimer >= 0) {
      clearTimeout(this.airPlayReconnectTimer);
      this.airPlayReconnectTimer = -1;
    }
    this.clearAirPlayStableTimer();
    this.clearAirPlayWaitTimers();
  }

  private isCurrentAirPlaySession(pairing: AirPlayPairingClient, generation: number): boolean {
    return this.running && generation === this.airPlayGeneration && this.activePairing === pairing;
  }

  private async startProjection(
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

  private async stopProjection(): Promise<void> {
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

  private async startAudio(media: AirPlayMediaSessionInfo, generation: number): Promise<void> {
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

  private reportError(error: Error | string): void {
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

function makeAirPlayServiceFromEndpoint(endpoint: WirelessAirPlayEndpoint): AirPlayService {
  const addresses = endpoint.addresses.slice();
  const host = addresses.find((address: string): boolean => address.includes('.') && !address.includes(':')) ??
    addresses[0] ?? '';
  const txt: Record<string, string> = {};
  txt['deviceid'] = endpoint.deviceIdentifier;
  if (endpoint.publicKey) {
    txt['pk'] = endpoint.publicKey;
  }
  txt['srcvers'] = endpoint.sourceVersion;
  const service: AirPlayService = {
    name: `iAP2 ${endpoint.deviceIdentifier}`,
    host,
    addresses,
    port: endpoint.port,
    txt
  };
  return service;
}

function normalizeDeviceIdentifier(value: string): string {
  return value.trim().replace(/[:-]/g, '').toLowerCase();
}
