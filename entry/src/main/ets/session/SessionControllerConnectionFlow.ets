import abilityAccessCtrl from '@ohos.abilityAccessCtrl';
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


export class SessionControllerConnectionFlow {
  protected readonly context: common.UIAbilityContext;
  protected readonly events: SessionEvents;
  protected readonly bluetooth: BluetoothIap2Server = new BluetoothIap2Server();
  protected readonly wifi: WifiCarPlayConnector = new WifiCarPlayConnector();
  protected readonly wifiNetworkLease: WifiNetworkLease = new WifiNetworkLease();
  protected readonly projectionDisplay: CarPlayVirtualDisplay = new CarPlayVirtualDisplay();
  protected readonly touchInput: CarPlayTouchInput = new CarPlayTouchInput();
  protected readonly videoCapture: NativeH264ScreenCapture = new NativeH264ScreenCapture();
  protected readonly videoEncoder: NativeH264VideoEncoder = new NativeH264VideoEncoder();
  protected audioRtpSender?: AudioRtpSender;
  protected playbackAudioCapture?: PlaybackAudioCapture;
  protected discovery?: AirPlayMdnsDiscovery;
  protected ctrlAdvertiser?: CarPlayCtrlAdvertiser;
  protected activePairing?: AirPlayPairingClient;
  protected discoveredAirPlay?: AirPlayService;
  protected mdnsAirPlayService?: AirPlayService;
  protected iap2AirPlayEndpoint?: WirelessAirPlayEndpoint;
  protected airPlayIdentityConflict: boolean = false;
  protected iap2?: Iap2SenderSession;
  protected credentials?: WifiCredentials;
  protected running: boolean = false;
  protected inviteReceived: boolean = false;
  protected airPlayStartSessionReceived: boolean = false;
  protected airPlayInviteWaitElapsed: boolean = false;
  protected airPlayEndpointResolveElapsed: boolean = false;
  protected vehicleWifiConnected: boolean = false;
  protected adapterMode: boolean = false;
  protected wifiJoinInProgress: boolean = false;
  protected wifiJoinGeneration: number = 0;
  protected airPlayConnectInProgress: boolean = false;
  protected airPlayConnectAttempted: boolean = false;
  protected airPlayGeneration: number = 0;
  protected airPlayReconnectTimer: number = -1;
  protected airPlayStableTimer: number = -1;
  protected airPlayInviteWaitTimer: number = -1;
  protected airPlayEndpointResolveTimer: number = -1;
  protected pendingStartSessionTimer: number = -1;
  protected airPlayReconnectAttempts: number = 0;
  protected airPlayPairingDeadline: number = -1;
  protected wifiReconnectTimer: number = -1;
  protected wifiReconnectAttempts: number = 0;
  protected wifiLostCleanupInProgress: boolean = false;
  protected lastGatewayFallbackSignature: string = '';
  protected pendingAirPlayDisconnect: string = '';
  protected readonly deviceAddress: string;
  protected readonly deviceName: string;
  protected readonly deviceUuid: string;
  protected readonly keepScreenOn: boolean;
  protected readonly allowMfiIntermediateDownload: boolean;
  protected readonly trustedMfiFingerprints: string[];
  protected readonly skipMfiChallengeVerification: boolean;
  protected videoFrameCount: number = 0;
  protected videoCodecConfigCount: number = 0;
  protected readonly receiverHomeHandler = (): void => {
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
  protected async requestPermissions(permissions: Array<
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

  protected startAirPlayDiscovery(): void {
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
        if (this.inviteReceived || this.airPlayInviteWaitElapsed || this.hasSelfContainedAirPlayEndpoint()) {
          this.clearAirPlayWaitTimers();
        }
        void this.connectAirPlay().catch((error: Error): void => this.reportError(error));
      },
      (message: string): void => this.events.onLog(message)
    );
    this.discovery.start();
    this.events.onLog('正在发现 _airplay._tcp 服务');
  }

