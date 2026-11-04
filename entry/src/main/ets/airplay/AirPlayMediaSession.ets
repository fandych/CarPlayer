import netSocket from '@ohos.net.socket';
import { AirPlayMediaSessionTransport } from './media/AirPlayMediaSessionTransport';
import { hkdfSha512, sha512 } from './AirPlayCrypto';
import { AirPlayEventChannel, AirPlayEventRequest } from './AirPlayEventChannel';
import { AirPlayRtspClient, AirPlayRtspResponse } from './AirPlayRtspClient';
import { BinaryPlist, PlistNode } from './BinaryPlist';
import {
  AirPlayVideoEncryptionMode,
  AirPlayVideoStreamSender,
  EncodedH264Event
} from './AirPlayVideoStream';
import { settleSocketWithin } from '../network/SocketDeadline';
import {
  DEFAULT_TOUCH_HID_UUID,
  extractCarPlayTouchReport,
  findTouchHidDevice,
  scaleCarPlayTouchReport,
  TouchHidDevice
} from './CarPlayTouchReport';
import { encodeUtf8, toArrayBuffer } from '../protocol/Iap2Codec';
import { CARPLAY_SENDER_OS_BUILD_VERSION, CARPLAY_SENDER_SOURCE_VERSION } from '../protocol/CarPlaySenderCompatibility';
import { AudioRtpSession, SAMPLES_PER_PACKET } from '../audio/AudioRtpSender';
import { getSocketAddressFamily, WifiNetworkLease } from '../network/WifiNetworkLease';
import { formatProtocolEvent, formatRawBytesDiagnostic } from '../session/ProtocolLogger';
import { ProjectionDisplayMode } from '../video/ProjectionSettings';
import { Iap2SenderSession } from '../session/Iap2SenderSession';
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
} from './media/AirPlayMediaHelpers';

export {
  AirPlayMediaSessionStatusError,
  AirPlayViewArea,
  PcmAudioFormat,
  isForceKeyFrameCommand,
  parseIapSendMessagePayload,
  selectPcmAudioFormat
} from './media/AirPlayMediaHelpers';

const CONTROLLER_FEATURES: string[] = [
  'uiContext',
  'viewAreas',
  'cornerMasks',
  'focusTransfer',
  'h.264Level5.1',
  'mainBuffered',
  'altScreen',
  'enhancedSiri',
  'hevc',
  'sessionManagement',
  'logTransfer',
  'iAPChannel',
  'vehicleStateProtocol',
  'videoPlayback'
];
const CARPLAY_SENDER_MAC_ADDRESS: string = 'aa:bb:cc:dd:ee:ff';
const MIB3_IAP2_DETECT_MARKER: Uint8Array = new Uint8Array([0xff, 0x55, 0x02, 0x00, 0xee, 0x10]);

export interface AirPlayMediaSessionInfo {
  eventPort: number;
  timingPort: number;
  keepAlivePort: number;
  enabledFeatures: string[];
  displayUuid: string;
  displayType: number;
  nativeDisplayWidth: number;
  nativeDisplayHeight: number;
  viewArea: AirPlayViewArea;
  displayModeId: string;
  availableDisplayModes: ProjectionDisplayMode[];
  resolutionMessage: string;
  displayWidth: number;
  displayHeight: number;
  maxFrameRate: number;
  videoDataPort: number;
  videoConnectionId: bigint;
  videoStreamKey: Uint8Array;
  audioSession: AudioRtpSession | undefined;
}

// Entities: 0 none, 1 controller (phone), 2 accessory (vehicle).
export interface AirPlayModes {
  screenEntity: number;
  screenPermanentEntity: number;
  audioEntity: number;
  audioPermanentEntity: number;
  speechEntity: number;
  speechMode: number;
  phoneCallEntity: number;
  turnByTurnEntity: number;
}

export function createDefaultModes(): AirPlayModes {
  return {
    screenEntity: 1,
    screenPermanentEntity: 1,
    audioEntity: 1,
    audioPermanentEntity: 1,
    speechEntity: 0,
    speechMode: -1,
    phoneCallEntity: 0,
    turnByTurnEntity: 0
  };
}

