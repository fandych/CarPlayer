import cryptoFramework from '@ohos.security.cryptoFramework';
import netSocket from '@ohos.net.socket';
import { hkdfSha512 } from './AirPlayCrypto';
import { AirPlayEventChannel, AirPlayEventRequest } from './AirPlayEventChannel';
import { AirPlayRtspClient, AirPlayRtspResponse } from './AirPlayRtspClient';
import { BinaryPlist, PlistNode } from './BinaryPlist';
import { AirPlayVideoStreamSender, EncodedH264Event } from './AirPlayVideoStream';
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
import {
  projectionDisplayModes, ProjectionDisplayMode, readProjectionResolutionPreference,
  resolveProjectionDisplayMode, saveProjectionResolutionPreference
} from '../video/ProjectionSettings';

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

export interface AirPlayMediaSessionInfo {
  eventPort: number;
  timingPort: number;
  keepAlivePort: number;
  enabledFeatures: string[];
  displayUuid: string;
  nativeDisplayWidth: number;
  nativeDisplayHeight: number;
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
interface AirPlayNetworkError extends Error {
  code?: string | number;
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

export class AirPlayMediaSession {
  private readonly client: AirPlayRtspClient;
  private readonly receiverHost: string;
  private readonly log: (message: string) => void;
  private readonly onTransportDisconnected: (message: string) => void;
  private readonly wifiNetworkLease: WifiNetworkLease;
  private videoDataSocket?: netSocket.TCPSocket;
  private videoSocketErrorHandler?: (error: Error) => void;
  private videoSocketCloseHandler?: () => void;
  private videoStreamSender?: AirPlayVideoStreamSender;
  private videoWriteQueue: Promise<void> = Promise.resolve();
  private videoWriteFailed: boolean = false;
  private timingRequestsReceived: number = 0;
  private lowPowerKeepAlivesSent: number = 0;
  private forceKeyFrameHandler?: () => void;
  private touchReportHandler?: (report: Uint8Array) => void;
  private nightModeHandler?: (night: boolean) => void;
  private nightMode: boolean = false;
  private modes: AirPlayModes = createDefaultModes();
  private touchHid?: TouchHidDevice;
  private videoWidth: number = 0;
  private videoHeight: number = 0;
  private videoKeepAliveTimer: number = -1;
  private videoKeepAlivePending: boolean = false;
  private timingSocket?: netSocket.UDPSocket;
  private timingHandler?: (info: netSocket.SocketMessageInfo) => void;
  private keepAliveSocket?: netSocket.UDPSocket;
  private eventChannel?: AirPlayEventChannel;
  private keepAliveTimer: number = -1;
  private feedbackTimer: number = -1;
  private feedbackPending: boolean = false;
  private feedbackEnabled: boolean = true;
  private running: boolean = false;
  private recorded: boolean = false;

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

  async start(deviceId: string, sharedSecret: Uint8Array):
    Promise<AirPlayMediaSessionInfo> {
    if (this.running) {
      throw new Error('AirPlay media session is already active');
    }
    if (sharedSecret.length === 0) {
      throw new Error('AirPlay shared secret is missing; refusing to negotiate an unauthenticated media session');
    }
    const normalizedDeviceId = normalizeDeviceId(deviceId);
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
        AirPlayMediaSession.buildSessionSetupPayload(normalizedDeviceId, timingPort),
        'initial session SETUP'
      );
      this.ensureRunning();
      const initialResponse = requireDictionary(initialSetup, 'initial session SETUP');
      const enabledFeatures = readStringArray(initialResponse.get('enabledFeatures'));
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
      this.touchHid = findTouchHidDevice(info, displayUuid) ?? {
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
        }
      } else {
        this.log('Receiver did not provide an event port before resource claim');
      }
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
      await this.openVideoDataPort(videoDataPort);
      this.ensureRunning();
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
      const videoStreamKey = await hkdfSha512(
        sharedSecret,
        encodeUtf8(`DataStream-Salt${videoConnectionId.toString()}`),
        encodeUtf8('DataStream-Output-Encryption-Key')
      );
      this.videoStreamSender = new AirPlayVideoStreamSender(
        videoStreamKey,
        display.width,
        display.height,
        (data: Uint8Array): Promise<void> => this.enqueueVideoBytes(data),
        this.log,
        (): void => this.forceKeyFrameHandler?.()
      );
      let audioSession: AudioRtpSession | undefined = undefined;
      try {
        // The session is already recording, so the receiver starts a newly set up stream immediately.
        audioSession = await this.setupAudioStream(info, sharedSecret);
        this.ensureRunning();
      } catch (error) {
        this.ensureRunning();
        audioSession = undefined;
        this.log(`AirPlay audio SETUP unavailable: ${error instanceof Error ? error.message : String(error)}`);
      }

