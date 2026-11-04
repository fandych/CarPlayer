import netSocket from '@ohos.net.socket';
import { hkdfSha512, sha512 } from '../AirPlayCrypto';
import { AirPlayEventChannel, AirPlayEventRequest } from '../AirPlayEventChannel';
import { AirPlayRtspClient, AirPlayRtspResponse } from '../AirPlayRtspClient';
import { BinaryPlist, PlistNode } from '../BinaryPlist';
import {
  AirPlayVideoEncryptionMode,
  AirPlayVideoStreamSender,
  EncodedH264Event
} from '../AirPlayVideoStream';
import { settleSocketWithin } from '../../network/SocketDeadline';
import {
  DEFAULT_TOUCH_HID_UUID,
  extractCarPlayTouchReport,
  findTouchHidDevice,
  scaleCarPlayTouchReport,
  TouchHidDevice
} from '../CarPlayTouchReport';
import { encodeUtf8, toArrayBuffer } from '../../protocol/Iap2Codec';
import { CARPLAY_SENDER_OS_BUILD_VERSION, CARPLAY_SENDER_SOURCE_VERSION } from '../../protocol/CarPlaySenderCompatibility';
import { AudioRtpSession, SAMPLES_PER_PACKET } from '../../audio/AudioRtpSender';
import { getSocketAddressFamily, WifiNetworkLease } from '../../network/WifiNetworkLease';
import { formatProtocolEvent, formatRawBytesDiagnostic } from '../../session/ProtocolLogger';
import { ProjectionDisplayMode } from '../../video/ProjectionSettings';
import { Iap2SenderSession } from '../../session/Iap2SenderSession';
import type { AirPlayModes } from '../AirPlayMediaSession';
import {
  AirPlayMediaSessionStatusError,
  AirPlayViewArea,
  createNtpTimestamp,
  createUuid,
  describeNetworkError,
  isForceKeyFrameCommand,
  normalizeDeviceId,
  parseIapSendMessagePayload,
  randomPositiveInt64,
  readAudioLatency,
  readDisplayInfo,
  readPort,
  readStringArray,
  requireDictionary,
  requireSuccess,
  selectPcmAudioFormat
} from './AirPlayMediaHelpers';

export abstract class AirPlayMediaSessionTransport {
  protected readonly client: AirPlayRtspClient;
  protected readonly receiverHost: string;
  protected readonly log: (message: string) => void;
  protected readonly onTransportDisconnected: (message: string) => void;
  protected readonly wifiNetworkLease: WifiNetworkLease;
  protected videoDataSocket?: netSocket.TCPSocket;
  protected videoSocketErrorHandler?: (error: Error) => void;
  protected videoSocketCloseHandler?: () => void;
  protected videoStreamSender?: AirPlayVideoStreamSender;
  protected videoWriteQueue: Promise<void> = Promise.resolve();
  protected videoWriteFailed: boolean = false;
  protected timingRequestsReceived: number = 0;
  protected lowPowerKeepAlivesSent: number = 0;
  protected forceKeyFrameHandler?: () => void;
  protected touchReportHandler?: (report: Uint8Array) => void;
  protected nightModeHandler?: (night: boolean) => void;
  protected nightMode: boolean = false;
  protected modes: AirPlayModes = {
    screenEntity: 1,
    screenPermanentEntity: 1,
    audioEntity: 1,
    audioPermanentEntity: 1,
    speechEntity: 0,
    speechMode: -1,
    phoneCallEntity: 0,
    turnByTurnEntity: 0
  };
  protected touchHid?: TouchHidDevice;
  protected videoWidth: number = 0;
  protected videoHeight: number = 0;
  protected videoKeepAliveTimer: number = -1;
  protected videoKeepAlivePending: boolean = false;
  protected timingSocket?: netSocket.UDPSocket;
  protected timingHandler?: (info: netSocket.SocketMessageInfo) => void;
  protected keepAliveSocket?: netSocket.UDPSocket;
  protected eventChannel?: AirPlayEventChannel;
  protected virtualIap2Session?: Iap2SenderSession;
  protected keepAliveTimer: number = -1;
  protected feedbackTimer: number = -1;
  protected feedbackPending: boolean = false;
  protected feedbackEnabled: boolean = true;
  protected running: boolean = false;
  protected recorded: boolean = false;

