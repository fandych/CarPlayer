import {
  formatIap2RawFrameDiagnostic,
  Iap2ControlDecoder,
  Iap2LinkDecoder,
  Iap2LinkFrame
} from '../../protocol/Iap2Codec';
import {
  formatIap2FrameInterpretation
} from './Iap2SessionProtocol';
export abstract class Iap2LinkLayerReceive {
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
  protected peerSyncPayload?: Uint8Array;
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
  protected abstract restartSessionForNewPeerSync(): Promise<void>;
  protected abstract onLinkResetDiagnostic(): void;
  protected abstract onBuickRetransmissionFailure(): boolean;
  protected abstract onFrameSentWhileBuickWaiting(): boolean;
  protected abstract getBuickAvailabilityFrameDigest(): string;
  protected abstract cancel(): void;

  protected abstract sendLinkFrame(frame: Iap2LinkFrame, includeMarker?: boolean): Promise<void>;
  protected abstract transmitPending(): Promise<void>;
  protected abstract takeSequence(): number;
  protected abstract applyPeerLinkParameters(payload: Uint8Array): void;
  protected abstract clearRetransmitTimer(): void;

  protected async receiveLinkFrame(frame: Iap2LinkFrame): Promise<void> {
    this.log(formatIap2RawFrameDiagnostic('RX', frame));
    this.log(formatIap2FrameInterpretation('RX', frame));
    if ((frame.control & 0x10) !== 0) {
      this.onLinkResetDiagnostic();
      this.cancel();
      throw new Error('车机发送 iAP2 链路复位，已终止当前认证会话');
    }
    if ((frame.control & 0x80) !== 0 && frame.payload.length >= 10) {
      const sameSyncPayload = this.peerSyncPayload !== undefined &&
        this.peerSyncPayload.length === frame.payload.length &&
        this.peerSyncPayload.every((value: number, index: number): boolean => value === frame.payload[index]);
      if (this.identificationRequested && this.peerSyncSequence === frame.sequence &&
        this.lastReceivedSequence === frame.sequence && sameSyncPayload) {
        if ((frame.control & 0x40) === 0 && this.peerSyncResponse) {
          await this.sendLinkFrame(this.peerSyncResponse);
        }
        this.log(`收到重复 iAP2 SYN：seq=${frame.sequence}，保持现有协商状态`);
        if (this.identificationTimer !== undefined) {
          await this.onIdentificationRequested();
        }
        return;
      }
      if (this.identificationRequested) {
        this.log(`收到新的 iAP2 SYN：seq=${frame.sequence}；清理旧协商状态并重新开始识别`);
        await this.restartSessionForNewPeerSync();
      }
      const peerControlSession = this.readControlSessionId(frame.payload);
      if (peerControlSession === undefined) {
        throw new Error('iAP2 同步包没有声明控制会话，无法发送 IDENTIFICATION_START');
      }
      this.lastReceivedSequence = frame.sequence;
      this.controlSessionId = peerControlSession;
      this.peerSyncSequence = frame.sequence;
      this.peerSyncPayload = frame.payload.slice();
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
    if (!this.identificationRequested && this.peerSyncSequence === undefined &&
      (frame.control & 0x40) !== 0 && (frame.control & 0x20) === 0 &&
      frame.sessionId > 0 && frame.payload.length >= 6 &&
      frame.payload[0] === 0x40 && frame.payload[1] === 0x40) {
      this.controlSessionId = frame.sessionId;
      this.lastReceivedSequence = (frame.sequence - 1 + 256) & 0xff;
      this.identificationRequested = true;
      if (this.detectionRetryTimer !== undefined) {
        clearTimeout(this.detectionRetryTimer);
        this.detectionRetryTimer = undefined;
      }
      this.log(
        `未收到 SYN 即收到 iAP2 控制数据；按 CSM 会话 ${frame.sessionId}、序号 ${frame.sequence} 恢复接收`
      );
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

  protected resetLinkSessionState(): void {
    if (this.detectionRetryTimer !== undefined) {
      clearTimeout(this.detectionRetryTimer);
      this.detectionRetryTimer = undefined;
    }
    this.clearRetransmitTimer();
    this.controlDecoder = new Iap2ControlDecoder();
    this.nextSequence = 99;
    this.lastReceivedSequence = 0;
    this.controlSessionId = 10;
    this.identificationRequested = false;
    this.peerSyncSequence = undefined;
    this.peerSyncPayload = undefined;
    this.peerSyncResponse = undefined;
    this.peerMaxOutstanding = 1;
    this.peerMaxPacketLength = 1024;
    this.peerRetransmitTimeoutMs = 1500;
    this.peerMaxRetransmissions = 3;
    this.unacknowledgedFrames.clear();
    this.outOfOrderFrames.clear();
    this.outboundQueue.length = 0;
    this.retransmitCounts.clear();
  }

}