  protected handleIap2AirPlayEndpoint(endpoint: WirelessAirPlayEndpoint | undefined): void {
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

  protected refreshDiscoveredAirPlay(): void {
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

  protected makeAirPlayGatewayFallback(endpoint?: WirelessAirPlayEndpoint): AirPlayService | undefined {
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

  protected rejectAirPlayIdentityConflict(reason: string): void {
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

  protected async startControlAdvertisement(): Promise<void> {
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

  protected hasSelfContainedAirPlayEndpoint(): boolean {
    const endpoint = this.iap2AirPlayEndpoint;
    return endpoint !== undefined && endpoint.port > 0 &&
      endpoint.addresses.some((address: string): boolean => address.trim().length > 0);
  }

  protected hasAirPlayStartSignal(): boolean {
    return this.inviteReceived || this.airPlayStartSessionReceived ||
      this.mdnsAirPlayService !== undefined || this.airPlayEndpointResolveElapsed;
  }

  protected startAirPlayPrerequisiteWait(): void {
    if (!this.running || !this.vehicleWifiConnected) {
      return;
    }
    if (this.hasSelfContainedAirPlayEndpoint()) {
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
      if (!this.running || !this.vehicleWifiConnected || this.hasSelfContainedAirPlayEndpoint()) {
        return;
      }
      this.airPlayInviteWaitElapsed = true;
      this.events.onLog('等待 CarPlay ctrl 邀请达到 4 秒；继续等待 AirPlay mDNS/端点解析');
      this.startAirPlayEndpointResolutionWait();
    }, AIRPLAY_CTRL_INVITE_WAIT_MS);
  }

  protected startAirPlayEndpointResolutionWait(): void {
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

  protected clearAirPlayInviteWaitTimer(): void {
    if (this.airPlayInviteWaitTimer >= 0) {
      clearTimeout(this.airPlayInviteWaitTimer);
      this.airPlayInviteWaitTimer = -1;
    }
  }

  protected clearAirPlayEndpointResolveTimer(): void {
    if (this.airPlayEndpointResolveTimer >= 0) {
      clearTimeout(this.airPlayEndpointResolveTimer);
      this.airPlayEndpointResolveTimer = -1;
    }
  }

  protected clearAirPlayWaitTimers(): void {
    this.clearAirPlayInviteWaitTimer();
    this.clearAirPlayEndpointResolveTimer();
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

  protected async connectAirPlay(): Promise<void> {
    const service = this.discoveredAirPlay;
    if (this.airPlayIdentityConflict) {
      this.events.onLog('AirPlay mDNS 与 iAP2 endpoint 身份冲突；拒绝连接');
      return;
    }
    if (!this.running || !service || !isAirPlayStartReady(
      this.vehicleWifiConnected,
      this.inviteReceived || this.airPlayInviteWaitElapsed,
      this.hasSelfContainedAirPlayEndpoint(),
      this.mdnsAirPlayService !== undefined,
      this.airPlayEndpointResolveElapsed
    ) || this.airPlayConnectInProgress ||
      this.airPlayConnectAttempted) {
      return;
    }
    const pairingRequired = supportsAirPlayPairingAndEncryption(service.txt['features']) !== false;
    if (pairingRequired && !/^(?:0x)?[0-9a-fA-F]{64}$/.test(service.txt['pk'] ?? '')) {
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
    const mib3VirtualLink = this.iap2?.isClassicMib3Receiver === true;
    const pairing = new AirPlayPairingClient(
      (message: string): void => this.events.onLog(message),
      (message: string): void => this.handleAirPlayTransportDisconnect(generation, message),
      this.wifiNetworkLease
    );
    const virtualIap2 = mib3VirtualLink ? new Iap2SenderSession(
      (bytes: Uint8Array): Promise<void> => pairing.sendVirtualIap2Message(bytes),
      (message: string): void => this.events.onLog(message),
      (): void => {},
      (): void => {},
      this.deviceAddress,
      this.deviceName,
      this.deviceUuid,
      this.allowMfiIntermediateDownload,
      this.trustedMfiFingerprints,
      this.events.requestMfiTrust,
      this.events.persistMfiFingerprint,
      this.skipMfiChallengeVerification,
      this.context,
      (): void => {},
      true
    ) : undefined;
    this.activePairing = pairing;
    try {
      let result: AirPlayPairingResult;
      if (pairingRequired) {
        this.events.onStatus('车机邀请和 AirPlay 服务已就绪，正在安全配对');
        this.events.onLog(`开始 AirPlay Pair-Setup/Verify：${service.host}:${service.port}`);
        try {
          result = await pairing.pair(this.context, service);
        } catch (error) {
          if (!(error instanceof AirPlayRtspStatusError) ||
            ![404, 405, 455, 501].includes(error.statusCode)) {
            throw error instanceof Error ? error : new Error(String(error));
          }
          await pairing.close();
          result = await pairing.connectUnpaired(service);
          this.events.onLog(
            `AirPlay pairing 接口返回 ${error.statusCode}，按 CardDeck et=NONE 兼容路径重试`
          );
        }
      } else {
        this.events.onStatus('接收端未声明 AirPlay 配对加密，正在建立 et=NONE 会话');
        result = await pairing.connectUnpaired(service);
      }
      if (!this.running || generation !== this.airPlayGeneration) {
        await pairing.close();
        return;
      }
      if (result.encryptedControl) {
        this.events.onLog(`AirPlay 配对验证通过：${result.receiverId} · ${result.model}`);
        this.events.onStatus('AirPlay 配对通过，正在建立 RTSP 会话');
      }
      let media: AirPlayMediaSessionInfo;
      try {
        media = await pairing.startCarPlaySession(this.deviceAddress, mib3VirtualLink, virtualIap2);
      } catch (error) {
        if (pairingRequired || result.encryptedControl || !(error instanceof AirPlayMediaSessionStatusError) ||
          error.stage !== 'initial session SETUP') {
          throw error instanceof Error ? error : new Error(String(error));
        }
        await pairing.close();
        this.events.onLog('et=NONE 初始 SETUP 被拒绝；尝试 Pair-Setup/Pair-Verify 加密升级');
        result = await pairing.pair(this.context, service);
        media = await pairing.startCarPlaySession(this.deviceAddress, mib3VirtualLink, virtualIap2);
      }
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

  protected handleAirPlayTransportDisconnect(generation: number, message: string): void {
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

  protected scheduleAirPlayReconnect(reason: string): void {
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

  protected scheduleAirPlayStableReset(generation: number): void {
    this.clearAirPlayStableTimer();
    this.airPlayStableTimer = setTimeout((): void => {
      this.airPlayStableTimer = -1;
      if (this.running && generation === this.airPlayGeneration) {
        this.airPlayReconnectAttempts = 0;
        this.airPlayPairingDeadline = -1;
      }
    }, 60000);
  }

  protected clearAirPlayStableTimer(): void {
    if (this.airPlayStableTimer >= 0) {
      clearTimeout(this.airPlayStableTimer);
      this.airPlayStableTimer = -1;
    }
  }

  protected clearAirPlayTimers(): void {
    if (this.airPlayReconnectTimer >= 0) {
      clearTimeout(this.airPlayReconnectTimer);
      this.airPlayReconnectTimer = -1;
    }
    this.clearAirPlayStableTimer();
    this.clearAirPlayWaitTimers();
  }

  protected isCurrentAirPlaySession(pairing: AirPlayPairingClient, generation: number): boolean {
    return this.running && generation === this.airPlayGeneration && this.activePairing === pairing;
  }

}
