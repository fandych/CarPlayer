import common from '@ohos.app.ability.common';
import { AirPlayService } from '../network/AirPlayMdnsDiscovery';
import { AirPlayIdentityStore } from './AirPlayIdentityStore';
import {
  AirPlayMediaSession,
  AirPlayMediaSessionInfo,
  AirPlayMediaSessionStatusError
} from './AirPlayMediaSession';
import { EncodedH264Event } from './AirPlayVideoStream';
import { AirPlayRtspClient } from './AirPlayRtspClient';
import { WifiNetworkLease } from '../network/WifiNetworkLease';
import { Iap2SenderSession } from '../session/Iap2SenderSession';
import { formatProtocolEvent } from '../session/ProtocolLogger';
import { AirPlayRtspStatusError, PairSetupClient, PairVerifyClient } from './pairing/PairingProtocol';

export { AirPlayRtspStatusError } from './pairing/PairingProtocol';

export interface AirPlayPairingResult {
  receiverId: string;
  encryptedControl: boolean;
  model: string;
  features: string;
}

const HK_PAIRING_AND_ENCRYPT: bigint = BigInt('0x4000000000');
const AIRPLAY_PLAINTEXT_SETUP_WINDOW_MS: number = 120_000;
const AIRPLAY_PLAINTEXT_SETUP_RETRY_MS: number = 2000;

export function supportsAirPlayPairingAndEncryption(features: string | undefined): boolean | undefined {
  if (!features) {
    return undefined;
  }
  const words = features.split(',');
  if (words.length !== 2) {
    return undefined;
  }
  const parseWord = (word: string): bigint | undefined => {
    const normalized = word.trim().replace(/^0x/i, '');
    if (!/^[0-9a-f]{1,8}$/i.test(normalized)) {
      return undefined;
    }
    return BigInt(`0x${normalized}`);
  };
  const low = parseWord(words[0]);
  const high = parseWord(words[1]);
  if (low === undefined || high === undefined) {
    return undefined;
  }
  const combined = (high << BigInt(32)) | low;
  return (combined & HK_PAIRING_AND_ENCRYPT) !== BigInt(0);
}

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
    const advertisedReceiverKey = decodeHex(service.txt['pk'] ?? '');
    if (advertisedReceiverKey.length !== 0 && advertisedReceiverKey.length !== 32) {
      throw new Error('AirPlay receiver public key must be 32 bytes');
    }
    if (advertisedReceiverKey.length === 0) {
      this.log('AirPlay endpoint 未提供预广播公钥；将从已验证的 Pair-Setup 响应建立接收端身份');
    }
    const identity = await this.identityStore.loadOrCreate(context);
    if (generation !== this.lifecycleGeneration) {
      throw new Error('AirPlay pairing was cancelled');
    }
    try {
      await this.connect(service);
      if (generation !== this.lifecycleGeneration) {
        await this.closeResources();
        throw new Error('AirPlay pairing was cancelled');
      }
      let setupReceiverId = '';
      let setupReceiverKey: Uint8Array | undefined;
      let usedPairVerifyFastPath = false;
      try {
        const receiver = await new PairSetupClient(this.requireClient(), identity, this.log)
          .run(advertisedReceiverKey.length === 32 ? advertisedReceiverKey : undefined);
        setupReceiverId = receiver.receiverId;
        setupReceiverKey = receiver.receiverPublicKey;
      } catch (error) {
        if (!(error instanceof AirPlayRtspStatusError) || error.statusCode !== 403) {
          throw error instanceof Error ? error : new Error(String(error));
        }
        if (advertisedReceiverKey.length !== 32) {
          throw new Error('Pair-Setup was rejected and no advertised receiver key is available for Pair-Verify');
        }
        this.log('Pair-Setup 被接收端以 403 拒绝；关闭当前 TCP 并按 CardDeck 已配对快路径重连 Pair-Verify');
        await this.closeResources();
        if (generation !== this.lifecycleGeneration) {
          throw new Error('AirPlay pairing was cancelled');
        }
        await this.connect(service);
        if (generation !== this.lifecycleGeneration) {
          await this.closeResources();
          throw new Error('AirPlay pairing was cancelled');
        }
        usedPairVerifyFastPath = true;
      }
      const receiverKey = setupReceiverKey ?? advertisedReceiverKey;
      if (receiverKey.length !== 32) {
        throw new Error('Pair-Setup did not provide a verifiable receiver public key');
      }
      const keys = await new PairVerifyClient(this.requireClient(), identity, this.log).run(receiverKey);
      if (generation !== this.lifecycleGeneration) {
        await this.closeResources();
        throw new Error('AirPlay pairing was cancelled');
      }
      if (setupReceiverId && setupReceiverId !== keys.receiverId) {
        throw new Error('pair-setup and pair-verify receiver identities do not match');
      }
      const client = this.requireClient();
      client.activateEncryption(keys.phoneReadKey, keys.phoneWriteKey);
      const model = service.txt['model'] ?? '未提供';
      const features = service.txt['features'] ?? '未提供';
      const receiverId = setupReceiverId || keys.receiverId;
      this.service = service;
      this.sharedSecret = keys.sharedSecret.slice();
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
    const hosts = Array.from(new Set([service.host, ...(service.addresses ?? [])].filter(Boolean)));
    const failures: string[] = [];
    for (const host of hosts) {
      let scopedHost: string;
      try {
        scopedHost = this.wifiNetworkLease.scopeLinkLocalAddress(host);
      } catch (error) {
        failures.push(`${host}: ${error instanceof Error ? error.message : String(error)}`);
        continue;
      }
      if (scopedHost !== host) {
        this.log(formatProtocolEvent('airplay.endpoint.address.scoped',
          'originalAddress', host,
          'scopedAddress', scopedHost
        ));
      }
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
        await client.connect(scopedHost, service.port);
        connectionEstablished = true;
        this.connectedHost = scopedHost;
        return;
      } catch (error) {
        this.client = undefined;
        const message = error instanceof Error ? error.message : String(error);
        failures.push(`${scopedHost}: ${message}`);
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

function decodeHex(hex: string): Uint8Array {
  const normalized = hex.startsWith('0x') ? hex.slice(2) : hex;
  if (normalized.length % 2 !== 0 || !/^[0-9a-fA-F]*$/.test(normalized)) {
    throw new Error('AirPlay TXT public key is not valid hexadecimal');
  }
  const result = new Uint8Array(normalized.length / 2);
  for (let index = 0; index < result.length; index++) {
    result[index] = parseInt(normalized.slice(index * 2, index * 2 + 2), 16);
  }
  return result;
}
