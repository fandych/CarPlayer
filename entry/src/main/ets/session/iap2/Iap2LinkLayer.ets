import {
  concatBytes,
  encodeIap2Control,
  encodeIap2LinkFrame,
  formatIap2MessageDiagnostic,
  formatIap2RawFrameDiagnostic,
  Iap2ControlDecoder,
  Iap2LinkDecoder,
  Iap2LinkFrame
} from '../../protocol/Iap2Codec';
import {
  formatIap2FrameInterpretation,
  LINK_MARKER
} from './Iap2SessionProtocol';

export abstract class Iap2LinkLayer {
  protected readonly linkDecoder: Iap2LinkDecoder = new Iap2LinkDecoder();
  protected controlDecoder: Iap2ControlDecoder = new Iap2ControlDecoder();
  protected readonly sendBytes: (bytes: Uint8Array) => Promise<void>;
  protected readonly log: (message: string) => void;
  protected receiveQueue: Promise<void> = Promise.resolve();
  protected nextSequence: number = 99;
  protected readonly unacknowledgedFrames: Map<number, Iap2LinkFrame> = new Map();
  protected readonly outOfOrderFrames: Map<number, Iap2LinkFrame> = new Map();
  protected lastReceivedSequence: number = 0;
  protected controlSessionId: number = 10;
  protected started: boolean = false;
  protected sessionGeneration: number = 0;
  protected identificationRequested: boolean = false;
  protected peerSyncSequence?: number;
  protected peerSyncResponse?: Iap2LinkFrame;
  protected peerMaxOutstanding: number = 1;
  protected peerMaxPacketLength: number = 1024;
  protected peerRetransmitTimeoutMs: number = 1500;
  protected peerMaxRetransmissions: number = 3;
  protected readonly outboundQueue: Iap2LinkFrame[] = [];
  protected readonly retransmitCounts: Map<number, number> = new Map();
  protected retransmitTimer?: number;
  protected detectionRetryTimer?: number;
  protected identificationTimer?: number;

  constructor(sendBytes: (bytes: Uint8Array) => Promise<void>, log: (message: string) => void) {
    this.sendBytes = sendBytes;
    this.log = log;
  }

  protected abstract onControlMessageReceived(messageId: number, body: Uint8Array): Promise<void>;
  protected abstract onIdentificationRequested(): Promise<void>;
  protected abstract onLinkResetDiagnostic(): void;
  protected abstract onBuickRetransmissionFailure(): boolean;
  protected abstract onFrameSentWhileBuickWaiting(): boolean;
  protected abstract getBuickAvailabilityFrameDigest(): string;
  protected abstract cancel(): void;