export class AirPlayMediaSession extends AirPlayMediaSessionTransport {
  protected createTimingResponse(request: Uint8Array, nowMillis: number): Uint8Array | undefined {
    return AirPlayMediaSession.buildTimingResponse(request, nowMillis);
  }

  protected createVideoKeepAliveFrame(nowMillis: number): Uint8Array {
    return AirPlayMediaSession.buildVideoKeepAliveFrame(nowMillis);
  }

  protected createAudioSetupPayload(connectionId: bigint, formatBit: bigint, latencyMs: number): Uint8Array {
    return AirPlayMediaSession.buildAudioSetupPayload(connectionId, formatBit, latencyMs);
  }

  protected applyModeChanges(modes: AirPlayModes, params: PlistNode | undefined): AirPlayModes {
    return AirPlayMediaSession.applyChangeModes(modes, params);
  }

  protected createModesDictionary(modes: AirPlayModes): PlistNode {
    return AirPlayMediaSession.buildModesDictionary(modes);
  }

  protected createModesChangedPayload(modes: AirPlayModes): Uint8Array {
    return AirPlayMediaSession.buildModesChangedPayload(modes);
  }

  protected createLowPowerKeepAliveBeacon(): Uint8Array {
    return AirPlayMediaSession.buildLowPowerKeepAliveBeacon();
  }

