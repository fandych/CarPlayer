import { hkdfSha512, sha512 } from '../AirPlayCrypto';
import { AirPlayVideoEncryptionMode, AirPlayVideoStreamSender } from '../AirPlayVideoStream';
import { BinaryPlist, PlistNode } from '../BinaryPlist';
import { encodeUtf8 } from '../../protocol/Iap2Codec';
import { Iap2SenderSession } from '../../session/Iap2SenderSession';
import { AudioRtpSession } from '../../audio/AudioRtpSender';
import {
  DEFAULT_TOUCH_HID_UUID,
  findTouchHidDevice,
  TouchHidDevice
} from '../CarPlayTouchReport';
import { AirPlayMediaSessionInfo } from './AirPlayMediaSessionTypes';
import { AirPlayMediaSessionStartHelpers } from './AirPlayMediaSessionStartHelpers';
import { AirPlayMediaSessionPayloads } from './AirPlayMediaSessionPayloads';
import {
  AirPlayMediaSessionStatusError,
  createUuid,
  normalizeDeviceId,
  randomPositiveInt64,
  readAudioLatency,
  readDisplayInfo,
  readPort,
  readStringArray,
  requireDictionary,
  requireSuccess,
  selectPcmAudioFormat
} from './AirPlayMediaHelpers';

const MIB3_IAP2_DETECT_MARKER: Uint8Array = new Uint8Array([0xff, 0x55, 0x02, 0x00, 0xee, 0x10]);

export abstract class AirPlayMediaSessionStart extends AirPlayMediaSessionStartHelpers {
  abstract stop(abort?: boolean): Promise<void>;
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
        AirPlayMediaSessionPayloads.buildSessionSetupPayload(
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
        AirPlayMediaSessionPayloads.buildModesChangedPayload(),
        'modesChanged resource declaration'
      );
      this.ensureRunning();
      const videoConnectionId = await randomPositiveInt64();
      const videoSetup = await this.request(
        'SETUP',
        '/',
        AirPlayMediaSessionPayloads.buildVideoSetupPayload(displayUuid, videoConnectionId),
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
          AirPlayMediaSessionPayloads.buildIapSendMessagePayload(MIB3_IAP2_DETECT_MARKER),
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
      await this.setupEventChannel(eventPort, sharedSecret, mib3VirtualLink, paired, touchHid);
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

}
