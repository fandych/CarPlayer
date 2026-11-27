import common from '@ohos.app.ability.common';
import { AirPlayService } from '../network/AirPlayMdnsDiscovery';
import { AirPlayIdentityStore } from './AirPlayIdentityStore';
import { AirPlayPairingHandshake } from './AirPlayPairingHandshake';
import {
  AirPlayMediaSession,
  AirPlayMediaSessionInfo,
  AirPlayMediaSessionStatusError
} from './AirPlayMediaSession';
import { EncodedH264Event } from './AirPlayVideoStream';
import { AirPlayRtspClient } from './AirPlayRtspClient';
import { orderAirPlayAddresses, WifiNetworkLease } from '../network/WifiNetworkLease';
import { Iap2SenderSession } from '../session/Iap2SenderSession';

export { AirPlayRtspStatusError } from './pairing/PairingProtocol';
export { supportsAirPlayPairingAndEncryption } from './AirPlayPairingHelpers';

export interface AirPlayPairingResult {
  receiverId: string;
  encryptedControl: boolean;
  model: string;
  features: string;
}

const AIRPLAY_PLAINTEXT_SETUP_WINDOW_MS: number = 120_000;
const AIRPLAY_PLAINTEXT_SETUP_RETRY_MS: number = 2000;

export class AirPlayPairingClient {
  private readonly identityStore: AirPlayIdentityStore = new AirPlayIdentityStore();
  private readonly log: (message: string) => void;
  private readonly onDisconnected: (message: string) => void;
  private readonly wifiNetworkLease: WifiNetworkLease;
  private client?: AirPlayRtspClient;
  private service?: AirPlayService;
  private connectedHost?: string;
  private sharedSecret?: Uint8Array;
  private mediaSession?: AirPlayMediaSession;
  private lifecycleGeneration: number = 0;

  constructor(
    log: (message: string) => void,
    onDisconnected: (message: string) => void,
    wifiNetworkLease: WifiNetworkLease
  ) {
    this.log = log;
    this.onDisconnected = onDisconnected;
    this.wifiNetworkLease = wifiNetworkLease;
  }

  async pair(context: common.UIAbilityContext, service: AirPlayService): Promise<AirPlayPairingResult> {
    const generation = this.lifecycleGeneration;
    const handshake = new AirPlayPairingHandshake(
      this.identityStore,
      this.log,
      (target: AirPlayService): Promise<void> => this.connect(target),
      (): AirPlayRtspClient => this.requireClient(),
      (): Promise<void> => this.closeResources(),
      (): boolean => generation === this.lifecycleGeneration
    );
    const state = await handshake.prepare(context, service);
    try {
      const outcome = await handshake.run(state, service);
      const receiverId = outcome.receiverId;
      const model = outcome.model;
      const features = outcome.features;
      const sharedSecret = outcome.sharedSecret;
      const usedPairVerifyFastPath = outcome.usedPairVerifyFastPath;
      this.service = service;
      this.sharedSecret = sharedSecret;
      this.log(
        `AirPlay pair-verify 已通过：receiver=${receiverId} mDNS model=${model} features=${features} ` +
          `路径=${usedPairVerifyFastPath ? '已配对快路径' : '新配对'}`
      );
      const result: AirPlayPairingResult = { receiverId, encryptedControl: true, model, features };
      return result;
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      try {
        await this.close();
      } catch (cleanupError) {
        const cleanupMessage = cleanupError instanceof Error ? cleanupError.message : String(cleanupError);
        throw new Error(`${message}; RTSP cleanup failed: ${cleanupMessage}`);
      }
      throw error instanceof Error ? error : new Error(String(error));
    }
  }

  async connectUnpaired(service: AirPlayService): Promise<AirPlayPairingResult> {
    await this.connect(service);
    this.service = service;
    this.sharedSecret = undefined;
    const result: AirPlayPairingResult = {
      receiverId: service.txt['deviceid'] ?? 'unpaired',
      encryptedControl: false,
      model: service.txt['model'] ?? '未提供',
      features: service.txt['features'] ?? '未提供'
    };
    this.log('AirPlay receiver does not require HomeKit pairing; using et=NONE session setup');
    return result;
  }

  private requireClient(): AirPlayRtspClient {
    const client = this.client;
    if (!client) {
      throw new Error('AirPlay RTSP connection disappeared during pairing');
    }
    return client;
  }

  private async connect(service: AirPlayService): Promise<void> {
    const hosts = orderAirPlayAddresses([service.host, ...(service.addresses ?? [])].filter(Boolean));
    const failures: string[] = [];
    for (const host of hosts) {
      let connectionEstablished = false;
      const client = new AirPlayRtspClient(
        this.log,
        (message: string): void => {
          if (connectionEstablished) {
            this.onDisconnected(message);
          }
        },
        this.wifiNetworkLease
      );
      this.client = client;
      try {
        await client.connect(host, service.port);
        connectionEstablished = true;
        this.connectedHost = host;
        return;
      } catch (error) {
        this.client = undefined;
        const message = error instanceof Error ? error.message : String(error);
        failures.push(`${host}: ${message}`);
        try {
          await client.close();
        } catch (cleanupError) {
          failures.push(`${host} cleanup: ${cleanupError instanceof Error ? cleanupError.message : String(cleanupError)}`);
        }
      }
    }
    throw new Error(`连接 AirPlay 接收端失败：${failures.join('; ') || '没有有效 IP 地址'}`);
  }