  async start(
    deviceId: string,
    sharedSecret?: Uint8Array,
    mib3VirtualLink: boolean = false,
    virtualIap2Session?: Iap2SenderSession
  ):
    Promise<AirPlayMediaSessionInfo> {
    if (this.running) {
      throw new Error('AirPlay media session is already active');
    }
    if (sharedSecret?.length === 0) {
      throw new Error('AirPlay shared secret is empty');
    }
    const paired = sharedSecret !== undefined;
    const mediaSessionKey = sharedSecret ?? new Uint8Array(16);
    const normalizedDeviceId = normalizeDeviceId(deviceId);
    const sessionUuid = createUuid().toUpperCase();
    const sessionCorrelationUuid = createUuid().toUpperCase();
    this.running = true;
    this.videoWriteFailed = false;
    this.timingRequestsReceived = 0;
    this.lowPowerKeepAlivesSent = 0;
    this.timingRequestsReceived = 0;
    this.lowPowerKeepAlivesSent = 0;
    try {
      const timingPort = await this.startTimingServer();
      this.ensureRunning();
      const initialSetup = await this.request(
        'SETUP',
        '/setup',
        AirPlayMediaSession.buildSessionSetupPayload(
          normalizedDeviceId, timingPort, !paired, sessionUuid, sessionCorrelationUuid
        ),
        'initial session SETUP'
      );
      this.ensureRunning();
      const initialResponse = requireDictionary(initialSetup, 'initial session SETUP');
      const enabledFeatures = readStringArray(initialResponse.get('enabledFeatures'));
      const keepAlivePort = readPort(initialResponse.get('keepAlivePort'));
      const infoResponse = await this.request(
        'GET',
        '/info',
        BinaryPlist.encode(PlistNode.dictionary(new Map<string, PlistNode>())),
        'receiver /info after initial session SETUP'
      );
      this.ensureRunning();
      const info = requireDictionary(infoResponse, 'receiver /info');
      const display = readDisplayInfo(info);
      const displayUuid = display.uuid;
      this.videoWidth = display.width;
      this.videoHeight = display.height;
      this.log(
        `AirPlay display profile: type=${display.displayType}, ` +
          `nativeCanvas=${display.nativeWidth}x${display.nativeHeight}, ` +
          `encoderCanvas=${display.width}x${display.height}, ` +
          `activeViewArea=${display.viewArea.width}x${display.viewArea.height}` +
          `@${display.viewArea.originX},${display.viewArea.originY}`
      );
      const touchHid = findTouchHidDevice(info, displayUuid);
      this.touchHid = touchHid ?? {
        uuid: DEFAULT_TOUCH_HID_UUID,
        logicalMaxX: display.sourceWidth - 1,
        logicalMaxY: display.sourceHeight - 1
      };
      this.log(`AirPlay touch HID uuid=${this.touchHid.uuid} logical=${this.touchHid.logicalMaxX}x` +
        `${this.touchHid.logicalMaxY} video=${display.width}x${display.height}`);
      if (display.resolutionMessage.length > 0) {
        this.log(display.resolutionMessage);
      }
      if (!enabledFeatures.includes('videoPlayback')) {
        this.log(
          `Receiver SETUP did not advertise videoPlayback (${enabledFeatures.join(', ') || 'no features'}); ` +
            'continuing to the video stream SETUP to verify actual support'
        );
      }
      const eventPort = readPort(initialResponse.get('eventPort'));
      this.ensureRunning();
      await this.request(
        'POST',
        '/command',
        AirPlayMediaSession.buildModesChangedPayload(),
        'modesChanged resource declaration'
      );
      this.ensureRunning();
      const videoConnectionId = await randomPositiveInt64();
      const videoSetup = await this.request(
        'SETUP',
        '/',
        AirPlayMediaSession.buildVideoSetupPayload(displayUuid, videoConnectionId),
        'video stream SETUP'
      );
      this.ensureRunning();
      const videoResponse = requireDictionary(videoSetup, 'video stream SETUP');
      const streams = videoResponse.get('streams');
      if (!streams || streams.kind !== 'array' || streams.arrayValue.length === 0) {
        throw new Error('Video SETUP response has no streams array');
      }
      const stream = streams.arrayValue.find((item: PlistNode): boolean =>
        item.kind === 'dictionary' && item.get('type')?.integerValue === BigInt(110)
      );
      if (!stream) {
        throw new Error('Video SETUP response has no type 110 screen stream');
      }
      const videoDataPort = readPort(stream.get('dataPort'));
      if (videoDataPort === 0) {
        throw new Error('Video SETUP response did not include a valid data port');
      }
      if (mib3VirtualLink && paired) {
        await this.request(
          'POST',
          '/command',
          AirPlayMediaSession.buildIapSendMessagePayload(MIB3_IAP2_DETECT_MARKER),
          'MIB3 virtual iAP2 DETECT'
        );
        this.ensureRunning();
        if (!virtualIap2Session) {
          throw new Error('MIB3 virtual iAP2 link engine is unavailable');
        }
        virtualIap2Session.setMib3WirelessSessionUuid(sessionUuid);
        await virtualIap2Session.start(false);
        this.virtualIap2Session = virtualIap2Session;
      }
      await this.openVideoDataPort(videoDataPort);
      this.ensureRunning();
      if (eventPort > 0) {
        const eventChannel = new AirPlayEventChannel(
          (message: string): void => this.log(message),
          (request: AirPlayEventRequest): boolean => this.handleEventRequest(request),
          this.wifiNetworkLease
        );
        this.eventChannel = eventChannel;
        try {
          await eventChannel.connect(this.receiverHost, eventPort, sharedSecret);
        } catch (error) {
          this.log(`AirPlay event channel unavailable: ${error instanceof Error ? error.message : String(error)}`);
          this.eventChannel = undefined;
          await eventChannel.close();
          if (mib3VirtualLink && paired) {
            throw new Error(
              `MIB3 virtual iAP2 event channel unavailable: ${error instanceof Error ? error.message : String(error)}`
            );
          }
        }
      } else {
        this.log('Receiver did not provide an event port before resource claim');
        if (mib3VirtualLink && paired) {
          throw new Error('MIB3 virtual iAP2 requires an AirPlay event channel');
        }
      }
      const eventChannel = this.eventChannel;
      if (touchHid && eventChannel) {
        try {
          await eventChannel.sendCommand(AirPlayMediaSession.buildHidSetInputModePayload(touchHid.uuid));
          this.ensureRunning();
          this.log(`AirPlay touch HID input mode armed: uuid=${touchHid.uuid}, mode=0`);
        } catch (error) {
          this.ensureRunning();
          this.log(`AirPlay touch HID input mode unavailable: ${error instanceof Error ? error.message : String(error)}`);
        }
      }
      await this.startKeepAlive(keepAlivePort);
      this.ensureRunning();
      this.startFeedbackLoop();
      const record = await this.request(
        'RECORD',
        '/',
        BinaryPlist.encode(PlistNode.dictionary(new Map<string, PlistNode>())),
        'RECORD'
      );
      this.ensureRunning();
      requireSuccess(record, 'RECORD');
      this.recorded = true;
      await this.sendVideoKeepAlive();
      this.ensureRunning();
      this.videoKeepAliveTimer = setInterval((): void => {
        void this.sendVideoKeepAlive().catch((error: Error): void => {
          this.log(`AirPlay screen keep-alive failed: ${error.message}`);
          if (this.videoKeepAliveTimer >= 0) {
            clearInterval(this.videoKeepAliveTimer);
            this.videoKeepAliveTimer = -1;
          }
        });
      }, 1000);
      const connectionIdText = videoConnectionId.toString();
      const videoEncryption = paired
        ? AirPlayVideoEncryptionMode.CHACHA20_POLY1305
        : AirPlayVideoEncryptionMode.AES_128_CTR;
      const videoStreamKey = paired
        ? await hkdfSha512(
          mediaSessionKey,
          encodeUtf8(`DataStream-Salt${connectionIdText}`),
          encodeUtf8('DataStream-Output-Encryption-Key')
        )
        : (await sha512(encodeUtf8(`AirPlayStreamKey${connectionIdText}`), mediaSessionKey)).slice(0, 16);
      const videoStreamIv = paired
        ? undefined
        : (await sha512(encodeUtf8(`AirPlayStreamIV${connectionIdText}`), mediaSessionKey)).slice(0, 16);
      const videoStreamSender = new AirPlayVideoStreamSender(
        videoStreamKey,
        display.width,
        display.height,
        (data: Uint8Array): Promise<void> => this.enqueueVideoBytes(data),
        this.log,
        (): void => this.forceKeyFrameHandler?.(),
        videoEncryption,
        videoStreamIv
      );
      await videoStreamSender.initialize();
      this.videoStreamSender = videoStreamSender;
      let audioSession: AudioRtpSession | undefined = undefined;
      if (paired) {
        try {
          audioSession = await this.setupAudioStream(info, mediaSessionKey);
          this.ensureRunning();
        } catch (error) {
          this.ensureRunning();
          audioSession = undefined;
          this.log(`AirPlay audio SETUP unavailable: ${error instanceof Error ? error.message : String(error)}`);
        }
      } else {
        this.log('AirPlay et=NONE session: audio RTP is disabled because no paired DataStream key exists');
      }
      if (audioSession) {
        const audioRecord = await this.request(
          'RECORD',
          '/',
          BinaryPlist.encode(PlistNode.dictionary(new Map<string, PlistNode>())),
          'RECORD after audio SETUP'
        );
        this.ensureRunning();
        requireSuccess(audioRecord, 'RECORD after audio SETUP');
      }

      const result: AirPlayMediaSessionInfo = {
        eventPort,
        timingPort,
        keepAlivePort,
        enabledFeatures,
        displayUuid,
        displayType: display.displayType,
        nativeDisplayWidth: display.nativeWidth,
        nativeDisplayHeight: display.nativeHeight,
        viewArea: display.viewArea,
        displayModeId: display.modeId,
        availableDisplayModes: display.availableModes,
        resolutionMessage: display.resolutionMessage,
        displayWidth: display.width,
        displayHeight: display.height,
        maxFrameRate: display.maxFrameRate,
        videoDataPort,
        videoConnectionId,
        videoStreamKey,
        audioSession
      };
      if (result.eventPort === 0) {
        this.log('Receiver did not provide an event port; HID return channel is unavailable');
      }
      this.log(
        `AirPlay RTSP session active: video port=${videoDataPort}, event port=${result.eventPort}, ` +
          `timing port=${timingPort}, keep-alive port=${result.keepAlivePort}`
      );
      return result;
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      let cleanupMessage = '';
      try {
        await this.stop();
      } catch (cleanupError) {
        cleanupMessage = cleanupError instanceof Error ? cleanupError.message : String(cleanupError);
      }
      if (error instanceof AirPlayMediaSessionStatusError) {
        if (cleanupMessage.length > 0) {
          throw new AirPlayMediaSessionStatusError(
            error.statusCode,
            error.statusLine,
            error.stage,
            `${message}; media-session cleanup failed: ${cleanupMessage}`
          );
        }
        throw error;
      }
      if (cleanupMessage.length > 0) {
        throw new Error(`${message}; media-session cleanup failed: ${cleanupMessage}`);
      }
      throw new Error(`AirPlay media session failed: ${message}`);
    }
  }

