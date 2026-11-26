import {
  concatBytes,
  encodeIap2Control,
  encodeIap2LinkFrame,
  formatIap2MessageDiagnostic,
  formatIap2RawFrameDiagnostic,
  Iap2LinkFrame
} from '../../protocol/Iap2Codec';
import {
  formatIap2FrameInterpretation,
  LINK_MARKER
} from './Iap2SessionProtocol';
import { Iap2LinkLayerReceive } from './Iap2LinkLayerReceive';

export abstract class Iap2LinkLayer extends Iap2LinkLayerReceive {
  protected async sendControl(messageId: number, body: Uint8Array = new Uint8Array(0)): Promise<void> {
    const encoded = encodeIap2Control(messageId, body);
    this.log(formatIap2MessageDiagnostic('TX', messageId, body));
    const maximumPayload = Math.max(1, this.peerMaxPacketLength - 10);
    for (let offset = 0; offset < encoded.length; offset += maximumPayload) {
      const payload = encoded.slice(offset, Math.min(encoded.length, offset + maximumPayload));
      this.outboundQueue.push({
        control: 0x40,
        sequence: 0,
        acknowledgement: 0,
        sessionId: this.controlSessionId,
        payload
      });
    }
    await this.transmitPending();
  }

  protected async transmitPending(): Promise<void> {
    while (this.outboundQueue.length > 0 && this.unacknowledgedFrames.size < this.peerMaxOutstanding) {
      const queued = this.outboundQueue.shift();
      if (!queued) {
        break;
      }
      await this.sendLinkFrame({
        control: 0x40,
        sequence: this.takeSequence(),
        acknowledgement: this.lastReceivedSequence,
        sessionId: queued.sessionId,
        payload: queued.payload
      });
    }
    if (this.outboundQueue.length > 0) {
      this.log(`iAP2 发送窗口已满（${this.peerMaxOutstanding}），${this.outboundQueue.length} 个分片等待车机 ACK`);
    }
  }

  protected applyPeerLinkParameters(payload: Uint8Array): void {
    if (payload.length < 10) {
      return;
    }
    this.peerMaxOutstanding = Math.max(1, payload[1]);
    this.peerMaxPacketLength = Math.max(11, (payload[2] << 8) | payload[3]);
    this.peerRetransmitTimeoutMs = Math.max(200, (payload[4] << 8) | payload[5]);
    this.peerMaxRetransmissions = payload[8];
    this.log(
      `iAP2 链路参数：maxOutstanding=${this.peerMaxOutstanding}, maxPacket=${this.peerMaxPacketLength}, ` +
        `retransmitMs=${this.peerRetransmitTimeoutMs}, maxRetransmissions=${this.peerMaxRetransmissions}`
    );
  }

  private scheduleRetransmit(): void {
    if (this.retransmitTimer !== undefined || this.unacknowledgedFrames.size === 0) {
      return;
    }
    const generation = this.sessionGeneration;
    this.retransmitTimer = setTimeout((): void => {
      this.retransmitTimer = undefined;
      const retry = this.receiveQueue.then(async (): Promise<void> => {
        if (!this.started || generation !== this.sessionGeneration) {
          return;
        }
        await this.retransmitUnacknowledged();
      });
      this.receiveQueue = retry.catch((error: Error): void => {
        this.log(`iAP2 重传失败：${error.message}`);
      });
    }, this.peerRetransmitTimeoutMs);
  }

  protected async retransmitUnacknowledged(): Promise<void> {
    for (const pending of Array.from(this.unacknowledgedFrames.values())) {
      const attempts = (this.retransmitCounts.get(pending.sequence) ?? 0) + 1;
      if (attempts > this.peerMaxRetransmissions) {
        if (this.onBuickRetransmissionFailure()) {
          this.log(
            `Buick B233 T21：iAP2 链路在等待 0x4301 时失效；${this.controlAckSnapshot()} ` +
              `frameSHA256prefix=${this.getBuickAvailabilityFrameDigest()}`
          );
        }
        this.log(`ERROR: iAP2 序号 ${pending.sequence} 重传 ${this.peerMaxRetransmissions} 次仍未确认；链路视为失效`);
        this.cancel();
        return;
      }
      this.retransmitCounts.set(pending.sequence, attempts);
      this.log(`iAP2 超时重传序号 ${pending.sequence}（${attempts}/${this.peerMaxRetransmissions}）`);
      await this.sendLinkFrame({
        control: pending.control,
        sequence: pending.sequence,
        acknowledgement: this.lastReceivedSequence,
        sessionId: pending.sessionId,
        payload: pending.payload
      });
    }
  }

  protected clearRetransmitTimer(): void {
    if (this.retransmitTimer !== undefined) {
      clearTimeout(this.retransmitTimer);
      this.retransmitTimer = undefined;
    }
  }

  protected async sendLinkFrame(frame: Iap2LinkFrame, includeMarker: boolean = false): Promise<void> {
    const encodedFrame = encodeIap2LinkFrame(frame);
    this.log(formatIap2RawFrameDiagnostic('TX', frame, includeMarker));
    this.log(formatIap2FrameInterpretation('TX', frame));
    await this.sendBytes(includeMarker ? concatBytes(LINK_MARKER, encodedFrame) : encodedFrame);
    if (this.onFrameSentWhileBuickWaiting()) {
      this.log(
        `Buick B233 T21：iAP2 link reset while waiting 0x4301；${this.controlAckSnapshot()} ` +
          `frameSHA256prefix=${this.getBuickAvailabilityFrameDigest()}`
      );
    }
    if (frame.control === 0x40 && frame.payload.length > 0) {
      this.unacknowledgedFrames.set(frame.sequence, {
        control: frame.control,
        sequence: frame.sequence,
        acknowledgement: frame.acknowledgement,
        sessionId: frame.sessionId,
        payload: frame.payload.slice()
      });
      this.scheduleRetransmit();
    }
  }

  protected takeSequence(): number {
    const sequence = this.nextSequence;
    this.nextSequence = (this.nextSequence + 1) & 0xff;
    return sequence;
  }

  protected async waitForControlQueueDrain(timeoutMs: number): Promise<boolean> {
    const deadline = Date.now() + timeoutMs;
    while (this.started && Date.now() < deadline) {
      if (this.outboundQueue.length === 0 && this.unacknowledgedFrames.size === 0) {
        return true;
      }
      await new Promise<void>((resolve): void => { setTimeout(resolve, 50); });
    }
    return this.started && this.outboundQueue.length === 0 && this.unacknowledgedFrames.size === 0;
  }

  protected controlAckSnapshot(): string {
    const pending = Array.from(this.unacknowledgedFrames.keys());
    return `link=${this.started ? 'up' : 'down'} outstanding=${pending.length > 0 ? pending.join(',') : 'none'} ` +
      `queued=${this.outboundQueue.length} window=${this.peerMaxOutstanding} rxSeq=${this.lastReceivedSequence}`;
  }

}
