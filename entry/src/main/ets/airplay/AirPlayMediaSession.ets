import { PlistNode } from './BinaryPlist';
import { AirPlayMediaSessionLifecycle } from './media/AirPlayMediaSessionLifecycle';
import { AirPlayMediaSessionPayloads } from './media/AirPlayMediaSessionPayloads';
import { AirPlayModes, createDefaultModes } from './media/AirPlayMediaSessionTypes';
import { createUuid } from './media/AirPlayMediaHelpers';

export { AirPlayMediaSessionInfo, AirPlayModes, createDefaultModes } from './media/AirPlayMediaSessionTypes';
export { AirPlayViewArea } from './media/AirPlayMediaHelpers';
export {
  AirPlayMediaSessionStatusError,
  PcmAudioFormat,
  isForceKeyFrameCommand,
  parseIapSendMessagePayload,
  selectPcmAudioFormat
} from './media/AirPlayMediaHelpers';

export class AirPlayMediaSession extends AirPlayMediaSessionLifecycle {
  protected createTimingResponse(request: Uint8Array, nowMillis: number): Uint8Array | undefined {
    return AirPlayMediaSessionPayloads.buildTimingResponse(request, nowMillis);
  }

  protected createVideoKeepAliveFrame(nowMillis: number): Uint8Array {
    return AirPlayMediaSessionPayloads.buildVideoKeepAliveFrame(nowMillis);
  }

  protected createAudioSetupPayload(connectionId: bigint, formatBit: bigint, latencyMs: number): Uint8Array {
    return AirPlayMediaSessionPayloads.buildAudioSetupPayload(connectionId, formatBit, latencyMs);
  }

  protected applyModeChanges(modes: AirPlayModes, params: PlistNode | undefined): AirPlayModes {
    return AirPlayMediaSessionPayloads.applyChangeModes(modes, params);
  }

  protected createModesDictionary(modes: AirPlayModes): PlistNode {
    return AirPlayMediaSessionPayloads.buildModesDictionary(modes);
  }

  protected createModesChangedPayload(modes: AirPlayModes): Uint8Array {
    return AirPlayMediaSessionPayloads.buildModesChangedPayload(modes);
  }

  protected createLowPowerKeepAliveBeacon(): Uint8Array {
    return AirPlayMediaSessionPayloads.buildLowPowerKeepAliveBeacon();
  }

  static buildSessionSetupPayload(
    deviceId: string,
    timingPort: number,
    encryptionTypeNone: boolean = false,
    sessionUuid: string = createUuid().toUpperCase(),
    sessionCorrelationUuid: string = createUuid().toUpperCase()
  ): Uint8Array {
    return AirPlayMediaSessionPayloads.buildSessionSetupPayload(
      deviceId, timingPort, encryptionTypeNone, sessionUuid, sessionCorrelationUuid);
  }

  static buildVideoSetupPayload(displayUuid: string, connectionId: bigint): Uint8Array {
    return AirPlayMediaSessionPayloads.buildVideoSetupPayload(displayUuid, connectionId);
  }

  static buildAudioSetupPayload(connectionId: bigint, formatBit: bigint, latencyMs: number): Uint8Array {
    return AirPlayMediaSessionPayloads.buildAudioSetupPayload(connectionId, formatBit, latencyMs);
  }

  static buildModesDictionary(modes: AirPlayModes = createDefaultModes()): PlistNode {
    return AirPlayMediaSessionPayloads.buildModesDictionary(modes);
  }

  static buildModesChangedPayload(modes: AirPlayModes = createDefaultModes()): Uint8Array {
    return AirPlayMediaSessionPayloads.buildModesChangedPayload(modes);
  }

  static buildHidSetInputModePayload(uuid: string): Uint8Array {
    return AirPlayMediaSessionPayloads.buildHidSetInputModePayload(uuid);
  }

  static buildIapSendMessagePayload(frame: Uint8Array): Uint8Array {
    return AirPlayMediaSessionPayloads.buildIapSendMessagePayload(frame);
  }

  static applyChangeModes(modes: AirPlayModes, params: PlistNode | undefined): AirPlayModes {
    return AirPlayMediaSessionPayloads.applyChangeModes(modes, params);
  }

  static buildTimingResponse(request: Uint8Array, nowMillis: number): Uint8Array | undefined {
    return AirPlayMediaSessionPayloads.buildTimingResponse(request, nowMillis);
  }

  static buildLowPowerKeepAliveBeacon(): Uint8Array {
    return AirPlayMediaSessionPayloads.buildLowPowerKeepAliveBeacon();
  }

  static buildVideoKeepAliveFrame(nowMillis: number): Uint8Array {
    return AirPlayMediaSessionPayloads.buildVideoKeepAliveFrame(nowMillis);
  }
}