  async requestReceiverHome(): Promise<void> {
    this.ensureRunning();
    const body = BinaryPlist.encode(PlistNode.dictionary(new Map<string, PlistNode>([
      ['type', PlistNode.string('requestUI')],
      ['params', PlistNode.dictionary(new Map<string, PlistNode>([
        ['url', PlistNode.string('oem:')]
      ]))]
    ])));
    const response = await this.client.request('POST', '/command', body,
      { contentType: 'application/x-apple-binary-plist' });
    if (response.statusCode !== 200) {
      throw new Error(`车机拒绝界面切换：${response.statusCode}`);
    }
    this.log('Receiver acknowledged OEM UI request; media streams remain active');
  }

  async sendVirtualIap2Message(bytes: Uint8Array): Promise<void> {
    this.ensureRunning();
    if (!this.virtualIap2Session) {
      throw new Error('MIB3 virtual iAP2 link is not active');
    }
    await this.request(
      'POST',
      '/command',
      AirPlayMediaSession.buildIapSendMessagePayload(bytes),
      'MIB3 virtual iAP2 message'
    );
  }

  async stop(abort: boolean = false): Promise<void> {
    this.running = false;
    this.virtualIap2Session?.cancel();
    this.virtualIap2Session = undefined;
    if (abort) {
      this.recorded = false;
    }
    this.log(
      `AirPlay heartbeat summary: timingRequests=${this.timingRequestsReceived}, ` +
        `lowPowerKeepAlivesSent=${this.lowPowerKeepAlivesSent}`
    );
    if (this.keepAliveTimer >= 0) {
      clearInterval(this.keepAliveTimer);
      this.keepAliveTimer = -1;
    }
    if (this.feedbackTimer >= 0) {
      clearTimeout(this.feedbackTimer);
      this.feedbackTimer = -1;
    }
    if (this.videoKeepAliveTimer >= 0) {
      clearInterval(this.videoKeepAliveTimer);
      this.videoKeepAliveTimer = -1;
    }
    const failures: string[] = [];
    const videoSocket = this.videoDataSocket;
    this.videoDataSocket = undefined;
    this.videoWriteFailed = true;
    if (videoSocket) {
      const errorHandler = this.videoSocketErrorHandler;
      const closeHandler = this.videoSocketCloseHandler;
      this.videoSocketErrorHandler = undefined;
      this.videoSocketCloseHandler = undefined;
      if (errorHandler) {
        try { videoSocket.off('error', errorHandler); } catch (_error) {}
      }
      if (closeHandler) {
        try { videoSocket.off('close', closeHandler); } catch (_error) {}
      }
      try {
        await settleSocketWithin(videoSocket.close(), 1500, 'video socket close timed out');
      } catch (error) {
        failures.push(`video data socket: ${error instanceof Error ? error.message : String(error)}`);
      }
    }
    const videoStreamSender = this.videoStreamSender;
    this.videoStreamSender = undefined;
    if (videoStreamSender) {
      try {
        await settleSocketWithin(videoStreamSender.flush(), 1500, 'encoder queue shutdown timed out');
      } catch (error) {
        failures.push(`screen-stream encoder queue: ${error instanceof Error ? error.message : String(error)}`);
      }
      try {
        await settleSocketWithin(videoStreamSender.finish(), 1500, 'screen-stream cipher shutdown timed out');
      } catch (error) {
        failures.push(`screen-stream cipher: ${error instanceof Error ? error.message : String(error)}`);
      }
    }
    try {
      await settleSocketWithin(this.videoWriteQueue, 1500, 'video write shutdown timed out');
    } catch (error) {
      failures.push(`screen-stream send queue: ${error instanceof Error ? error.message : String(error)}`);
    }
    const eventChannel = this.eventChannel;
    this.eventChannel = undefined;
    if (eventChannel) {
      try {
        await settleSocketWithin(eventChannel.close(), 1500, 'event channel shutdown timed out');
      } catch (error) {
        failures.push(`event channel: ${error instanceof Error ? error.message : String(error)}`);
      }
    }
    if (this.recorded) {
      this.recorded = false;
      if (this.client.isConnected) {
        try {
          await this.request(
            'TEARDOWN',
            '/',
            BinaryPlist.encode(PlistNode.dictionary(new Map<string, PlistNode>())),
            'TEARDOWN'
          );
        } catch (error) {
          const message = error instanceof Error ? error.message : String(error);
          this.log(`WARN: RTSP TEARDOWN failed during shutdown; continuing local cleanup: ${message}`);
        }
      }
    }
    if (this.timingSocket) {
      const socket = this.timingSocket;
      this.timingSocket = undefined;
      if (this.timingHandler) {
        try {
          socket.off('message', this.timingHandler);
        } catch (error) {
          failures.push(`timing listener: ${error instanceof Error ? error.message : String(error)}`);
        }
      }
      this.timingHandler = undefined;
      try {
        await settleSocketWithin(socket.close(), 1500, 'timing socket close timed out');
      } catch (error) {
        failures.push(`timing socket: ${error instanceof Error ? error.message : String(error)}`);
      }
    }
    if (this.keepAliveSocket) {
      const socket = this.keepAliveSocket;
      this.keepAliveSocket = undefined;
      try {
        await settleSocketWithin(socket.close(), 1500, 'keep-alive socket close timed out');
      } catch (error) {
        failures.push(`keep-alive socket: ${error instanceof Error ? error.message : String(error)}`);
      }
    }
    if (failures.length > 0) {
      throw new Error(failures.join('; '));
    }
  }