  protected abstract createTimingResponse(request: Uint8Array, nowMillis: number): Uint8Array | undefined;
  protected abstract createVideoKeepAliveFrame(nowMillis: number): Uint8Array;
  protected abstract createAudioSetupPayload(connectionId: bigint, formatBit: bigint, latencyMs: number): Uint8Array;
  protected abstract applyModeChanges(modes: AirPlayModes, params: PlistNode | undefined): AirPlayModes;
  protected abstract createModesDictionary(modes: AirPlayModes): PlistNode;
  protected abstract createModesChangedPayload(modes: AirPlayModes): Uint8Array;
  protected abstract createLowPowerKeepAliveBeacon(): Uint8Array;

  constructor(
    client: AirPlayRtspClient,
    receiverHost: string,
    log: (message: string) => void,
    onTransportDisconnected: (message: string) => void,
    wifiNetworkLease: WifiNetworkLease
  ) {
    this.client = client;
    this.receiverHost = receiverHost;
    this.log = log;
    this.onTransportDisconnected = onTransportDisconnected;
    this.wifiNetworkLease = wifiNetworkLease;
  }
  protected ensureRunning(): void {
    if (!this.running) {
      throw new Error('AirPlay media session startup was cancelled');
    }
  }

  protected async startTimingServer(): Promise<number> {
    const socket = netSocket.constructUDPSocketInstance();
    const handler = (info: netSocket.SocketMessageInfo): void => {
      const request = new Uint8Array(info.message);
      this.log(formatRawBytesDiagnostic('RX', 'AirPlay timing UDP', request, 64));
      const response = this.createTimingResponse(request, Date.now());
      if (!response) {
        this.log(formatProtocolEvent('airplay.timing.request.invalid',
          'bytes', request.length,
          'source', `${info.remoteInfo.address}:${info.remoteInfo.port}`,
          'meaning', '长度或类型不符合 AirPlay timing 请求格式，未发送响应'
        ));
        return;
      }
      const requestNumber = ++this.timingRequestsReceived;
      this.log(formatProtocolEvent('airplay.timing.request',
        'packet', requestNumber,
        'bytes', request.length,
        'source', `${info.remoteInfo.address}:${info.remoteInfo.port}`,
        'meaning', '请求本机时钟时间；已构造对应 NTP 时间戳响应'
      ));

      const options: netSocket.UDPSendOptions = {
        data: toArrayBuffer(response),
        address: { address: info.remoteInfo.address, port: info.remoteInfo.port }
      };
      void socket.send(options).then((): void => {
        this.log(formatRawBytesDiagnostic('TX', 'AirPlay timing UDP', response, 64));
        this.log(formatProtocolEvent('airplay.timing.response',
          'requestPacket', requestNumber,
          'bytes', response.length,
          'destination', `${info.remoteInfo.address}:${info.remoteInfo.port}`,
          'meaning', '发送时钟响应，供对端校准 RTP 播放时间'
        ));
      }).catch((error: Error): void => {
        this.log(formatProtocolEvent('airplay.timing.response.failure',
          'requestPacket', requestNumber,
          'error', describeNetworkError(error),
          'meaning', '时钟响应未能通过 UDP socket 发送'
        ));
      });
    };
    try {
      socket.on('message', handler);
      const boundToCarWifi = await this.wifiNetworkLease.bindSocket(
        socket, 'AirPlay timing UDP', getSocketAddressFamily(this.receiverHost));
      this.log(boundToCarWifi ? 'AirPlay timing UDP socket 已绑定指定车机 Wi-Fi 网络' :
        'AirPlay timing UDP socket 使用系统默认网络路由');
      const localAddress = await socket.getLocalAddress();
      const localPort = localAddress.port;
      if (typeof localPort !== 'number' || localPort < 1) {
        throw new Error('System did not allocate a timing UDP port');
      }
      this.timingSocket = socket;
      this.timingHandler = handler;
      return localPort;
    } catch (error) {
      try {
        socket.off('message', handler);
      } catch (cleanupError) {
        this.log(`AirPlay timing listener cleanup failed: ${cleanupError instanceof Error ?
          cleanupError.message : String(cleanupError)}`);
      }
      try {
        await socket.close();
      } catch (cleanupError) {
        this.log(`AirPlay timing socket cleanup failed: ${cleanupError instanceof Error ?
          cleanupError.message : String(cleanupError)}`);
      }
      throw new Error(`Unable to start AirPlay timing service: ${error instanceof Error ? error.message : String(error)}`);
    }
  }

