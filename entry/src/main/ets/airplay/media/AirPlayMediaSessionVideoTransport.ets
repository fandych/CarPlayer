import netSocket from '@ohos.net.socket';
import { hkdfSha512 } from '../AirPlayCrypto';
import { EncodedH264Event } from '../AirPlayVideoStream';
import { PlistNode } from '../BinaryPlist';
import { encodeUtf8, toArrayBuffer } from '../../protocol/Iap2Codec';
import { AudioRtpSession } from '../../audio/AudioRtpSender';
import { AirPlayMediaSessionTransportBase } from './AirPlayMediaSessionTransportBase';
import {
  describeNetworkError,
  randomPositiveInt64,
  readAudioLatency,
  readPort,
  requireDictionary,
  selectPcmAudioFormat
} from './AirPlayMediaHelpers';

export abstract class AirPlayMediaSessionVideoTransport extends AirPlayMediaSessionTransportBase {
  protected async sendVideoKeepAlive(): Promise<void> {
    const socket = this.videoDataSocket;
    if (!socket || !this.recorded || this.videoKeepAlivePending) {
      return;
    }
    const header = this.createVideoKeepAliveFrame(Date.now());
    this.videoKeepAlivePending = true;
    try {
      await this.enqueueVideoBytes(header);
    } finally {
      this.videoKeepAlivePending = false;
    }
  }

  async pushEncodedVideo(event: EncodedH264Event): Promise<void> {
    const sender = this.videoStreamSender;
    if (!sender || !this.running || !this.recorded) {
      throw new Error('AirPlay screen stream is not ready for encoded frames');
    }
    await sender.handleEncoderEvent(event);
  }

  setForceKeyFrameHandler(handler: (() => void) | undefined): void {
    this.forceKeyFrameHandler = handler;
  }

  setTouchReportHandler(handler: ((report: Uint8Array) => void) | undefined): void {
    this.touchReportHandler = handler;
  }

  protected reportVideoSocketFailure(socket: netSocket.TCPSocket, reason: string): void {
    if (this.videoDataSocket !== socket || !this.running || !this.recorded || this.videoWriteFailed) {
      return;
    }
    this.videoWriteFailed = true;
    this.log(`AirPlay screen data TCP ${reason}`);
    this.onTransportDisconnected(`AirPlay screen data TCP ${reason}`);
  }

  protected enqueueVideoBytes(data: Uint8Array): Promise<void> {
    const operation = this.videoWriteQueue.then(async (): Promise<void> => {
      if (!this.running || this.videoWriteFailed) {
        throw new Error('AirPlay screen stream is closed or failed');
      }
      const socket = this.videoDataSocket;
      if (!socket) {
        throw new Error('AirPlay screen data socket is closed');
      }
      const options: netSocket.TCPSendOptions = { data: toArrayBuffer(data) };
      try {
        await socket.send(options);
      } catch (error) {
        this.reportVideoSocketFailure(socket, `write failed: ${describeNetworkError(error)}`);
        throw error instanceof Error ? error : new Error(String(error));
      }
    });
    this.videoWriteQueue = operation.catch((error: Error): void => {
      this.log(`AirPlay screen stream send failed: ${error.message}`);
    });
    return operation;
  }

  protected async setupAudioStream(info: PlistNode, sharedSecret: Uint8Array): Promise<AudioRtpSession | undefined> {
    const format = selectPcmAudioFormat(info);
    if (!format) {
      this.log('Receiver /info has no supported PCM media-audio format; audio RTP will remain disabled');
      return undefined;
    }
    const connectionId = await randomPositiveInt64();
    const audioLatencyMs = readAudioLatency(info, format.sampleRate);
    const response = await this.request(
      'SETUP',
      '/',
      this.createAudioSetupPayload(connectionId, format.formatBit, audioLatencyMs),
      'audio stream SETUP'
    );
    const root = requireDictionary(response, 'audio stream SETUP');
    const streams = root.get('streams');
    if (!streams || streams.kind !== 'array') {
      throw new Error('Audio SETUP response has no streams array');
    }
    const audio = streams.arrayValue.find((item: PlistNode): boolean =>
      item.kind === 'dictionary' && item.get('type')?.integerValue === BigInt(100)
    );
    const dataPort = readPort(audio?.get('dataPort'));
    if (!audio || dataPort === 0) {
      throw new Error('Audio SETUP response has no type 100 data port');
    }
    const streamKey = await hkdfSha512(
      sharedSecret,
      encodeUtf8(`DataStream-Salt${connectionId.toString()}`),
      encodeUtf8('DataStream-Output-Encryption-Key')
    );
    this.log(`AirPlay PCM audio stream negotiated: ${format.sampleRate}Hz → UDP ${dataPort}`);
    return {
      host: this.receiverHost,
      dataPort,
      controlPort: readPort(audio.get('controlPort')),
      streamKey,
      sampleRate: format.sampleRate
    };
  }

}