  static buildSessionSetupPayload(
    deviceId: string,
    timingPort: number,
    encryptionTypeNone: boolean = false,
    sessionUuid: string = createUuid().toUpperCase(),
    sessionCorrelationUuid: string = createUuid().toUpperCase()
  ): Uint8Array {
    if (timingPort < 1 || timingPort > 65535) {
      throw new Error('AirPlay timing server must have a bound UDP port before SETUP');
    }
    const features: PlistNode[] = CONTROLLER_FEATURES.map((feature: string): PlistNode =>
      PlistNode.string(feature)
    );
    const fields: Map<string, PlistNode> = new Map<string, PlistNode>([
      ['deviceID', PlistNode.string(normalizeDeviceId(deviceId))],
      ['macAddress', PlistNode.string(CARPLAY_SENDER_MAC_ADDRESS)],
      ['name', PlistNode.string('iPhone')],
      ['model', PlistNode.string('iPhone14,2')],
      ['osName', PlistNode.string('iPhone OS')],
      ['osBuildVersion', PlistNode.string(CARPLAY_SENDER_OS_BUILD_VERSION)],
      ['osVersion', PlistNode.string('15.0.2')],
      ['sourceVersion', PlistNode.string(CARPLAY_SENDER_SOURCE_VERSION)],
      ['timingPort', PlistNode.integer(timingPort)],
      ['sessionUUID', PlistNode.string(sessionUuid)],
      ['sessionCorrelationUUID', PlistNode.string(sessionCorrelationUuid)],
      ['statsCollectionEnabled', PlistNode.boolean(false)],
      ['updateSessionRequest', PlistNode.boolean(false)],
      ['keepAliveLowPower', PlistNode.boolean(true)],
      ['features', PlistNode.array(features)]
    ]);
    if (encryptionTypeNone) {
      fields.set('et', PlistNode.integer(1));
    }
    return BinaryPlist.encode(PlistNode.dictionary(fields));
  }

