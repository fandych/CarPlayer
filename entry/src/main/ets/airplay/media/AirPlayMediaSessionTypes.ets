import { AudioRtpSession } from '../../audio/AudioRtpSender';
import { ProjectionDisplayMode } from '../../video/ProjectionSettings';
import { AirPlayViewArea } from './AirPlayMediaHelpers';

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
