import common from '@ohos.app.ability.common';
import { concatBytes } from '../../protocol/Iap2Codec';
import { MfiTrustPromptInfo, MfiVerifier, ValidatedMfiCertificate } from '../../iap2/MfiVerifier';
import {
  EaProtocol,
  MESSAGE,
  MIB3_COMMUNICATIONS_IDLE_BODY,
  MIB3_NOW_PLAYING_IDLE_BODY
} from './Iap2SessionProtocol';
import { WifiCredentials, WirelessAirPlayEndpoint } from './WirelessSessionParser';
import { Iap2LinkLayer } from './Iap2LinkLayer';

interface PendingAuthenticatedMessage {
  messageId: number;
  body: Uint8Array;
}

export abstract class Iap2SenderSessionState extends Iap2LinkLayer {
  protected readonly onWifi: (credentials: WifiCredentials) => void;
  protected readonly onEndpoint: (endpoint: WirelessAirPlayEndpoint | undefined) => void;
  protected readonly onEndpointPending: () => void;
  protected readonly mfiVerifier: MfiVerifier;
  protected readonly mfiOnlyVirtualLink: boolean;
  protected mib3WirelessSessionUuid: string = '';
  protected pendingReceiveChunks: number = 0;
  protected lastReceiveQueueDelayLogAt: number = 0;
  protected readonly deviceAddress: string;
  protected readonly deviceName: string;
  protected readonly deviceUuid: string;
  protected readonly context?: common.UIAbilityContext;
  protected authenticated: boolean = false;
  protected mfiVerified: boolean = false;
  protected mfiAuthenticationFailed: boolean = false;
  protected accessoryIdentity: string = '';
  protected buickB233Receiver: boolean = false;
  protected buickAvailabilitySent: boolean = false;
  protected buickWaitingForStartSession: boolean = false;
  protected buickReidentificationWindowOpen: boolean = false;
  protected buickMarkerEchoSent: boolean = false;
  protected buickReidentificationUsed: boolean = false;
  protected buickReauthenticationInProgress: boolean = false;
  protected pendingBuickStartSession?: Uint8Array;
  protected pendingAuthenticatedMessages: PendingAuthenticatedMessage[] = [];
  protected lastDetectionResponseAt: number = 0;
  protected detectionRetryCount: number = 0;
  protected accessorySendMessages?: number[];
  protected accessoryReceiveMessages?: number[];
  protected accessoryEaProtocols: EaProtocol[] = [];
  protected deviceAnnouncementSent: boolean = false;
  protected deviceAnnouncementInProgress: boolean = false;
  protected challengeLength: number = 32;
  protected challengeLengths: number[] = [32, 20, 16];
  protected challengeIndex: number = 0;
  protected validatedAccessoryCertificate?: ValidatedMfiCertificate;
  protected pendingMfiChallenge?: Uint8Array;
  protected transportIdentifierSent: boolean = false;
  protected transportIdentifierPending: boolean = false;
  protected challengeTimer?: number;
  protected mfiCertificateTimer?: number;
  protected mfiCertificateRequestCount: number = 0;
  protected wifiConfigurationTimer?: number;
  protected wifiConfigurationRescueGeneration: number = 0;
  protected wifiConfigurationDeadline: number = -1;
  protected eaSessionWaitTimer?: number;
  protected hidStartWaitTimer?: number;
  protected startSessionWaitTimer?: number;
  protected wifiConfigurationReceived: boolean = false;
  protected startSessionReceived: boolean = false;
  protected deviceStateGreetingsSent: boolean = false;
  protected buickStartSessionWaitTimer?: number;
  protected buickAvailabilitySentAt: number = 0;
  protected buickAvailabilityFrameDigest: string = '';

  protected abstract receiveControlMessage(messageId: number, body: Uint8Array): Promise<void>;

  protected deferAuthenticatedMessage(messageId: number, body: Uint8Array): void {
    const pendingMessage: PendingAuthenticatedMessage = {
      messageId: messageId,
      body: body.slice()
    };
    const existingIndex = this.pendingAuthenticatedMessages.findIndex(
      (message) => message.messageId === messageId
    );
    if (existingIndex >= 0) {
      this.pendingAuthenticatedMessages.splice(existingIndex, 1);
      this.log(`认证完成前再次收到 0x${messageId.toString(16)}；用最新消息替换暂存内容`);
    }
    if (this.pendingAuthenticatedMessages.length >= 8) {
      this.log(`认证前消息暂存区已满；忽略 0x${messageId.toString(16)}，避免无界占用内存`);
      return;
    }
    this.pendingAuthenticatedMessages.push(pendingMessage);
    this.log(`认证尚未完成；暂存 0x${messageId.toString(16)}，将在认证后处理`);
  }