  static buildVideoSetupPayload(displayUuid: string, connectionId: bigint): Uint8Array {
    if (!displayUuid || connectionId <= BigInt(0)) {
      throw new Error('Video SETUP requires a receiver display UUID and positive stream connection ID');
    }
    const stream = PlistNode.dictionary(new Map<string, PlistNode>([
      ['type', PlistNode.integer(110)],
      ['streamConnectionID', PlistNode.integer(connectionId)],
      ['uuid', PlistNode.string(displayUuid)],
      ['latencyMs', PlistNode.integer(25)]
    ]));
    return BinaryPlist.encode(PlistNode.dictionary(new Map<string, PlistNode>([
      ['streams', PlistNode.array([stream])]
    ])));
  }

  static buildAudioSetupPayload(
    connectionId: bigint,
    formatBit: bigint,
    latencyMs: number
  ): Uint8Array {
    if (connectionId <= BigInt(0) || (formatBit !== (BigInt(1) << BigInt(15)) &&
      formatBit !== (BigInt(1) << BigInt(11))) || latencyMs < 1 || latencyMs > 2000) {
      throw new Error('Invalid PCM audio SETUP parameters');
    }
    const stream = PlistNode.dictionary(new Map<string, PlistNode>([
      ['type', PlistNode.integer(100)],
      ['streamConnectionID', PlistNode.integer(connectionId)],
      ['audioFormat', PlistNode.integer(formatBit)],
      ['audioType', PlistNode.string('media')],
      ['audioLatencyMs', PlistNode.integer(latencyMs)],
      ['input', PlistNode.boolean(false)],
      ['supportsRTPPacketRedundancy', PlistNode.boolean(false)],
      ['supportsHighAccuracyTimestamps', PlistNode.boolean(false)],
      ['spf', PlistNode.integer(SAMPLES_PER_PACKET)],
      ['framesPerPacket', PlistNode.integer(SAMPLES_PER_PACKET)]
    ]));
    return BinaryPlist.encode(PlistNode.dictionary(new Map<string, PlistNode>([
      ['streams', PlistNode.array([stream])]
    ])));
  }