  protected async openVideoDataPort(port: number): Promise<void> {
    const socket = netSocket.constructTCPSocketInstance();
    const errorHandler = (error: Error): void => {
      this.reportVideoSocketFailure(socket, `socket error: ${describeNetworkError(error)}`);
    };
    const closeHandler = (): void => {
      this.reportVideoSocketFailure(socket, 'socket closed by peer');
    };
    this.videoDataSocket = socket;
    this.videoSocketErrorHandler = errorHandler;
    this.videoSocketCloseHandler = closeHandler;
    socket.on('error', errorHandler);
    socket.on('close', closeHandler);
    try {
      if (await this.wifiNetworkLease.bindSocket(
        socket, 'AirPlay video TCP', getSocketAddressFamily(this.receiverHost))) {
        this.log('AirPlay video TCP socket 已绑定指定车机 Wi-Fi 网络');
      }
      await socket.connect({
        address: { address: this.receiverHost, port },
        timeout: 5000
      });
      this.log(`AirPlay screen data TCP connected: ${this.receiverHost}:${port}`);
    } catch (error) {
      if (this.videoDataSocket === socket) {
        this.videoDataSocket = undefined;
      }
      this.videoSocketErrorHandler = undefined;
      this.videoSocketCloseHandler = undefined;
      try {
        socket.off('error', errorHandler);
        socket.off('close', closeHandler);
      } catch (_cleanupError) {
      }
      try {
        await socket.close();
      } catch (cleanupError) {
        this.log(`AirPlay screen TCP cleanup failed: ${cleanupError instanceof Error ?
          cleanupError.message : String(cleanupError)}`);
      }
      throw new Error(`Unable to connect screen data port: ${error instanceof Error ? error.message : String(error)}`);
    }
  }

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

