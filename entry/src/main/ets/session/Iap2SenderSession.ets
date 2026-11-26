import { Iap2SenderSessionTransport } from './iap2/Iap2SenderSessionTransport';
import { isClassicMib3Profile, MESSAGE } from './iap2/Iap2SessionProtocol';

export {
  encodeBuickB233AvailabilityBody,
  isBuickB233Identity,
  isClassicMib3Profile,
  parseMfiCertificatePayload,
  readMessageIds,
  shouldProbeLegacyWifi
} from './iap2/Iap2SessionProtocol';

export {
  parseWirelessSessionCredentials,
  parseWirelessSessionEndpoint,
  WifiCredentials,
  WirelessAirPlayEndpoint
} from './iap2/WirelessSessionParser';

export class Iap2SenderSession extends Iap2SenderSessionTransport {
  get isAccessoryVerified(): boolean {
    return this.mfiVerified;
  }

  get isAuthenticationComplete(): boolean {
    return this.authenticated;
  }

  protected async onControlMessageReceived(messageId: number, body: Uint8Array): Promise<void> {
    await this.receiveControlMessage(messageId, body);
  }

  protected async onIdentificationRequested(): Promise<void> {
    if (this.identificationTimer !== undefined) {
      clearTimeout(this.identificationTimer);
      this.identificationTimer = undefined;
    }
    await this.sendControl(MESSAGE.IDENTIFICATION_START);
    this.log('已发送 iAP2 IDENTIFICATION_START，等待车机识别信息');
    this.identificationTimer = setTimeout((): void => {
      this.identificationTimer = undefined;
      if (!this.validatedAccessoryCertificate && !this.authenticated) {
        this.log('等待 iAP2 0x1D01 超时：检查车机是否接受 SYN-ACK、RFCOMM 链路序号与识别消息');
      }
    }, 8000);
  }

  protected async restartSessionForNewPeerSync(): Promise<void> {
    this.cancel();
    this.resetLinkSessionState();
    this.mfiAuthenticationFailed = false;
    this.mfiCertificateRequestCount = 0;
    this.challengeIndex = 0;
    this.validatedAccessoryCertificate = undefined;
    await this.start(false);
  }

  protected onLinkResetDiagnostic(): void {
    if (this.buickB233Receiver && this.buickWaitingForStartSession) {
      this.log(
        `Buick B233 T21：iAP2 link reset while waiting 0x4301；${this.controlAckSnapshot()} ` +
          `frameSHA256prefix=${this.buickAvailabilityFrameDigest}`
      );
    }
  }

  protected onBuickRetransmissionFailure(): boolean {
    return this.buickB233Receiver && this.buickWaitingForStartSession;
  }

  protected onFrameSentWhileBuickWaiting(): boolean {
    return this.buickB233Receiver && this.buickWaitingForStartSession;
  }

  protected getBuickAvailabilityFrameDigest(): string {
    return this.buickAvailabilityFrameDigest;
  }

  setMib3WirelessSessionUuid(sessionUuid: string): void {
    if (!/^[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}$/.test(sessionUuid)) {
      throw new Error('MIB3 virtual iAP2 requires the AirPlay wireless session UUID');
    }
    this.mib3WirelessSessionUuid = sessionUuid;
  }

  get isClassicMib3Receiver(): boolean {
    return isClassicMib3Profile(
      this.accessoryIdentity,
      this.accessorySendMessages,
      this.accessoryReceiveMessages
    );
  }
}
