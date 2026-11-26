import { SAMPLES_PER_PACKET } from '../../audio/AudioRtpSender';
import { CARPLAY_SENDER_OS_BUILD_VERSION, CARPLAY_SENDER_SOURCE_VERSION } from '../../protocol/CarPlaySenderCompatibility';
import { BinaryPlist, PlistNode } from '../BinaryPlist';
import { AirPlayModes } from './AirPlayMediaSessionTypes';
import { createNtpTimestamp, createUuid, normalizeDeviceId } from './AirPlayMediaHelpers';

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

export class AirPlayMediaSessionPayloads {
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
      ['params', AirPlayMediaSessionPayloads.buildModesDictionary(modes)]
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