  static buildModesDictionary(modes: AirPlayModes = createDefaultModes()): PlistNode {
    const appStates: PlistNode[] = [
      PlistNode.dictionary(new Map<string, PlistNode>([
        ['appStateID', PlistNode.integer(2)],
        ['entity', PlistNode.integer(modes.phoneCallEntity)]
      ])),
      PlistNode.dictionary(new Map<string, PlistNode>([
        ['appStateID', PlistNode.integer(3)],
        ['entity', PlistNode.integer(modes.turnByTurnEntity)]
      ])),
      PlistNode.dictionary(new Map<string, PlistNode>([
        ['appStateID', PlistNode.integer(1)],
        ['entity', PlistNode.integer(modes.speechEntity)],
        ['speechMode', PlistNode.integer(modes.speechMode)]
      ]))
    ];
    const resources: PlistNode[] = [
      PlistNode.dictionary(new Map<string, PlistNode>([
        ['resourceID', PlistNode.integer(1)],
        ['entity', PlistNode.integer(modes.screenEntity)],
        ['permanentEntity', PlistNode.integer(modes.screenPermanentEntity)]
      ])),
      PlistNode.dictionary(new Map<string, PlistNode>([
        ['resourceID', PlistNode.integer(2)],
        ['entity', PlistNode.integer(modes.audioEntity)],
        ['permanentEntity', PlistNode.integer(modes.audioPermanentEntity)]
      ]))
    ];
    return PlistNode.dictionary(new Map<string, PlistNode>([
      ['appStates', PlistNode.array(appStates)],
      ['resources', PlistNode.array(resources)]
    ]));
  }

  static buildModesChangedPayload(modes: AirPlayModes = createDefaultModes()): Uint8Array {
    return BinaryPlist.encode(PlistNode.dictionary(new Map<string, PlistNode>([
      ['type', PlistNode.string('modesChanged')],
      ['params', AirPlayMediaSession.buildModesDictionary(modes)]
    ])));
  }

  static buildHidSetInputModePayload(uuid: string): Uint8Array {
    if (!uuid.trim()) {
      throw new Error('HID input mode requires a device UUID');
    }
    return BinaryPlist.encode(PlistNode.dictionary(new Map<string, PlistNode>([
      ['type', PlistNode.string('hidSetInputMode')],
      ['params', PlistNode.dictionary(new Map<string, PlistNode>([
        ['hidInputMode', PlistNode.integer(0)],
        ['uuid', PlistNode.string(uuid.toLowerCase())]
      ]))]
    ])));
  }

