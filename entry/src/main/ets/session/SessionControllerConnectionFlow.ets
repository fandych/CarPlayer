import abilityAccessCtrl from '@ohos.abilityAccessCtrl';
import common from '@ohos.app.ability.common';
import { AirPlayPairingClient } from '../airplay/AirPlayPairingClient';
import { AirPlayMediaSessionInfo } from '../airplay/AirPlayMediaSession';
import { AudioRtpSender } from '../audio/AudioRtpSender';
import { PlaybackAudioCapture } from '../audio/PlaybackAudioCapture';
import { MfiTrustPromptInfo } from '../iap2/MfiVerifier';
import { AirPlayMdnsDiscovery, AirPlayService } from '../network/AirPlayMdnsDiscovery';
import { AirPlayMdnsRawMonitor } from '../network/AirPlayMdnsRawMonitor';
import { CarPlayCtrlAdvertiser } from '../network/CarPlayCtrlAdvertiser';
import { WifiCarPlayConnector } from '../network/WifiCarPlayConnector';
import { WifiNetworkLease } from '../network/WifiNetworkLease';
import { BluetoothIap2Server } from '../transport/BluetoothIap2Server';
import { CarPlayVirtualDisplay } from '../video/CarPlayVirtualDisplay';
import { CarPlayTouchInput } from '../video/CarPlayTouchInput';
import { NativeH264ScreenCapture } from '../video/NativeH264ScreenCapture';
import { NativeH264VideoEncoder } from '../video/NativeH264VideoEncoder';
import { Iap2SenderSession, WifiCredentials, WirelessAirPlayEndpoint } from './Iap2SenderSession';

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

export abstract class SessionControllerConnectionFlow {
  abstract stop(): Promise<void>;
  protected abstract startProjection(
    media: AirPlayMediaSessionInfo,
    pairing: AirPlayPairingClient,
    generation: number
  ): Promise<void>;
  protected abstract stopProjection(): Promise<void>;
  protected abstract startAudio(media: AirPlayMediaSessionInfo, generation: number): Promise<void>;
  protected abstract reportError(error: Error | string): void;

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
  protected mdnsRawMonitor?: AirPlayMdnsRawMonitor;
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
  protected airPlayCtrlReannounceTimer: number = -1;
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
}