  async startCarPlaySession(
    deviceId: string,
    mib3VirtualLink: boolean = false,
    virtualIap2Session?: Iap2SenderSession
  ): Promise<AirPlayMediaSessionInfo> {
    const sharedSecret = this.sharedSecret;
    const service = this.service;
    if (!this.client || !service) {
      throw new Error('AirPlay RTSP connection must exist before starting a media session');
    }
    if (this.mediaSession) {
      throw new Error('AirPlay media session is already active');
    }
    if (sharedSecret) {
      return await this.startMediaSession(deviceId, service, sharedSecret, mib3VirtualLink, virtualIap2Session);
    }

    const generation = this.lifecycleGeneration;
    const deadline = Date.now() + AIRPLAY_PLAINTEXT_SETUP_WINDOW_MS;
    let lastError: Error = new Error('AirPlay plaintext SETUP did not complete');
    while (Date.now() < deadline) {
      try {
        return await this.startMediaSession(deviceId, service, undefined, mib3VirtualLink, virtualIap2Session);
      } catch (error) {
        if (!(error instanceof AirPlayMediaSessionStatusError) || error.stage !== 'initial session SETUP') {
          throw error instanceof Error ? error : new Error(String(error));
        }
        lastError = error instanceof Error ? error : new Error(String(error));
        const remainingMs = deadline - Date.now();
        if (remainingMs <= 0) {
          break;
        }
        await this.closeResources();
        await new Promise<void>((resolve): void => {
          setTimeout(resolve, Math.min(AIRPLAY_PLAINTEXT_SETUP_RETRY_MS, remainingMs));
        });
        if (generation !== this.lifecycleGeneration) {
          throw new Error('AirPlay plaintext SETUP retry was cancelled');
        }
        await this.connect(service);
        if (generation !== this.lifecycleGeneration) {
          await this.closeResources();
          throw new Error('AirPlay plaintext SETUP retry was cancelled');
        }
        this.service = service;
      }
    }
    throw lastError;
  }

  private async startMediaSession(
    deviceId: string,
    service: AirPlayService,
    sharedSecret: Uint8Array | undefined,
    mib3VirtualLink: boolean,
    virtualIap2Session?: Iap2SenderSession
  ): Promise<AirPlayMediaSessionInfo> {
    const client = this.client;
    if (!client) {
      throw new Error('AirPlay RTSP connection disappeared before media startup');
    }
    const session = new AirPlayMediaSession(
      client,
      this.connectedHost ?? service.host,
      (message: string): void => this.log(message),
      (message: string): void => this.onDisconnected(message),
      this.wifiNetworkLease
    );
    this.mediaSession = session;
    try {
      return await session.start(deviceId, sharedSecret, mib3VirtualLink, virtualIap2Session);
    } catch (error) {
      this.mediaSession = undefined;
      throw error instanceof Error ? error : new Error(String(error));
    }
  }

  async pushEncodedVideo(event: EncodedH264Event): Promise<void> {
    const mediaSession = this.mediaSession;
    if (!mediaSession) {
      throw new Error('AirPlay media session is not active');
    }
    await mediaSession.pushEncodedVideo(event);
  }

  async sendVirtualIap2Message(bytes: Uint8Array): Promise<void> {
    const mediaSession = this.mediaSession;
    if (!mediaSession) {
      throw new Error('AirPlay media session is not active');
    }
    await mediaSession.sendVirtualIap2Message(bytes);
  }

  setForceKeyFrameHandler(handler: (() => void) | undefined): void {
    this.mediaSession?.setForceKeyFrameHandler(handler);
  }

  async requestReceiverHome(): Promise<void> {
    if (!this.mediaSession) {
      throw new Error('车机会话未连接');
    }
    await this.mediaSession.requestReceiverHome();
  }

  setTouchReportHandler(handler: ((report: Uint8Array) => void) | undefined): void {
    this.mediaSession?.setTouchReportHandler(handler);
  }

  setNightModeHandler(handler: ((night: boolean) => void) | undefined): void {
    this.mediaSession?.setNightModeHandler(handler);
  }

  async stopMediaSession(abort: boolean = false): Promise<void> {
    const mediaSession = this.mediaSession;
    this.mediaSession = undefined;
    if (mediaSession) {
      await mediaSession.stop(abort);
    }
  }

  async close(): Promise<void> {
    this.lifecycleGeneration++;
    await this.closeResources();
  }

  private async closeResources(): Promise<void> {
    const failures: string[] = [];
    try {
      await this.stopMediaSession();
    } catch (error) {
      failures.push(`AirPlay media session: ${error instanceof Error ? error.message : String(error)}`);
    }
    const client = this.client;
    this.client = undefined;
    this.service = undefined;
    this.connectedHost = undefined;
    this.sharedSecret = undefined;
    if (client) {
      try {
        await client.close();
      } catch (error) {
        failures.push(`AirPlay RTSP client: ${error instanceof Error ? error.message : String(error)}`);
      }
    }
    if (failures.length > 0) {
      throw new Error(`AirPlay cleanup failed: ${failures.join('; ')}`);
    }
  }
}
