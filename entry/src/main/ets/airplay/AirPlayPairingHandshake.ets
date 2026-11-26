import common from '@ohos.app.ability.common';
import { AirPlayService } from '../network/AirPlayMdnsDiscovery';
import {
  AirPlayControllerIdentity,
  AirPlayIdentityStore,
  VerifiedAirPlayReceiverIdentity
} from './AirPlayIdentityStore';
import { AirPlayRtspClient } from './AirPlayRtspClient';
import { decodeAirPlayHex, equalAirPlayBytes } from './AirPlayPairingHelpers';
import { AirPlayRtspStatusError, PairSetupClient, PairVerifyClient } from './pairing/PairingProtocol';

export interface AirPlayPairingHandshakeOutcome {
  receiverId: string;
  model: string;
  features: string;
  sharedSecret: Uint8Array;
  usedPairVerifyFastPath: boolean;
}

export interface AirPlayPairingHandshakeState {
  context: common.UIAbilityContext;
  identity: AirPlayControllerIdentity;
  deviceIdentifier: string;
  storedReceiver?: VerifiedAirPlayReceiverIdentity;
  expectedReceiverKey?: Uint8Array;
}

export class AirPlayPairingHandshake {
  private readonly identityStore: AirPlayIdentityStore;
  private readonly log: (message: string) => void;
  private readonly connect: (service: AirPlayService) => Promise<void>;
  private readonly requireClient: () => AirPlayRtspClient;
  private readonly closeResources: () => Promise<void>;
  private readonly isCurrent: () => boolean;

  constructor(
    identityStore: AirPlayIdentityStore,
    log: (message: string) => void,
    connect: (service: AirPlayService) => Promise<void>,
    requireClient: () => AirPlayRtspClient,
    closeResources: () => Promise<void>,
    isCurrent: () => boolean
  ) {
    this.identityStore = identityStore;
    this.log = log;
    this.connect = connect;
    this.requireClient = requireClient;
    this.closeResources = closeResources;
    this.isCurrent = isCurrent;
  }

  async prepare(context: common.UIAbilityContext, service: AirPlayService): Promise<AirPlayPairingHandshakeState> {
    const advertisedReceiverKey = decodeAirPlayHex(service.txt['pk'] ?? '');
    if (advertisedReceiverKey.length !== 0 && advertisedReceiverKey.length !== 32) {
      throw new Error('AirPlay receiver public key must be 32 bytes');
    }
    if (advertisedReceiverKey.length === 0) {
      this.log('AirPlay endpoint 未提供预广播公钥；将从已验证的 Pair-Setup 响应建立接收端身份');
    }
    const identity = await this.identityStore.loadOrCreate(context);
    const deviceIdentifier = service.txt['deviceid'] ?? '';
    const storedReceiver = await this.identityStore.loadVerifiedReceiver(context, deviceIdentifier);
    if (!this.isCurrent()) {
      throw new Error('AirPlay pairing was cancelled');
    }
    if (advertisedReceiverKey.length === 32 && storedReceiver &&
      !equalAirPlayBytes(advertisedReceiverKey, storedReceiver.publicKeyRaw)) {
      throw new Error('AirPlay receiver key conflicts with the previously verified identity');
    }
    return {
      context,
      identity,
      deviceIdentifier,
      storedReceiver,
      expectedReceiverKey: advertisedReceiverKey.length === 32
        ? advertisedReceiverKey
        : storedReceiver?.publicKeyRaw
    };
  }

  async run(
    state: AirPlayPairingHandshakeState,
    service: AirPlayService
  ): Promise<AirPlayPairingHandshakeOutcome> {
    const { context, identity, deviceIdentifier, storedReceiver, expectedReceiverKey } = state;
    await this.connect(service);
    if (!this.isCurrent()) {
      await this.closeResources();
      throw new Error('AirPlay pairing was cancelled');
    }
    let setupReceiverId = '';
    let setupReceiverKey: Uint8Array | undefined;
    let usedPairVerifyFastPath = false;
    try {
      const receiver = await new PairSetupClient(this.requireClient(), identity, this.log)
        .run(expectedReceiverKey);
      setupReceiverId = receiver.receiverId;
      setupReceiverKey = receiver.receiverPublicKey;
    } catch (error) {
      if (!(error instanceof AirPlayRtspStatusError) || error.statusCode !== 403) {
        throw error instanceof Error ? error : new Error(String(error));
      }
      if (!expectedReceiverKey) {
        this.log('Pair-Setup 403 fast path rejected: no advertised or previously verified receiver key is available');
        throw error;
      }
      this.log('Pair-Setup 被接收端以 403 拒绝；关闭当前 TCP 并按 CardDeck 已配对快路径重连 Pair-Verify');
      await this.closeResources();
      if (!this.isCurrent()) {
        throw new Error('AirPlay pairing was cancelled');
      }
      await this.connect(service);
      if (!this.isCurrent()) {
        await this.closeResources();
        throw new Error('AirPlay pairing was cancelled');
      }
      usedPairVerifyFastPath = true;
    }
    const receiverKey = setupReceiverKey ?? expectedReceiverKey;
    if (!receiverKey || receiverKey.length !== 32) {
      throw new Error('Pair-Setup did not provide a verifiable receiver public key');
    }
    const keys = await new PairVerifyClient(this.requireClient(), identity, this.log).run(receiverKey);
    if (!this.isCurrent()) {
      await this.closeResources();
      throw new Error('AirPlay pairing was cancelled');
    }
    if (setupReceiverId && setupReceiverId !== keys.receiverId) {
      throw new Error('pair-setup and pair-verify receiver identities do not match');
    }
    if (storedReceiver && storedReceiver.receiverId !== keys.receiverId) {
      throw new Error('pair-verify receiver ID conflicts with the previously verified identity');
    }
    if (deviceIdentifier) {
      try {
        await this.identityStore.saveVerifiedReceiver(context, deviceIdentifier, keys.receiverId, receiverKey);
      } catch (error) {
        this.log(`WARN: AirPlay verified receiver identity could not be persisted: ${error instanceof Error ? error.message : String(error)}`);
      }
    }
    this.requireClient().activateEncryption(keys.phoneReadKey, keys.phoneWriteKey);
    return {
      receiverId: setupReceiverId || keys.receiverId,
      model: service.txt['model'] ?? '未提供',
      features: service.txt['features'] ?? '未提供',
      sharedSecret: keys.sharedSecret.slice(),
      usedPairVerifyFastPath
    };
  }
}