  setNightModeHandler(handler: ((night: boolean) => void) | undefined): void {
    this.nightModeHandler = handler;
    handler?.(this.nightMode);
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

  protected handleChangeModes(request: AirPlayEventRequest, params: PlistNode | undefined): void {
    this.modes = this.applyModeChanges(this.modes, params);
    request.responseBody = BinaryPlist.encode(PlistNode.dictionary(new Map<string, PlistNode>([
      ['status', PlistNode.integer(0)],
      ['params', this.createModesDictionary(this.modes)]
    ])));
    this.log(`AirPlay changeModes granted: screen=${this.modes.screenEntity}, audio=${this.modes.audioEntity}, ` +
      `speech=${this.modes.speechMode}, call=${this.modes.phoneCallEntity}, nav=${this.modes.turnByTurnEntity}`);
    const payload = this.createModesChangedPayload(this.modes);
    void this.client.request('POST', '/command', payload, { contentType: 'application/x-apple-binary-plist' })
      .then((response: AirPlayRtspResponse): void => {
        if (response.statusCode !== 200) {
          this.log(`AirPlay modesChanged rejected: ${response.statusLine}`);
        }
      })
      .catch((error: Error): void => this.log(`AirPlay modesChanged failed: ${error.message}`));
  }

  protected handleEventRequest(request: AirPlayEventRequest): boolean {
    let commandSummary = '';
    if (request.body.length > 0) {
      try {
        const command = BinaryPlist.decode(request.body);
        if (command.kind === 'dictionary') {
          commandSummary = ` fields=${Array.from(command.dictionaryValue.keys()).join(',')}`;
          const touchReport = extractCarPlayTouchReport(command, this.touchHid?.uuid);
          if (request.method === 'POST' && request.target === '/command' && touchReport) {
            const device = this.touchHid;
            this.touchReportHandler?.(device ?
              scaleCarPlayTouchReport(touchReport, device, this.videoWidth, this.videoHeight) : touchReport);
          }
          const type = command.get('type');
          if (request.method === 'POST' && request.target === '/command' &&
            type?.kind === 'string' && type.stringValue === 'changeModes') {
            this.handleChangeModes(request, command.get('params'));
          }
          if (request.method === 'POST' && request.target === '/command' &&
            type?.kind === 'string' && type.stringValue === 'iAPSendMessage') {
            const bytes = parseIapSendMessagePayload(command);
            const session = this.virtualIap2Session;
            if (session && bytes) {
              void session.receive(bytes).catch((error: Error): void => {
                if (this.virtualIap2Session !== session) {
                  return;
                }
                this.log(`MIB3 virtual iAP2 receive failed: ${error.message}`);
                session.cancel();
                this.virtualIap2Session = undefined;
              });
            }
          }
          if (request.method === 'POST' && request.target === '/command' &&
            type?.kind === 'string' && type.stringValue === 'setNightMode') {
            const night = command.get('params')?.get('nightMode');
            if (night?.kind !== 'boolean') {
              throw new Error('setNightMode requires params.nightMode Boolean');
            }
            this.nightMode = night.boolValue;
            this.nightModeHandler?.(this.nightMode);
          }
          if (request.method === 'POST' && request.target === '/command' &&
            type?.kind === 'string' && type.stringValue === 'hidSendReport') {
            return true;
          }
          if (request.method === 'POST' && request.target === '/command' && isForceKeyFrameCommand(command)) {
            this.log('AirPlay receiver requested an immediate H.264 key frame');
            this.forceKeyFrameHandler?.();
          }
        }
      } catch (error) {
        commandSummary = ` plistError=${error instanceof Error ? error.message : String(error)}`;
      }
    }
    this.log(
      `AirPlay event ${request.method} ${request.target} cseq=${request.cseq} body=${request.body.length}B${commandSummary}`
    );
    return false;
  }

  protected async startKeepAlive(port: number): Promise<void> {
    if (port === 0) {
      this.log('Receiver did not advertise a keep-alive UDP port');
      return;
    }
    const socket = netSocket.constructUDPSocketInstance();
    try {
      const boundToCarWifi = await this.wifiNetworkLease.bindSocket(
        socket, 'AirPlay keep-alive UDP', getSocketAddressFamily(this.receiverHost));
      this.log(boundToCarWifi ? 'AirPlay keep-alive UDP socket 已绑定指定车机 Wi-Fi 网络' :
        'AirPlay keep-alive UDP socket 使用系统默认网络路由');
      this.keepAliveSocket = socket;
      this.keepAliveTimer = setInterval((): void => {
        void this.sendKeepAlive(port).catch((error: Error): void => {
          this.log(`AirPlay UDP keep-alive failed: ${error.message}`);
        });
      }, 5000);
      await this.sendKeepAlive(port);
    } catch (error) {
      try {
        await socket.close();
      } catch (cleanupError) {
        this.log(`AirPlay keep-alive socket cleanup failed: ${cleanupError instanceof Error ?
          cleanupError.message : String(cleanupError)}`);
      }
      this.keepAliveSocket = undefined;
      throw new Error(`Unable to start AirPlay keep-alive: ${error instanceof Error ? error.message : String(error)}`);
    }
  }

  protected async sendKeepAlive(port: number): Promise<void> {
    const socket = this.keepAliveSocket;
    if (!socket || !this.running) {
      return;
    }
    const beacon = this.createLowPowerKeepAliveBeacon();
    const options: netSocket.UDPSendOptions = {
      data: toArrayBuffer(beacon),
      address: { address: this.receiverHost, port }
    };
    await socket.send(options);
    const packetNumber = ++this.lowPowerKeepAlivesSent;
    this.log(formatRawBytesDiagnostic('TX', 'AirPlay low-power keep-alive UDP', beacon, 64));
    this.log(formatProtocolEvent('airplay.keep_alive.tx',
      'packet', packetNumber,
      'destination', `${this.receiverHost}:${port}`,
      'bytes', beacon.length,
      'meaning', '向接收端发送低功耗会话保活信标，避免控制会话因空闲被回收'
    ));
  }

  protected startFeedbackLoop(): void {
    const run = async (): Promise<void> => {
      this.feedbackTimer = -1;
      if (!this.running || this.feedbackPending) {
        return;
      }
      this.feedbackPending = true;
      try {
        const response = await this.client.request(
          'POST',
          '/feedback',
          new Uint8Array(0),
          { contentType: 'application/x-apple-binary-plist' }
        );
        if (response.statusCode !== 200) {
          this.log(`AirPlay feedback returned ${response.statusLine}`);
          this.feedbackEnabled = false;
        }
      } catch (error) {
        this.log(`AirPlay feedback failed: ${error instanceof Error ? error.message : String(error)}`);
        this.feedbackEnabled = false;
      } finally {
        this.feedbackPending = false;
        if (this.running && this.feedbackEnabled) {
          this.feedbackTimer = setTimeout((): void => {
            void run();
          }, 1000);
        }
      }
    };
    this.feedbackTimer = setTimeout((): void => {
      void run();
    }, 1000);
  }

  protected async request(method: string, path: string, body: Uint8Array, label: string):
    Promise<AirPlayRtspResponse> {
    const response = await this.client.request(method, path, body, {
      contentType: 'application/x-apple-binary-plist'
    });
    requireSuccess(response, label);
    return response;
  }}