      const result: AirPlayMediaSessionInfo = {
        eventPort,
        timingPort,
        keepAlivePort: readPort(initialResponse.get('keepAlivePort')),
        enabledFeatures,
        displayUuid,
        nativeDisplayWidth: display.nativeWidth,
        nativeDisplayHeight: display.nativeHeight,
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
      await this.startKeepAlive(result.keepAlivePort);
      this.ensureRunning();
      this.startFeedbackLoop();
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
      try {
        await this.stop();
      } catch (cleanupError) {
        const cleanupMessage = cleanupError instanceof Error ? cleanupError.message : String(cleanupError);
        throw new Error(`${message}; media-session cleanup failed: ${cleanupMessage}`);
      }
      throw new Error(`AirPlay media session failed: ${message}`);
    }
  }

  private ensureRunning(): void {
    if (!this.running) {
      throw new Error('AirPlay media session startup was cancelled');
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

  async stop(abort: boolean = false): Promise<void> {
    this.running = false;
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

  static buildSessionSetupPayload(deviceId: string, timingPort: number): Uint8Array {
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
      ['sessionUUID', PlistNode.string(createUuid().toUpperCase())],
      ['sessionCorrelationUUID', PlistNode.string(createUuid().toUpperCase())],
      ['statsCollectionEnabled', PlistNode.boolean(false)],
      ['updateSessionRequest', PlistNode.boolean(false)],
      ['keepAliveLowPower', PlistNode.boolean(true)],
      ['features', PlistNode.array(features)]
    ]);
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

  private async startTimingServer(): Promise<number> {
    const socket = netSocket.constructUDPSocketInstance();
    const handler = (info: netSocket.SocketMessageInfo): void => {
      const request = new Uint8Array(info.message);
      this.log(formatRawBytesDiagnostic('RX', 'AirPlay timing UDP', request, 64));
      const response = AirPlayMediaSession.buildTimingResponse(request, Date.now());
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

  private async openVideoDataPort(port: number): Promise<void> {
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

  private async sendVideoKeepAlive(): Promise<void> {
    const socket = this.videoDataSocket;
    if (!socket || !this.recorded || this.videoKeepAlivePending) {
      return;
    }
    const header = AirPlayMediaSession.buildVideoKeepAliveFrame(Date.now());
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

  private reportVideoSocketFailure(socket: netSocket.TCPSocket, reason: string): void {
    if (this.videoDataSocket !== socket || !this.running || !this.recorded || this.videoWriteFailed) {
      return;
    }
    this.videoWriteFailed = true;
    this.log(`AirPlay screen data TCP ${reason}`);
    this.onTransportDisconnected(`AirPlay screen data TCP ${reason}`);
  }

  private enqueueVideoBytes(data: Uint8Array): Promise<void> {
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

  private async setupAudioStream(info: PlistNode, sharedSecret: Uint8Array): Promise<AudioRtpSession | undefined> {
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
      AirPlayMediaSession.buildAudioSetupPayload(connectionId, format.formatBit, audioLatencyMs),
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

  private handleChangeModes(request: AirPlayEventRequest, params: PlistNode | undefined): void {
    this.modes = AirPlayMediaSession.applyChangeModes(this.modes, params);
    request.responseBody = BinaryPlist.encode(PlistNode.dictionary(new Map<string, PlistNode>([
      ['status', PlistNode.integer(0)],
      ['params', AirPlayMediaSession.buildModesDictionary(this.modes)]
    ])));
    this.log(`AirPlay changeModes granted: screen=${this.modes.screenEntity}, audio=${this.modes.audioEntity}, ` +
      `speech=${this.modes.speechMode}, call=${this.modes.phoneCallEntity}, nav=${this.modes.turnByTurnEntity}`);
    const payload = AirPlayMediaSession.buildModesChangedPayload(this.modes);
    void this.client.request('POST', '/command', payload, { contentType: 'application/x-apple-binary-plist' })
      .then((response: AirPlayRtspResponse): void => {
        if (response.statusCode !== 200) {
          this.log(`AirPlay modesChanged rejected: ${response.statusLine}`);
        }
      })
      .catch((error: Error): void => this.log(`AirPlay modesChanged failed: ${error.message}`));
  }

  private handleEventRequest(request: AirPlayEventRequest): boolean {
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

  private async startKeepAlive(port: number): Promise<void> {
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

  private async sendKeepAlive(port: number): Promise<void> {
    const socket = this.keepAliveSocket;
    if (!socket || !this.running) {
      return;
    }
    const beacon = AirPlayMediaSession.buildLowPowerKeepAliveBeacon();
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

  private startFeedbackLoop(): void {
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

  private async request(method: string, path: string, body: Uint8Array, label: string):
    Promise<AirPlayRtspResponse> {
    const response = await this.client.request(method, path, body, {
      contentType: 'application/x-apple-binary-plist'
    });
    requireSuccess(response, label);
    return response;
  }
}

function requireDictionary(response: AirPlayRtspResponse, label: string): PlistNode {
  const value = BinaryPlist.decode(response.body);
  if (value.kind !== 'dictionary') {
    throw new Error(`${label} response is not a binary plist dictionary`);
  }
  return value;
}

function requireSuccess(response: AirPlayRtspResponse, label: string): void {
  if (response.statusCode !== 200) {
    throw new Error(`${label} rejected: ${response.statusLine}`);
  }
}

function readPort(node: PlistNode | undefined): number {
  if (!node || node.kind !== 'integer') {
    return 0;
  }
  const port = Number(node.integerValue);
  return Number.isSafeInteger(port) && port >= 0 && port <= 65535 ? port : 0;
}

export function isForceKeyFrameCommand(command: PlistNode): boolean {
  if (command.kind !== 'dictionary') {
    return false;
  }
  const type = command.get('type');
  const legacyCommand = command.get('command');
  return (type?.kind === 'string' && type.stringValue === 'forceKeyFrame') ||
    (legacyCommand?.kind === 'string' && legacyCommand.stringValue === 'forceKeyFrame');
}

export interface PcmAudioFormat {
  formatBit: bigint;
  sampleRate: number;
}

export function selectPcmAudioFormat(info: PlistNode): PcmAudioFormat | undefined {
  const formats = info.get('audioFormats');
  if (!formats || formats.kind !== 'array') {
    return undefined;
  }
  let supports48k = false;
  let supports44k = false;
  for (const entry of formats.arrayValue) {
    if (entry.kind !== 'dictionary' || entry.get('type')?.integerValue !== BigInt(100) ||
      entry.get('audioType')?.stringValue !== 'media') {
      continue;
    }
    const output = entry.get('audioOutputFormats');
    if (!output || output.kind !== 'integer') {
      continue;
    }
    supports48k ||= (output.integerValue & (BigInt(1) << BigInt(15))) !== BigInt(0);
    supports44k ||= (output.integerValue & (BigInt(1) << BigInt(11))) !== BigInt(0);
  }
  if (supports48k) {
    return { formatBit: BigInt(1) << BigInt(15), sampleRate: 48000 };
  }
  if (supports44k) {
    return { formatBit: BigInt(1) << BigInt(11), sampleRate: 44100 };
  }
  return undefined;
}

function readAudioLatency(info: PlistNode, sampleRate: number): number {
  const latencies = info.get('audioLatencies');
  if (!latencies || latencies.kind !== 'array') {
    return 250;
  }
  const selected = latencies.arrayValue.find((entry: PlistNode): boolean =>
    entry.kind === 'dictionary' &&
    entry.get('type')?.integerValue === BigInt(100) &&
    entry.get('audioType')?.stringValue === 'media'
  );
  const outputLatency = selected?.get('outputLatencyMicros');
  if (!outputLatency || outputLatency.kind !== 'integer') {
    return 250;
  }
  const milliseconds = Number(outputLatency.integerValue) / 1000;
  if (!Number.isFinite(milliseconds) || milliseconds < 0) {
    return 250;
  }
  return Math.max(32, Math.min(2000, Math.round(milliseconds + (sampleRate === 44100 ? 30 : 0))));
}

function readStringArray(node: PlistNode | undefined): string[] {
  if (!node || node.kind !== 'array') {
    return [];
  }
  return node.arrayValue
    .filter((item: PlistNode): boolean => item.kind === 'string')
    .map((item: PlistNode): string => item.stringValue);
}

interface AirPlayDisplayDescriptor {
  uuid: string;
  width: number;
  height: number;
  nativeWidth: number;
  nativeHeight: number;
  sourceWidth: number;
  sourceHeight: number;
  maxFrameRate: number;
  modeId: string;
  availableModes: ProjectionDisplayMode[];
  resolutionMessage: string;
}

function readDisplayInfo(info: PlistNode): AirPlayDisplayDescriptor {
  const displays = info.get('displays');
  if (!displays || displays.kind !== 'array' || displays.arrayValue.length === 0) {
    throw new Error('AirPlay /info did not provide a display descriptor; refusing to invent a display UUID');
  }
  const display = displays.arrayValue[0];
  if (display.kind !== 'dictionary') {
    throw new Error('AirPlay /info displays[0] is not a dictionary');
  }
  const uuid = display.get('uuid') ?? display.get('UUID');
  if (!uuid) {
    throw new Error('AirPlay /info display descriptor has no UUID');
  }
  let normalizedUuid: string;
  if (uuid.kind === 'string' && uuid.stringValue.length > 0) {
    normalizedUuid = uuid.stringValue;
  } else if (uuid.kind === 'integer') {
    normalizedUuid = uuid.integerValue.toString();
  } else if (uuid.kind === 'data' && uuid.dataValue.length === 16) {
    const hex = Array.from(uuid.dataValue).map((value: number): string =>
      value.toString(16).padStart(2, '0')
    ).join('');
    normalizedUuid =
      `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`;
  } else {
    throw new Error('AirPlay /info display UUID has an unsupported type or length');
  }
  const widthNode = display.get('widthPixels') ?? display.get('width');
  const heightNode = display.get('heightPixels') ?? display.get('height');
  const maxFpsNode = display.get('maxFPS');
  const readPositiveInteger = (node: PlistNode | undefined): number | undefined => {
    if (!node || node.kind !== 'integer') {
      return undefined;
    }
    const value = Number(node.integerValue);
    return Number.isSafeInteger(value) && value > 0 ? value : undefined;
  };
  const rawWidth = readPositiveInteger(widthNode);
  const rawHeight = readPositiveInteger(heightNode);
  const frameRate = readPositiveInteger(maxFpsNode);
  if (rawWidth === undefined || rawHeight === undefined) {
    throw new Error('AirPlay /info display is missing valid widthPixels/heightPixels; refusing to guess output size');
  }
  const nativeWidth = rawWidth;
  const nativeHeight = rawHeight;
  const availableModes = projectionDisplayModes(normalizedUuid, nativeWidth, nativeHeight);
  const preferredModeId = readProjectionResolutionPreference(normalizedUuid);
  const selectedMode = resolveProjectionDisplayMode(availableModes, preferredModeId);
  const resolutionMessage = selectedMode.usedNativeFallback
    ? `保存的分辨率档位 ${preferredModeId} 未在当前显示 Profile 验证，已恢复车机原生 ${nativeWidth}×${nativeHeight}`
    : '';
  if (selectedMode.usedNativeFallback) {
    saveProjectionResolutionPreference(normalizedUuid, selectedMode.mode.id);
  }
  return {
    uuid: normalizedUuid,
    width: selectedMode.mode.width,
    height: selectedMode.mode.height,
    nativeWidth,
    nativeHeight,
    sourceWidth: nativeWidth,
    sourceHeight: nativeHeight,
    maxFrameRate: Math.min(60, frameRate ?? 30),
    modeId: selectedMode.mode.id,
    availableModes,
    resolutionMessage
  };
}

function normalizeDeviceId(value: string): string {
  const normalized = value.trim().toUpperCase();
  if (!/^[0-9A-F]{2}(:[0-9A-F]{2}){5}$/.test(normalized) ||
    normalized === '02:00:00:00:00:00') {
    throw new Error('AirPlay session requires a real Bluetooth device address; replace the placeholder in Settings');
  }
  return normalized;
}

async function randomPositiveInt64(): Promise<bigint> {
  const blob = await cryptoFramework.createRandom().generateRandom(8);
  const random = new Uint8Array(blob.data);
  let value = BigInt(0);
  for (const byte of random) {
    value = (value << BigInt(8)) | BigInt(byte);
  }
  value &= (BigInt(1) << BigInt(63)) - BigInt(1);
  return value === BigInt(0) ? BigInt(1) : value;
}

function createUuid(): string {
  const digits: string[] = [];
  for (let index = 0; index < 32; index++) {
    digits.push(Math.floor(Math.random() * 16).toString(16));
  }
  digits[12] = '4';
  const variant = Number.parseInt(digits[16], 16);
  digits[16] = ((variant & 3) | 8).toString(16);
  const raw = digits.join('').toUpperCase();
  return `${raw.slice(0, 8)}-${raw.slice(8, 12)}-${raw.slice(12, 16)}-${raw.slice(16, 20)}-${raw.slice(20)}`;
}

function createNtpTimestamp(nowMillis: number): Uint8Array {
  const seconds = Math.floor(nowMillis / 1000) + 2208988800;
  const fraction = Math.floor(((nowMillis % 1000) * 0x100000000) / 1000);
  const result = new Uint8Array(8);
  writeBe32(result, 0, seconds);
  writeBe32(result, 4, fraction);
  return result;
}

function describeNetworkError(error: Error): string {
  const details = error as AirPlayNetworkError;
  const message = details.message || String(error);
  return details.code === undefined ? message : `${message} (code=${details.code})`;
}

function writeBe32(target: Uint8Array, offset: number, value: number): void {
  target[offset] = (value >>> 24) & 0xff;
  target[offset + 1] = (value >>> 16) & 0xff;
  target[offset + 2] = (value >>> 8) & 0xff;
  target[offset + 3] = value & 0xff;
}