  protected async replayAuthenticatedMessages(): Promise<void> {
    while (this.started && this.authenticated && this.pendingAuthenticatedMessages.length > 0) {
      const message = this.pendingAuthenticatedMessages.shift();
      if (message) {
        await this.receiveControlMessage(message.messageId, message.body);
      }
    }
  }

  constructor(
    sendBytes: (bytes: Uint8Array) => Promise<void>,
    log: (message: string) => void,
    onWifi: (credentials: WifiCredentials) => void,
    onEndpoint: (endpoint: WirelessAirPlayEndpoint | undefined) => void,
    deviceAddress: string,
    deviceName: string,
    deviceUuid: string,
    allowMfiIntermediateDownload: boolean = false,
    trustedMfiFingerprints: string[] = [],
    requestMfiTrust?: (info: MfiTrustPromptInfo) => Promise<boolean>,
    persistMfiFingerprint?: (fingerprint: string) => Promise<void>,
    skipMfiChallengeVerification: boolean = false,
    context?: common.UIAbilityContext,
    onEndpointPending: () => void = (): void => {},
    mfiOnlyVirtualLink: boolean = false
  ) {
    super(sendBytes, log);
    this.onWifi = onWifi;
    this.onEndpoint = onEndpoint;
    this.onEndpointPending = onEndpointPending;
    this.mfiOnlyVirtualLink = mfiOnlyVirtualLink;
    this.deviceAddress = deviceAddress;
    this.deviceName = deviceName;
    this.deviceUuid = deviceUuid;
    this.context = context;
    this.mfiVerifier = new MfiVerifier(
      log,
      allowMfiIntermediateDownload,
      trustedMfiFingerprints,
      requestMfiTrust,
      persistMfiFingerprint,
      skipMfiChallengeVerification
    );
  }
  protected async handleMib3PostAuthenticationMessage(messageId: number): Promise<void> {
    let responseId: number | undefined;
    let responseBody: Uint8Array = new Uint8Array(0);
    if (messageId === MESSAGE.MIB3_START_CALL_STATE_UPDATES) {
      responseId = MESSAGE.MIB3_CALL_STATE_UPDATE;
      responseBody = this.parameter(0x0002, new Uint8Array([0]));
    } else if (messageId === MESSAGE.MIB3_START_COMMUNICATIONS_UPDATES) {
      responseId = MESSAGE.MIB3_COMMUNICATIONS_UPDATE;
      responseBody = MIB3_COMMUNICATIONS_IDLE_BODY.slice();
    } else if (messageId === MESSAGE.MIB3_START_LIST_UPDATES) {
      responseId = MESSAGE.MIB3_LIST_UPDATE;
      responseBody = concatBytes(
        this.parameter(0x0000, new Uint8Array([0])),
        this.parameter(0x0002, new Uint8Array([0, 0])),
        this.parameter(0x0005, new Uint8Array([0])),
        this.parameter(0x0007, new Uint8Array([0, 0]))
      );
    } else if (messageId === MESSAGE.MIB3_START_NOW_PLAYING_UPDATES) {
      responseId = MESSAGE.MIB3_NOW_PLAYING_UPDATE;
      responseBody = MIB3_NOW_PLAYING_IDLE_BODY.slice();
    }
    if (responseId === undefined) {
      this.log(`MIB3 virtual iAP2: suppress unrelated post-auth message 0x${messageId.toString(16)}`);
      return;
    }
    await this.sendControl(responseId, responseBody);
    this.log(
      `MIB3 virtual iAP2: answered subscription 0x${messageId.toString(16)} ` +
        `with idle response 0x${responseId.toString(16)}`
    );
  }

  protected parameter(id: number, value: Uint8Array): Uint8Array {
    const result = new Uint8Array(4 + value.length);
    result[0] = (result.length >>> 8) & 0xff;
    result[1] = result.length & 0xff;
    result[2] = (id >>> 8) & 0xff;
    result[3] = id & 0xff;
    result.set(value, 4);
    return result;
  }
  protected errorDetails(error: Error | Object): string {
    if (error instanceof Error) {
      return error.stack ? `${error.message}\n${error.stack}` : error.message;
    }
    return String(error);
  }
}