  protected async receiveLinkFrame(frame: Iap2LinkFrame): Promise<void> {
    this.log(formatIap2RawFrameDiagnostic('RX', frame));
    this.log(formatIap2FrameInterpretation('RX', frame));
    if ((frame.control & 0x10) !== 0) {
      this.onLinkResetDiagnostic();
      this.cancel();
      throw new Error('车机发送 iAP2 链路复位，已终止当前认证会话');
    }
    if ((frame.control & 0x80) !== 0 && frame.payload.length >= 10) {
      if (this.identificationRequested && this.peerSyncSequence === frame.sequence) {
        if ((frame.control & 0x40) === 0 && this.peerSyncResponse) {
          await this.sendLinkFrame(this.peerSyncResponse);
        }
        this.log(`收到重复 iAP2 SYN：seq=${frame.sequence}，保持现有协商状态`);
        return;
      }
      const peerControlSession = this.readControlSessionId(frame.payload);
      if (peerControlSession === undefined) {
        throw new Error('iAP2 同步包没有声明控制会话，无法发送 IDENTIFICATION_START');
      }
      this.lastReceivedSequence = frame.sequence;
      this.controlSessionId = peerControlSession;
      this.peerSyncSequence = frame.sequence;
      this.applyPeerLinkParameters(frame.payload);
      if (this.detectionRetryTimer !== undefined) {
        clearTimeout(this.detectionRetryTimer);
        this.detectionRetryTimer = undefined;
      }
      const isSynAck = (frame.control & 0x40) !== 0;
      if (isSynAck) {
        this.log(`收到 iAP2 SYN-ACK，控制会话 ${this.controlSessionId}`);
      } else {
        const acknowledgement: Iap2LinkFrame = {
          control: 0xc0,
          sequence: this.takeSequence(),
          acknowledgement: frame.sequence,
          sessionId: 0,
          payload: frame.payload.slice()
        };
        this.peerSyncResponse = acknowledgement;
        await this.sendLinkFrame(acknowledgement);
        this.log(`收到 iAP2 同步包，控制会话 ${this.controlSessionId}`);
      }
      if (!this.identificationRequested) {
        this.identificationRequested = true;
        await this.onIdentificationRequested();
      }
      return;
    }
    if ((frame.control & 0x40) !== 0) {
      for (const sequence of Array.from(this.unacknowledgedFrames.keys())) {
        const distance = (frame.acknowledgement - sequence + 256) & 0xff;
        if (distance < 128) {
          this.unacknowledgedFrames.delete(sequence);
          this.retransmitCounts.delete(sequence);
        }
      }
      if (this.unacknowledgedFrames.size === 0) {
        this.clearRetransmitTimer();
      }
      await this.transmitPending();
    }
    if ((frame.control & 0x20) !== 0) {
      this.log(`收到 iAP2 EAK，acknowledgement=${frame.acknowledgement}，selectiveAckBytes=${frame.payload.length}`);
      for (const sequence of frame.payload) {
        const pending = this.unacknowledgedFrames.get(sequence);
        if (pending) {
          this.log(`按 EAK 重发 iAP2 序号 ${sequence}`);
          await this.sendLinkFrame({
            control: pending.control,
            sequence: pending.sequence,
            acknowledgement: this.lastReceivedSequence,
            sessionId: pending.sessionId,
            payload: pending.payload
          });
        }
      }
      return;
    }
    if ((frame.control & 0x40) === 0 || frame.payload.length === 0) {
      return;
    }
    const distance = (frame.sequence - this.lastReceivedSequence + 256) & 0xff;
    if (distance === 0 || distance >= 128) {
      await this.sendLinkFrame({
        control: 0x40,
        sequence: (this.nextSequence - 1) & 0xff,
        acknowledgement: this.lastReceivedSequence,
        sessionId: 0,
        payload: new Uint8Array(0)
      });
      return;
    }
    if (distance > 1) {
      if (distance > 16 || this.outOfOrderFrames.size >= 16) {
        throw new Error('iAP2 乱序帧超过接收窗口');
      }
      this.outOfOrderFrames.set(frame.sequence, frame);
      const missing: number[] = [];
      for (let offset = 1; offset < distance; offset++) {
        const sequence = (this.lastReceivedSequence + offset) & 0xff;
        if (!this.outOfOrderFrames.has(sequence)) {
          missing.push(sequence);
        }
      }
      await this.sendLinkFrame({
        control: 0x60,
        sequence: (this.nextSequence - 1) & 0xff,
        acknowledgement: this.lastReceivedSequence,
        sessionId: 0,
        payload: new Uint8Array(missing)
      });
      return;
    }
    let current: Iap2LinkFrame | undefined = frame;
    while (current) {
      this.lastReceivedSequence = current.sequence;
      await this.acceptDataFrame(current);
      const next = (this.lastReceivedSequence + 1) & 0xff;
      current = this.outOfOrderFrames.get(next);
      this.outOfOrderFrames.delete(next);
    }
  }

  private async acceptDataFrame(frame: Iap2LinkFrame): Promise<void> {
    const acknowledgement: Iap2LinkFrame = {
      control: 0x40,
      sequence: (this.nextSequence - 1) & 0xff,
      acknowledgement: frame.sequence,
      sessionId: 0,
      payload: new Uint8Array(0)
    };
    await this.sendLinkFrame(acknowledgement);
    if (frame.sessionId !== this.controlSessionId) {
      this.log(`忽略非控制会话 ${frame.sessionId} 上的 iAP2 数据`);
      return;
    }
    for (const message of this.controlDecoder.push(frame.payload)) {
      await this.onControlMessageReceived(message.messageId, message.body);
    }
  }

  protected readControlSessionId(payload: Uint8Array): number | undefined {
    for (let offset = 10; offset + 2 < payload.length; offset += 3) {
      const sessionId = payload[offset];
      const sessionKind = payload[offset + 1];
      if (sessionId !== undefined && sessionId > 0 && sessionKind === 0) {
        return sessionId;
      }
    }
    return undefined;
  }

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

  private async transmitPending(): Promise<void> {
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

  private applyPeerLinkParameters(payload: Uint8Array): void {
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