  static buildIapSendMessagePayload(frame: Uint8Array): Uint8Array {
    if (frame.length === 0) {
      throw new Error('Virtual iAP2 message must contain a frame');
    }
    return BinaryPlist.encode(PlistNode.dictionary(new Map<string, PlistNode>([
      ['type', PlistNode.string('iAPSendMessage')],
      ['params', PlistNode.dictionary(new Map<string, PlistNode>([
        ['data', PlistNode.data(frame)]
      ]))]
    ])));
  }

  // Grants every accessory request; the controller has no competing resource arbitration.
  static applyChangeModes(modes: AirPlayModes, params: PlistNode | undefined): AirPlayModes {
    const next: AirPlayModes = {
      screenEntity: modes.screenEntity,
      screenPermanentEntity: modes.screenPermanentEntity,
      audioEntity: modes.audioEntity,
      audioPermanentEntity: modes.audioPermanentEntity,
      speechEntity: modes.speechEntity,
      speechMode: modes.speechMode,
      phoneCallEntity: modes.phoneCallEntity,
      turnByTurnEntity: modes.turnByTurnEntity
    };
    const dictionary = params?.kind === 'dictionary' ? params : undefined;
    const resources = dictionary?.get('resources');
    for (const resource of resources?.kind === 'array' ? resources.arrayValue : []) {
      if (resource.kind !== 'dictionary') {
        continue;
      }
      const id = Number(resource.get('resourceID')?.integerValue ?? BigInt(0));
      const transfer = Number(resource.get('transferType')?.integerValue ?? BigInt(0));
      if (id !== 1 && id !== 2) {
        continue;
      }
      let permanent = id === 1 ? next.screenPermanentEntity : next.audioPermanentEntity;
      let current = id === 1 ? next.screenEntity : next.audioEntity;
      if (transfer === 1) {
        permanent = 2;
        current = 2;
      } else if (transfer === 2) {
        permanent = 1;
        current = 1;
      } else if (transfer === 3) {
        current = 2;
      } else if (transfer === 4) {
        current = permanent;
      }
      if (id === 1) {
        next.screenEntity = current;
        next.screenPermanentEntity = permanent;
      } else {
        next.audioEntity = current;
        next.audioPermanentEntity = permanent;
      }
    }
    const appStates = dictionary?.get('appStates');
    for (const appState of appStates?.kind === 'array' ? appStates.arrayValue : []) {
      if (appState.kind !== 'dictionary') {
        continue;
      }
      const id = Number(appState.get('appStateID')?.integerValue ?? BigInt(0));
      const state = appState.get('state');
      const active = state?.kind === 'boolean' && state.boolValue;
      if (id === 1) {
        const speechMode = appState.get('speechMode');
        if (speechMode?.kind === 'integer') {
          next.speechMode = Number(speechMode.integerValue);
          next.speechEntity = next.speechMode === -1 ? 0 : 2;
        }
      } else if (id === 2 && state?.kind === 'boolean') {
        next.phoneCallEntity = active ? 2 : 0;
      } else if (id === 3 && state?.kind === 'boolean') {
        next.turnByTurnEntity = active ? 2 : 0;
      }
    }
    return next;
  }

  static buildTimingResponse(request: Uint8Array, nowMillis: number): Uint8Array | undefined {
    if (request.length < 32 || (request[0] >>> 6) !== 2 || request[1] !== 0xd2 ||
      request[2] !== 0 || request[3] !== 7) {
      return undefined;
    }
    const response = new Uint8Array(32);
    response[0] = 0x80;
    response[1] = 0xd3;
    response[2] = 0;
    response[3] = 7;
    response.set(request.slice(24, 32), 8);
    const ntpTime = createNtpTimestamp(nowMillis);
    response.set(ntpTime, 16);
    response.set(ntpTime, 24);
    return response;
  }

  // Byte 0: version in bits 7-6 (0) and the sleep flag in bit 5 (awake).
  static buildLowPowerKeepAliveBeacon(): Uint8Array {
    return new Uint8Array([0x00]);
  }

  static buildVideoKeepAliveFrame(nowMillis: number): Uint8Array {
    const header = new Uint8Array(128);
    header[4] = 2;
    const timestamp = createNtpTimestamp(nowMillis);
    for (let index = 0; index < timestamp.length; index++) {
      header[8 + index] = timestamp[timestamp.length - 1 - index];
    }
    return header;
  }


}
