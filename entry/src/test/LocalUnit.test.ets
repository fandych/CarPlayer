import { describe, beforeAll, beforeEach, afterEach, afterAll, it, expect } from '@ohos/hypium';
import {
  encodeIap2LinkFrame,
  encodeIap2Control,
  encodeIap2Parameter,
  encodeIap2SyncPayload,
  encodeUtf8,
  formatIap2LinkPayloadDiagnostic,
  formatIap2MessageDiagnostic,
  formatIap2RawFrameDiagnostic,
  groupedParameter,
  Iap2LinkDecoder,
  Iap2LinkFrame,
  concatBytes,
  numberParameter,
  stringParameter
} from '../main/ets/protocol/Iap2Codec';
import {
  Iap2SenderSession,
  parseMfiCertificatePayload,
  parseWirelessSessionCredentials,
  parseWirelessSessionEndpoint,
  readMessageIds,
  shouldProbeLegacyWifi
} from '../main/ets/session/Iap2SenderSession';
import { isMfiPinEligiblePkixFailure, MfiVerifier, verifyRawMfiP256Signature } from '../main/ets/iap2/MfiVerifier';
import { appendConnectionLog, MAX_CONNECTION_LOG_LINES } from '../main/ets/session/ConnectionLogBuffer';
import { formatProtocolEvent, ProtocolLogger } from '../main/ets/session/ProtocolLogger';
import { formatLocalClock, formatLocalDateKey, formatLocalTimestamp } from '../main/ets/session/LogTimestamp';
import {
  AirPlayHidReportSummaryWindow,
  parseAirPlayEventRequests
} from '../main/ets/airplay/AirPlayEventChannel';
import { correlateAirPlayIdentity } from '../main/ets/network/AirPlayIdentityCorrelation';
import { AirPlayMediaSession, isForceKeyFrameCommand } from '../main/ets/airplay/AirPlayMediaSession';
import { BinaryPlist, PlistNode } from '../main/ets/airplay/BinaryPlist';
import { extractCarPlayTouchReport, parseCarPlayTouchReport } from '../main/ets/airplay/CarPlayTouchReport';
import { CARPLAY_SENDER_SOURCE_VERSION } from '../main/ets/protocol/CarPlaySenderCompatibility';
import { isAirPlayStartReady } from '../main/ets/session/SessionController';
import {
  AirPlayVideoStreamSender,
  buildAirPlayVideoConfigHeader,
  patchH264SpsLevel
} from '../main/ets/airplay/AirPlayVideoStream';
import { advanceAudioRtpTimestamp, buildAudioRtpSyncPacket, SAMPLES_PER_PACKET } from '../main/ets/audio/AudioRtpSender';
import { CarPlayTouchInput, CarPlayTouchReport, CarPlayTouchTap } from '../main/ets/video/CarPlayTouchInput';
import {
  projectionDisplayDensity,
  projectionDisplayToggleTarget
} from '../main/ets/video/CarPlayVirtualDisplay';
import { ProjectionShakeDetector } from '../main/ets/video/ProjectionShakeDetector';
import { ProjectionMapBounds, ProjectionMapGesture } from '../main/ets/video/ProjectionMapGesture';
import {
  activeProjectionMusicApp,
  findLaunchableProjectionApp,
  isProjectionAppInstanceMigratable,
  projectionAppLaunchTarget,
  ProjectionApp,
  PROJECTION_APP_CANDIDATES,
  PROJECTION_MAP_URI,
  resolveProjectionApps
} from '../main/ets/pages/ProjectionAppCatalog';

export default function localUnitTest() {
  describe('localUnitTest', () => {
    // Defines a test suite. Two parameters are supported: test suite name and test suite function.
    beforeAll(() => {
      // Presets an action, which is performed only once before all test cases of the test suite start.
      // This API supports only one parameter: preset action function.
    });
    beforeEach(() => {
      // Presets an action, which is performed before each unit test case starts.
      // The number of execution times is the same as the number of test cases defined by **it**.
      // This API supports only one parameter: preset action function.
    });
    afterEach(() => {
      // Presets a clear action, which is performed after each unit test case ends.
      // The number of execution times is the same as the number of test cases defined by **it**.
      // This API supports only one parameter: clear action function.
    });
    afterAll(() => {
      // Presets a clear action, which is performed after all test cases of the test suite end.
      // This API supports only one parameter: clear action function.
    });
    it('assertContain', 0, () => {
      // Defines a test case. This API supports three parameters: test case name, filter parameter, and test case function.
      let a = 'abc';
      let b = 'b';
      // Defines a variety of assertion methods, which are used to declare expected boolean conditions.
      expect(a).assertContain(b);
      expect(a).assertEqual(a);
    });

    it('restores reference app targets and keeps them disabled before device checks', 0, async (): Promise<void> => {
      expect(PROJECTION_APP_CANDIDATES.length).assertEqual(13);
      expect(PROJECTION_APP_CANDIDATES[0].uri).assertEqual(PROJECTION_MAP_URI);
      expect(PROJECTION_APP_CANDIDATES[0].launchTarget?.bundleName).assertEqual('com.amap.hmapp');
      expect(PROJECTION_APP_CANDIDATES[1].launchTarget?.uri).assertEqual('baidumap://map');
      const available = await resolveProjectionApps((_uri: string): boolean => false);
      expect(available.length).assertEqual(PROJECTION_APP_CANDIDATES.length);
      for (const app of PROJECTION_APP_CANDIDATES) {
        expect(app.launchState).assertEqual('UNVERIFIED');
        expect(app.uri.startsWith('carplay-client://v1/apps/')).assertTrue();
      }
      for (const app of available) {
        expect(app.launchState).assertEqual('UNVERIFIED');
      }
      const resolved = await resolveProjectionApps((uri: string): boolean => uri === 'amapuri://');
      expect(resolved[0].launchState).assertEqual('VERIFIED');
      expect(resolved[0].launchTarget?.kind).assertEqual('ability');
      expect(resolved[1].launchState).assertEqual('UNVERIFIED');
    });

    it('aggregates HID event diagnostics instead of logging each report', 0, () => {
      const summary = new AirPlayHidReportSummaryWindow(1000);
      expect(summary.record(1000)).assertEqual(1);
      expect(summary.record(1100)).assertUndefined();
      expect(summary.record(1200)).assertUndefined();
      expect(summary.record(2000)).assertEqual(3);
    });

    it('uses the URI and explicit Ability discovered on the connected Huawei Music package', 0,
      async (): Promise<void> => {
        const candidate = PROJECTION_APP_CANDIDATES[4];
        expect(candidate.bundleName).assertEqual('com.huawei.hmsapp.music');
        expect(candidate.abilityName).assertEqual('MainAbility');
        expect(candidate.launchTarget?.kind).assertEqual('appLink');
        expect(candidate.launchTarget?.uri).assertEqual('hwmusic://com.huawei.hmsapp.music');
        const resolved = await resolveProjectionApps(
          (uri: string): boolean => uri === 'hwmusic://com.huawei.hmsapp.music'
        );
        expect(resolved[4].launchState).assertEqual('VERIFIED');
        expect(resolved[4].launchTarget?.uri).assertEqual('hwmusic://com.huawei.hmsapp.music');
      });

    it('recognizes only a verified singleton AMap ability as migratable', 0,
      async (): Promise<void> => {
        const resolved = await resolveProjectionApps(
          (uri: string): boolean => uri === 'amapuri://',
          async (bundleName: string) => bundleName === 'com.amap.hmapp' ? [{
            moduleName: 'entry',
            abilityName: 'EntryAbility',
            isMainElement: true,
            enabled: true,
            exported: true,
            isSingleton: true
          }] : []
        );
        expect(resolved[0].launchTarget?.kind).assertEqual('ability');
        expect(resolved[0].launchTarget?.isSingleton).assertTrue();
        expect(isProjectionAppInstanceMigratable(resolved[0])).assertTrue();
        const startTarget = projectionAppLaunchTarget(resolved[0]);
        expect(startTarget?.kind).assertEqual('appLink');
        expect(startTarget?.uri).assertEqual('amapuri://');
        expect(projectionAppLaunchTarget(resolved[0], true)?.kind).assertEqual('ability');
        const target = resolved[0].launchTarget;
        if (!target) {
          throw new Error('AMap Ability target was not resolved');
        }
        const nonSingleton: ProjectionApp = {
          appId: 'amap',
          uri: PROJECTION_MAP_URI,
          bundleName: 'com.amap.hmapp',
          moduleName: 'entry',
          abilityName: 'EntryAbility',
          launchTarget: {
            kind: 'ability',
            bundleName: 'com.amap.hmapp',
            moduleName: 'entry',
            abilityName: 'EntryAbility',
            isSingleton: false
          },
          launchState: 'VERIFIED',
          label: '高德地图',
          mark: '高',
          color: '#308A6E',
          category: 'map'
        };
        expect(isProjectionAppInstanceMigratable(nonSingleton)).assertFalse();
        expect(projectionAppLaunchTarget(nonSingleton, true)).assertUndefined();
      });

    it('keeps Baidu Maps on its verified app-link launch target', 0, async (): Promise<void> => {
      const resolved = await resolveProjectionApps(
        (uri: string): boolean => uri === 'baidumap://map'
      );
      expect(resolved[1].launchState).assertEqual('VERIFIED');
      expect(resolved[1].launchTarget?.kind).assertEqual('appLink');
      expect(resolved[1].launchTarget?.uri).assertEqual('baidumap://map');
    });

    it('chooses launchable dock apps and recognizes an opened music app without playback state', 0,
      async (): Promise<void> => {
        const maps = await resolveProjectionApps((uri: string): boolean => uri === 'baidumap://map');
        const music = await resolveProjectionApps(
          (uri: string): boolean => uri === 'hwmusic://com.huawei.hmsapp.music'
        );
        expect(findLaunchableProjectionApp(
          maps, 'map', maps[0].uri
        )).assertUndefined();
        expect(findLaunchableProjectionApp(maps, 'map')?.appId)
          .assertEqual('baidu-map');
        expect(activeProjectionMusicApp(music, music[4].uri)?.appId).assertEqual('huawei-music');
        expect(activeProjectionMusicApp(music, maps[1].uri)).assertUndefined();
      });

    it('matches AirPlay identity by public key when identifier encodings differ', 0, () => {
      const publicKey = 'a'.repeat(64);
      expect(correlateAirPlayIdentity(
        '02:5B:CC:7B:1B:50', publicKey, 'F6:4E:E3:D9:DE:38', `0x${publicKey.toUpperCase()}`
      )).assertEqual('public-key-match');
      expect(correlateAirPlayIdentity(
        '02:5B:CC:7B:1B:50', publicKey, '02-5B-CC-7B-1B-50', 'b'.repeat(64)
      )).assertEqual('conflict');
      expect(correlateAirPlayIdentity(
        '02:5B:CC:7B:1B:50', '', '02-5B-CC-7B-1B-50', ''
      )).assertEqual('identifier-match');
    });

    it('does not require the optional reverse probe after an authenticated start endpoint', 0, () => {
      expect(isAirPlayStartReady(true, false, true)).assertTrue();
      expect(isAirPlayStartReady(true, true, false)).assertTrue();
      expect(isAirPlayStartReady(false, true, true)).assertFalse();
      expect(isAirPlayStartReady(true, false, false)).assertFalse();
    });

    it('accepts only the advertised two-slot touch HID report', 0, () => {
      const report = new Uint8Array([0, 1, 0x34, 0x02, 0x78, 0x01, 1, 0, 0, 0, 0, 0]);
      const command = PlistNode.dictionary(new Map<string, PlistNode>([
        ['type', PlistNode.string('hidSendReport')],
        ['uuid', PlistNode.string('2a2a2a2a')],
        ['hidReport', PlistNode.data(report)]
      ]));
      const extracted = extractCarPlayTouchReport(command);
      if (!extracted) {
        throw new Error('Touch report was not extracted');
      }
      const contacts = parseCarPlayTouchReport(extracted);
      if (!contacts) {
        throw new Error('Touch report was not parsed');
      }
      expect(contacts.length).assertEqual(2);
      expect(contacts[0].down).assertTrue();
      expect(contacts[0].x).assertEqual(0x234);
      expect(contacts[0].y).assertEqual(0x178);
      expect(contacts[1].down).assertFalse();
      expect(parseCarPlayTouchReport(report.slice(0, 11))).assertUndefined();
      const singleContact = parseCarPlayTouchReport(new Uint8Array([1, 0x34, 0x02, 0x78, 0x01]));
      if (!singleContact) {
        throw new Error('Single-contact touch report was not parsed');
      }
      expect(singleContact.length).assertEqual(1);
      expect(singleContact[0].down).assertTrue();
      expect(singleContact[0].x).assertEqual(0x234);
      expect(singleContact[0].y).assertEqual(0x178);
      report[6] = 0;
      expect(parseCarPlayTouchReport(report)).assertUndefined();
      command.dictionaryValue.set('uuid', PlistNode.string('2a2a2a2b'));
      expect(extractCarPlayTouchReport(command)).assertUndefined();
    });

    it('extracts touch reports from the protocol params dictionary', 0, () => {
      const report = new Uint8Array([0, 1, 0x34, 0x02, 0x78, 0x01, 1, 0, 0, 0, 0, 0]);
      const command = PlistNode.dictionary(new Map<string, PlistNode>([
        ['type', PlistNode.string('hidSendReport')],
        ['params', PlistNode.dictionary(new Map<string, PlistNode>([
          ['uuid', PlistNode.string('2a2a2a2a')],
          ['hidReport', PlistNode.data(report)]
        ]))]
      ]));
      const extracted = extractCarPlayTouchReport(command);
      if (!extracted) {
        throw new Error('Nested touch report was not extracted');
      }
      expect(extracted.length).assertEqual(report.length);
    });

    it('recognizes forceKeyFrame by the protocol type field', 0, () => {
      const request = PlistNode.dictionary(new Map<string, PlistNode>([
        ['type', PlistNode.string('forceKeyFrame')],
        ['params', PlistNode.dictionary(new Map<string, PlistNode>([
          ['uuid', PlistNode.string('primary-display')]
        ]))]
      ]));
      expect(isForceKeyFrameCommand(request)).assertTrue();
      expect(isForceKeyFrameCommand(PlistNode.dictionary(new Map<string, PlistNode>([
        ['command', PlistNode.string('forceKeyFrame')]
      ])))).assertTrue();
      expect(isForceKeyFrameCommand(PlistNode.dictionary(new Map<string, PlistNode>([
        ['type', PlistNode.string('hidSendReport')]
      ])))).assertFalse();
    });

    it('advances audio timestamps over dropped packets and wraps at 32 bits', 0, () => {
      expect(advanceAudioRtpTimestamp(100, 2)).assertEqual(804);
      expect(advanceAudioRtpTimestamp(0xfffffff0, 1)).assertEqual(336);
      expect(advanceAudioRtpTimestamp(123, 0)).assertEqual(123);
    });

    it('builds the 20-byte audio-stream sync packet with independent sequence and timestamp', 0, () => {
      const packet = buildAudioRtpSyncPacket(0x1234, 100, 0, true);
      expect(packet.length).assertEqual(20);
      expect(packet[0]).assertEqual(0x90);
      expect(packet[1]).assertEqual(0xd4);
      expect(packet[2]).assertEqual(0x12);
      expect(packet[3]).assertEqual(0x34);
      expect(packet[7]).assertEqual(100);
      expect(packet[16]).assertEqual(0);
      expect(packet[17]).assertEqual(0);
      expect(packet[18]).assertEqual(1);
      expect(packet[19]).assertEqual(0xc4);
    });

    it('leaves the AirPlay codec configuration body unencrypted', 0, () => {
      const header = buildAirPlayVideoConfigHeader(16, 1280, 720);
      expect(header.length).assertEqual(128);
      expect(header[4]).assertEqual(1);
      expect(header[6]).assertEqual(0);
    });

    it('settles the H.264 send queue after an encoder event fails', 0, async (): Promise<void> => {
      const sender = new AirPlayVideoStreamSender(
        new Uint8Array(32),
        1280,
        720,
        async (): Promise<void> => {},
        (_message: string): void => {}
      );
      let sendFailed = false;
      try {
        await sender.handleEncoderEvent({ type: 'error', timestampUs: 0, flags: 0, message: 'test failure' });
      } catch (_error) {
        sendFailed = true;
      }
      expect(sendFailed).assertTrue();
      await sender.flush();
    });

    it('sets projection density from the car display width', 0, () => {
      expect(projectionDisplayDensity(1920)).assertEqual(2);
      expect(projectionDisplayDensity(960)).assertEqual(1);
      expect(projectionDisplayDensity(320)).assertEqual(0.5);
    });

    it('routes display toggles to the opposite display for map and app windows', 0, () => {
      expect(projectionDisplayToggleTarget(false, 0, 42)).assertEqual(0);
      expect(projectionDisplayToggleTarget(true, 0, 42)).assertEqual(42);
    });

    it('dispatches only complete single-finger taps on the active display', 0, () => {
      const taps: CarPlayTouchTap[] = [];
      const input = new CarPlayTouchInput((tap: CarPlayTouchTap): void => { taps.push(tap); });
      const down = new Uint8Array([0, 1, 100, 0, 50, 0, 1, 0, 0, 0, 0, 0]);
      const up = new Uint8Array([0, 0, 100, 0, 50, 0, 1, 0, 0, 0, 0, 0]);
      input.start(42, 1920, 914);
      input.handleReport(down);
      input.handleReport(up);
      expect(taps.length).assertEqual(1);
      expect(taps[0].displayId).assertEqual(42);
      expect(taps[0].endX).assertEqual(100);
      expect(taps[0].maxDistance).assertEqual(0);
      input.handleReport(down);
      input.handleReport(new Uint8Array([0, 1, 150, 0, 50, 0, 1, 0, 0, 0, 0, 0]));
      input.handleReport(up);
      expect(taps.length).assertEqual(2);
      expect(taps[1].maxDistance).assertEqual(50);
      input.handleReport(down);
      input.handleReport(new Uint8Array([0, 1, 100, 0, 50, 0, 1, 1, 120, 0, 50, 0]));
      input.handleReport(up);
      expect(taps.length).assertEqual(2);
      input.stop();
      input.handleReport(down);
      input.handleReport(up);
      expect(taps.length).assertEqual(2);
    });

    it('requires repeated shake pulses and applies a switch cooldown', 0, () => {
      const detector = new ProjectionShakeDetector();
      expect(detector.update(0, 0, 9.8, 0)).assertFalse();
      expect(detector.update(1, 0, 9.8, 100)).assertFalse();
      expect(detector.update(22, 0, 9.8, 200)).assertFalse();
      expect(detector.update(-22, 0, 9.8, 350)).assertFalse();
      expect(detector.update(22, 0, 9.8, 500)).assertTrue();
      expect(detector.update(-22, 0, 9.8, 650)).assertFalse();
      expect(detector.update(22, 0, 9.8, 800)).assertFalse();
      expect(detector.update(Number.NaN, 0, 0, 1000)).assertFalse();
      expect(detector.update(-22, 0, 9.8, 3100)).assertFalse();
      expect(detector.update(22, 0, 9.8, 3250)).assertFalse();
      expect(detector.update(-22, 0, 9.8, 3400)).assertTrue();
    });

    it('cancels a missing contact when the touch report format changes', 0, () => {
      const taps: CarPlayTouchTap[] = [];
      const fallback = new CarPlayTouchInput((tap: CarPlayTouchTap): void => { taps.push(tap); });
      fallback.start(42, 320, 240);
      fallback.handleReport(new Uint8Array([0, 0, 0, 0, 0, 0, 1, 1, 100, 0, 50, 0]));
      fallback.handleReport(new Uint8Array([0, 0, 0, 0, 0]));
      expect(taps.length).assertEqual(0);
      fallback.stop();
    });

    it('routes multi-touch reports to the shell and cancels them on stop', 0, () => {
      const reports: CarPlayTouchReport[] = [];
      const input = new CarPlayTouchInput((_tap: CarPlayTouchTap): void => {},
        (report: CarPlayTouchReport): void => { reports.push(report); });
      input.start(42, 1920, 914);
      input.handleReport(new Uint8Array([0, 1, 100, 0, 50, 0, 1, 0, 0, 0, 0, 0]));
      input.handleReport(new Uint8Array([0, 1, 100, 0, 50, 0, 1, 1, 120, 0, 50, 0]));
      input.handleReport(new Uint8Array([0, 1, 110, 0, 50, 0, 1, 1, 130, 0, 50, 0]));
      input.handleReport(new Uint8Array([0, 0, 110, 0, 50, 0, 1, 1, 130, 0, 50, 0]));
      input.stop();
      expect(reports.length).assertEqual(5);
      expect(reports[1].contacts.length).assertEqual(2);
      expect(reports[reports.length - 1].contacts.length).assertEqual(0);
    });

    it('forwards valid fallback touch reports and cancels out-of-bounds contacts', 0, () => {
      const reports: CarPlayTouchReport[] = [];
      const input = new CarPlayTouchInput((_tap: CarPlayTouchTap): void => {},
        (report: CarPlayTouchReport): void => { reports.push(report); });
      input.start(42, 320, 240);
      input.handleReport(new Uint8Array([0, 1, 100, 0, 50, 0, 1, 1, 120, 0, 50, 0]));
      input.handleReport(new Uint8Array([0, 1, 0x40, 0x01, 50, 0, 1, 0, 0, 0, 0, 0]));
      input.handleReport(new Uint8Array([0, 1, 100, 0, 50, 0, 1, 0, 0, 0, 0, 0]));
      expect(reports.length).assertEqual(2);
      expect(reports[0].contacts.length).assertEqual(2);
      expect(reports[0].displayId).assertEqual(42);
      expect(reports[1].contacts.length).assertEqual(0);
      input.handleReport(new Uint8Array([0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0]));
      expect(reports.length).assertEqual(3);
      input.stop();
    });

    it('pans and pinches only gestures started inside the map', 0, () => {
      const gesture = new ProjectionMapGesture();
      const bounds: ProjectionMapBounds = { left: 100, top: 50, right: 900, bottom: 450 };
      expect(gesture.update([{ id: 0, down: true, x: 200, y: 100 }], bounds)).assertUndefined();
      const pan = gesture.update([{ id: 0, down: true, x: 220, y: 110 }], bounds);
      expect(pan?.scrollX).assertEqual(-20);
      expect(pan?.scrollY).assertEqual(-10);
      expect(gesture.update([
        { id: 0, down: true, x: 220, y: 110 }, { id: 1, down: true, x: 320, y: 110 }
      ], bounds)).assertUndefined();
      const pinch = gesture.update([
        { id: 0, down: true, x: 170, y: 110 }, { id: 1, down: true, x: 370, y: 110 }
      ], bounds);
      expect(pinch?.zoom).assertEqual(1);
      expect(pinch?.focusX).assertEqual(170);
      gesture.update([], bounds);
      expect(gesture.update([{ id: 0, down: true, x: 20, y: 100 }], bounds)).assertUndefined();
      expect(gesture.update([{ id: 0, down: true, x: 220, y: 100 }], bounds)).assertUndefined();
      gesture.update([], bounds);
      expect(gesture.update([{ id: 0, down: true, x: 220, y: 100 }], bounds)).assertUndefined();
      expect(gesture.update([{ id: 0, down: true, x: 230, y: 100 }], bounds)?.scrollX).assertEqual(-10);
    });

    it('does not pan the map for tap jitter and preserves the first drag delta', 0, () => {
      const gesture = new ProjectionMapGesture();
      const bounds: ProjectionMapBounds = { left: 100, top: 50, right: 900, bottom: 450 };
      expect(gesture.update([{ id: 0, down: true, x: 200, y: 100 }], bounds, 40)).assertUndefined();
      expect(gesture.update([{ id: 0, down: true, x: 205, y: 103 }], bounds, 40)).assertUndefined();
      expect(gesture.update([{ id: 0, down: true, x: 235, y: 100 }], bounds, 40)).assertUndefined();
      expect(gesture.update([{ id: 0, down: true, x: 240, y: 100 }], bounds, 40)).assertUndefined();
      const pan = gesture.update([{ id: 0, down: true, x: 241, y: 100 }], bounds, 40);
      expect(pan?.scrollX).assertEqual(-41);
      expect(gesture.update([{ id: 0, down: true, x: 242, y: 100 }], bounds, 40)?.scrollX).assertEqual(-1);
      gesture.update([], bounds, 40);
      expect(gesture.update([{ id: 0, down: true, x: 220, y: 100 }], bounds, 40)).assertUndefined();
      expect(gesture.update([{ id: 0, down: true, x: 225, y: 100 }], bounds, 40)).assertUndefined();
      expect(gesture.update([], bounds, 40)).assertUndefined();
    });

    it('decodes iAP2 link frames split across RFCOMM reads', 0, () => {
      const frame: Iap2LinkFrame = {
        control: 0x40,
        sequence: 12,
        acknowledgement: 9,
        sessionId: 10,
        payload: new Uint8Array([0x40, 0x40, 0x00, 0x06, 0x57, 0x03])
      };
      const encoded = encodeIap2LinkFrame(frame);
      const decoder = new Iap2LinkDecoder();
      expect(decoder.push(encoded.slice(0, 7)).length).assertEqual(0);
      const decoded = decoder.push(encoded.slice(7));
      expect(decoded.length).assertEqual(1);
      expect(decoded[0].sequence).assertEqual(frame.sequence);
      expect(decoded[0].sessionId).assertEqual(frame.sessionId);
    });

    it('recognizes split detection markers without treating frame payload as a marker', 0, async (): Promise<void> => {
      const sent: Uint8Array[] = [];
      const session = new Iap2SenderSession(
        async (bytes: Uint8Array): Promise<void> => { sent.push(bytes.slice()); },
        (): void => {}, (): void => {}, (): void => {},
        '34:86:DA:86:BB:96', 'test-device', 'test-uuid'
      );
      const marker = new Uint8Array([0xff, 0x55, 0x02, 0x00, 0xee, 0x10]);
      await session.start();
      sent.length = 0;
      await session.receive(marker.slice(0, 3));
      expect(sent.length).assertEqual(0);
      await session.receive(concatBytes(marker.slice(3), encodeIap2LinkFrame({
        control: 0x80, sequence: 70, acknowledgement: 0, sessionId: 0,
        payload: encodeIap2SyncPayload(1)
      })));
      expect(sent[0].length).assertEqual(marker.length);
      expect(sent[0].every((value: number, index: number): boolean => value === marker[index])).assertTrue();
      const synAck = new Iap2LinkDecoder().push(sent[1]);
      expect(synAck[0].control).assertEqual(0xc0);
      expect(synAck[0].sequence).assertEqual(99);
      expect(synAck[0].acknowledgement).assertEqual(70);
      const count = sent.length;
      await session.receive(encodeIap2LinkFrame({
        control: 0x40, sequence: 71, acknowledgement: 0, sessionId: 2, payload: marker
      }));
      expect(sent.length).assertEqual(count + 1);
      expect(sent[count].length).assertEqual(9);
      session.cancel();
    });

    it('does not echo repeated detection markers or change sequence for a retransmitted SYN', 0,
      async (): Promise<void> => {
        const sent: Uint8Array[] = [];
        const session = new Iap2SenderSession(
          async (bytes: Uint8Array): Promise<void> => { sent.push(bytes.slice()); },
          (): void => {}, (): void => {}, (): void => {},
          '34:86:DA:86:BB:96', 'test-device', 'test-uuid'
        );
        const marker = new Uint8Array([0xff, 0x55, 0x02, 0x00, 0xee, 0x10]);
        const sync = encodeIap2LinkFrame({
          control: 0x80, sequence: 70, acknowledgement: 0, sessionId: 0,
          payload: encodeIap2SyncPayload(1)
        });
        await session.start();
        await session.receive(marker);
        const afterMarker = sent.length;
        await session.receive(marker);
        expect(sent.length).assertEqual(afterMarker);
        await session.receive(sync);
        const decoder = new Iap2LinkDecoder();
        const initialFrames = sent.flatMap((bytes: Uint8Array): Iap2LinkFrame[] => decoder.push(bytes));
        const response = initialFrames.find((frame: Iap2LinkFrame): boolean => frame.control === 0xc0);
        const afterSync = sent.length;
        await session.receive(sync);
        expect(sent.length).assertEqual(afterSync + 1);
        const duplicate = decoder.push(sent[afterSync]);
        expect(duplicate[0].sequence).assertEqual(response?.sequence);
        session.cancel();
      });

    it('retries iAP2 detection and stops retries after cancellation', 0, async (): Promise<void> => {
      const sent: Uint8Array[] = [];
      const session = new Iap2SenderSession(
        async (bytes: Uint8Array): Promise<void> => { sent.push(bytes.slice()); },
        (): void => {}, (): void => {}, (): void => {},
        '34:86:DA:86:BB:96', 'test-device', 'test-uuid'
      );
      await session.start();
      const initialCount = sent.length;
      await new Promise<void>((resolve: () => void): void => { setTimeout(resolve, 1200); });
      expect(sent.length).assertEqual(initialCount + 1);
      expect(sent[initialCount].length).assertEqual(6);
      expect(new Iap2LinkDecoder().push(sent[initialCount]).length).assertEqual(0);
      session.cancel();
      const cancelledCount = sent.length;
      await new Promise<void>((resolve: () => void): void => { setTimeout(resolve, 1200); });
      expect(sent.length).assertEqual(cancelledCount);
    });

    it('restarts iAP2 negotiation when the accessory repeats detection', 0, async (): Promise<void> => {
      const sent: Uint8Array[] = [];
      const session = new Iap2SenderSession(
        async (bytes: Uint8Array): Promise<void> => { sent.push(bytes.slice()); },
        (): void => {}, (): void => {}, (): void => {},
        '34:86:DA:86:BB:96', 'test-device', 'test-uuid'
      );
      const marker = new Uint8Array([0xff, 0x55, 0x02, 0x00, 0xee, 0x10]);
      const sync = encodeIap2LinkFrame({
        control: 0x80, sequence: 70, acknowledgement: 0, sessionId: 0,
        payload: encodeIap2SyncPayload(1)
      });
      await session.start();
      await session.receive(sync);
      sent.length = 0;
      await session.receive(concatBytes(marker, sync));
      const decoder = new Iap2LinkDecoder();
      const frames = sent.flatMap((bytes: Uint8Array): Iap2LinkFrame[] => decoder.push(bytes));
      expect(sent[0].length).assertEqual(marker.length);
      expect(frames.some((frame: Iap2LinkFrame): boolean =>
        frame.payload.length >= 6 && frame.payload[4] === 0x1d && frame.payload[5] === 0x00)).assertTrue();
      expect(session.isAuthenticationComplete).assertFalse();
      session.cancel();
    });

    it('encodes and decodes pure iAP2 acknowledgements as 9-byte frames', 0, () => {
      const frame: Iap2LinkFrame = {
        control: 0x40,
        sequence: 12,
        acknowledgement: 9,
        sessionId: 0,
        payload: new Uint8Array(0)
      };
      const encoded = encodeIap2LinkFrame(frame);
      const decoded = new Iap2LinkDecoder().push(encoded);
      expect(encoded.length).assertEqual(9);
      expect(decoded.length).assertEqual(1);
      expect(decoded[0].payload.length).assertEqual(0);
      expect(decoded[0].acknowledgement).assertEqual(9);
    });

    it('reuses the data sequence for ACK-only frames and rejects EAK as CSM', 0, async (): Promise<void> => {
      const sent: Uint8Array[] = [];
      const session = new Iap2SenderSession(
        async (bytes: Uint8Array): Promise<void> => { sent.push(bytes.slice()); },
        (): void => {},
        (): void => {},
        (): void => {},
        '34:86:DA:86:BB:96',
        'test-device',
        'test-uuid'
      );
      const decoder = new Iap2LinkDecoder();
      let sentOffset = 0;
      const decodeNewOutput = (): Iap2LinkFrame[] => {
        const frames: Iap2LinkFrame[] = [];
        while (sentOffset < sent.length) {
          frames.push(...decoder.push(sent[sentOffset]));
          sentOffset++;
        }
        return frames;
      };

      await session.start();
      decodeNewOutput();
      await session.receive(encodeIap2LinkFrame({
        control: 0x80,
        sequence: 169,
        acknowledgement: 0,
        sessionId: 0,
        payload: encodeIap2SyncPayload(1)
      }));
      const negotiationOutput = decodeNewOutput();
      const identificationStart = negotiationOutput.find((frame: Iap2LinkFrame) =>
        frame.payload.length >= 6 && frame.payload[4] === 0x1d && frame.payload[5] === 0x00
      );
      expect(identificationStart !== undefined).assertTrue();

      const identityBody = concatBytes(
        encodeIap2Parameter(6, new Uint8Array([0xaa, 0x06])),
        encodeIap2Parameter(7, new Uint8Array([0x43, 0x00]))
      );
      await session.receive(encodeIap2LinkFrame({
        control: 0x40,
        sequence: 170,
        acknowledgement: identificationStart?.sequence ?? 0,
        sessionId: 1,
        payload: encodeIap2Control(0x1d01, identityBody)
      }));
      const identityOutput = decodeNewOutput();
      const linkAcknowledgement = identityOutput.find((frame: Iap2LinkFrame) =>
        frame.control === 0x40 && frame.payload.length === 0
      );
      const certificateRequest = identityOutput.find((frame: Iap2LinkFrame) =>
        frame.payload.length >= 6 && frame.payload[4] === 0xaa && frame.payload[5] === 0x00
      );
      expect(linkAcknowledgement?.sequence).assertEqual(identificationStart?.sequence);
      expect(session.isAuthenticationComplete).assertFalse();
      expect(certificateRequest !== undefined).assertTrue();
      expect(identityOutput.some((frame: Iap2LinkFrame) =>
        frame.payload.length >= 6 && frame.payload[4] === 0xaa && frame.payload[5] === 0x05
      )).assertFalse();

      await session.receive(encodeIap2LinkFrame({
        control: 0x40,
        sequence: 170,
        acknowledgement: identificationStart?.sequence ?? 0,
        sessionId: 1,
        payload: encodeIap2Control(0x1d01, identityBody)
      }));
      const duplicateOutput = decodeNewOutput();
      expect(duplicateOutput.length).assertEqual(1);
      expect(duplicateOutput[0].payload.length).assertEqual(0);
      expect(duplicateOutput[0].acknowledgement).assertEqual(170);

      const outputCount = sent.length;
      await session.receive(encodeIap2LinkFrame({
        control: 0x60,
        sequence: 171,
        acknowledgement: identificationStart?.sequence ?? 0,
        sessionId: 0,
        payload: new Uint8Array([certificateRequest?.sequence ?? 0])
      }));
      expect(sent.length).assertEqual(outputCount + 1);
      const retransmissions = decodeNewOutput();
      expect(retransmissions.length).assertEqual(1);
      expect(retransmissions[0].sequence).assertEqual(certificateRequest?.sequence);
      expect(retransmissions[0].payload[4]).assertEqual(0xaa);
      expect(retransmissions[0].payload[5]).assertEqual(0x00);
      session.cancel();
    });

    it('requests missing iAP2 frames and delivers buffered data in sequence', 0, async (): Promise<void> => {
      const sent: Uint8Array[] = [];
      const session = new Iap2SenderSession(
        async (bytes: Uint8Array): Promise<void> => { sent.push(bytes.slice()); },
        (): void => {}, (): void => {}, (): void => {},
        '34:86:DA:86:BB:96', 'test-device', 'test-uuid'
      );
      const decoder = new Iap2LinkDecoder();
      await session.start();
      await session.receive(encodeIap2LinkFrame({
        control: 0x80, sequence: 254, acknowledgement: 0, sessionId: 0,
        payload: encodeIap2SyncPayload(1)
      }));
      sent.length = 0;
      const identity = encodeIap2Control(0x1d01, new Uint8Array(0));
      await session.receive(encodeIap2LinkFrame({
        control: 0x40, sequence: 0, acknowledgement: 0, sessionId: 1,
        payload: identity.slice(3)
      }));
      let output = sent.flatMap((bytes: Uint8Array): Iap2LinkFrame[] => decoder.push(bytes));
      expect(output.length).assertEqual(1);
      expect(output[0].control).assertEqual(0x60);
      expect(output[0].acknowledgement).assertEqual(254);
      expect(output[0].payload[0]).assertEqual(255);
      sent.length = 0;
      await session.receive(encodeIap2LinkFrame({
        control: 0x40, sequence: 255, acknowledgement: 0, sessionId: 1,
        payload: identity.slice(0, 3)
      }));
      output = sent.flatMap((bytes: Uint8Array): Iap2LinkFrame[] => decoder.push(bytes));
      expect(output.some((frame: Iap2LinkFrame): boolean =>
        frame.payload.length >= 6 && frame.payload[4] === 0xaa && frame.payload[5] === 0x00
      )).assertTrue();
      session.cancel();
    });

    it('reports malformed MFi certificates to the accessory as AA04', 0, async (): Promise<void> => {
      const sent: Uint8Array[] = [];
      const session = new Iap2SenderSession(
        async (bytes: Uint8Array): Promise<void> => { sent.push(bytes.slice()); },
        (): void => {}, (): void => {}, (): void => {},
        '34:86:DA:86:BB:96', 'test-device', 'test-uuid'
      );
      await session.start();
      await session.receive(encodeIap2LinkFrame({
        control: 0x80, sequence: 10, acknowledgement: 0, sessionId: 0, payload: encodeIap2SyncPayload(1)
      }));
      sent.length = 0;
      await session.receive(encodeIap2LinkFrame({
        control: 0x40, sequence: 11, acknowledgement: 0, sessionId: 1,
        payload: encodeIap2Control(0xaa01, new Uint8Array(0))
      }));
      const decoder = new Iap2LinkDecoder();
      const frames: Iap2LinkFrame[] = [];
      for (const bytes of sent) {
        frames.push(...decoder.push(bytes));
      }
      expect(frames.some((frame: Iap2LinkFrame): boolean =>
        frame.payload.length >= 6 && frame.payload[4] === 0xaa && frame.payload[5] === 0x04
      )).assertTrue();
      expect(session.isAuthenticationComplete).assertFalse();
      session.cancel();
    });

    it('terminates iAP2 on reset and ignores subsequent data', 0, async (): Promise<void> => {
      const sent: Uint8Array[] = [];
      const session = new Iap2SenderSession(
        async (bytes: Uint8Array): Promise<void> => { sent.push(bytes.slice()); },
        (): void => {}, (): void => {}, (): void => {},
        '34:86:DA:86:BB:96', 'test-device', 'test-uuid'
      );
      await session.start();
      let resetReported = false;
      try {
        await session.receive(encodeIap2LinkFrame({
          control: 0x10, sequence: 0, acknowledgement: 0, sessionId: 0, payload: new Uint8Array(0)
        }));
      } catch (_error) {
        resetReported = true;
      }
      expect(resetReported).assertTrue();
      expect(session.isAuthenticationComplete).assertFalse();
      const outputCount = sent.length;
      await session.receive(encodeIap2LinkFrame({
        control: 0x80, sequence: 1, acknowledgement: 0, sessionId: 0, payload: encodeIap2SyncPayload(1)
      }));
      expect(sent.length).assertEqual(outputCount);
    });

    it('probes legacy Wi-Fi for unknown or sparse accessory capabilities', 0, () => {
      expect(shouldProbeLegacyWifi(undefined, undefined)).assertTrue();
      expect(shouldProbeLegacyWifi([0x4301, 0x6800], [0x4300, 0x4e09, 0x4e0a, 0x4e0b, 0x4e0c]))
        .assertTrue();
      expect(shouldProbeLegacyWifi([], [])).assertFalse();
      expect(shouldProbeLegacyWifi([1, 2, 3, 4, 5], [6, 7, 8, 9, 10])).assertFalse();
      expect(shouldProbeLegacyWifi([0x5703], [])).assertTrue();
    });

    it('verifies raw P-256 MFi signatures without hashing the challenge again', 0, () => {
      const fromHex = (hex: string): Uint8Array => {
        const bytes = new Uint8Array(hex.length / 2);
        for (let index = 0; index < bytes.length; index++) {
          bytes[index] = parseInt(hex.slice(index * 2, index * 2 + 2), 16);
        }
        return bytes;
      };
      const publicKey = fromHex(
        '3059301306072a8648ce3d020106082a8648ce3d03010703420004' +
        '8e533b6fa0bf7b4625bb30667c01fb607ef9f8b8a80fef5b300628703187b2a3' +
        '73eb1dbde03318366d069f83a6f5900053c73633cb041b21c55e1a86c1f400b4'
      );
      const signature = fromHex(
        'b2415773cc980676059a7b930cc8ff2f29bdee8de7f5379f3ea3ad4ea3f0435f' +
        'aa1fb2c6830f9e5009a093366b93220b76da3e580a2d2e6a1faa0e46592f1a9f'
      );
      const alternate = fromHex(
        'b2415773cc980676059a7b930cc8ff2f29bdee8de7f5379f3ea3ad4ea3f0435f' +
        '55e04d387cf061b0f65f6cc9946cddf4460cbc559cea701ad40fbc7ca3340ab2'
      );
      const challenge = new Uint8Array(32).fill(42);
      expect(verifyRawMfiP256Signature(publicKey, challenge, signature)).assertTrue();
      expect(verifyRawMfiP256Signature(publicKey, challenge, alternate)).assertTrue();
      challenge[0] ^= 1;
      expect(verifyRawMfiP256Signature(publicKey, challenge, signature)).assertFalse();
      challenge[0] ^= 1;
      signature[0] ^= 1;
      expect(verifyRawMfiP256Signature(publicKey, challenge, signature)).assertFalse();
      expect(verifyRawMfiP256Signature(publicKey.slice(0, 20), challenge, alternate)).assertFalse();
    });

    it('continues after an unverified challenge only in explicit diagnostic mode', 0, () => {
      const strictVerifier = new MfiVerifier((): void => {});
      const diagnosticVerifier = new MfiVerifier((): void => {}, false, [], undefined, undefined, true);
      expect(strictVerifier.canContinueAfterChallengeVerification(false)).assertFalse();
      expect(strictVerifier.canContinueAfterChallengeVerification(true)).assertTrue();
      expect(diagnosticVerifier.canContinueAfterChallengeVerification(false)).assertTrue();
      expect(diagnosticVerifier.canContinueAfterChallengeVerification(true)).assertTrue();
    });

    it('allows MFi fingerprint pinning only for certificate-chain trust failures', 0, () => {
      expect(isMfiPinEligiblePkixFailure('unable to get local issuer certificate')).assertTrue();
      expect(isMfiPinEligiblePkixFailure('untrusted certificate')).assertTrue();
      expect(isMfiPinEligiblePkixFailure('key cannot be used for a digital signature')).assertFalse();
      expect(isMfiPinEligiblePkixFailure('unsupported critical extension')).assertFalse();
      expect(isMfiPinEligiblePkixFailure('19030005')).assertFalse();
    });

    it('keeps protocol log history bounded and chronological', 0, () => {
      let lines: string[] = [];
      for (let index = 0; index < MAX_CONNECTION_LOG_LINES + 2; index++) {
        lines = appendConnectionLog(lines, `line-${index}`);
      }
      expect(lines.length).assertEqual(MAX_CONNECTION_LOG_LINES);
      expect(lines[0]).assertEqual('line-2');
      expect(lines[lines.length - 1]).assertEqual(`line-${MAX_CONNECTION_LOG_LINES + 1}`);
    });

    it('adds structured metadata and redacts protocol secrets', 0, () => {
      let line = '';
      const logger = new ProtocolLogger((entry: string): void => {
        line = entry;
      });
      logger.write('wifi', 'password=example-secret privateKey: hidden-key', 'WARN');
      expect(line.startsWith('[')).assertTrue();
      expect(line.includes('] WARN wifi:')).assertTrue();
      expect(line.includes('#')).assertFalse();
      expect(line.includes('[REDACTED]')).assertTrue();
      expect(line.includes('example-secret')).assertFalse();
      expect(line.includes('hidden-key')).assertFalse();
    });

    it('formats log timestamps in the device local timezone', 0, () => {
      const date = new Date(2026, 9, 27, 12, 34, 56, 789);
      const timestamp = formatLocalTimestamp(date);
      const offsetMinutes = -date.getTimezoneOffset();
      const offsetSign = offsetMinutes >= 0 ? '+' : '-';
      const offsetMagnitude = Math.abs(offsetMinutes);
      const expectedOffset = `${offsetSign}${Math.floor(offsetMagnitude / 60).toString().padStart(2, '0')}:` +
        `${(offsetMagnitude % 60).toString().padStart(2, '0')}`;
      expect(timestamp.startsWith('2026-10-27T12:34:56.789')).assertTrue();
      expect(timestamp.endsWith(expectedOffset)).assertTrue();
      expect(timestamp.endsWith('Z')).assertFalse();
      expect(formatLocalDateKey(date)).assertEqual('2026-10-27');
      expect(formatLocalClock(date)).assertEqual('[12:34:56.789]');
    });

    it('formats JSON protocol events and redacts sensitive field names and assignments', 0, () => {
      const event = formatProtocolEvent('wifi.connect',
        'ssid', 'DIRECT-example',
        'securityType', 2,
        'passphrase', 'must-not-appear',
        'detail', 'challenge=private-challenge'
      );
      expect(event.includes('"event":"wifi.connect"')).assertTrue();
      expect(event.includes('"ssid":"DIRECT-example"')).assertTrue();
      expect(event.includes('[REDACTED]')).assertTrue();
      expect(event.includes('must-not-appear')).assertFalse();
      expect(event.includes('private-challenge')).assertFalse();
    });

    it('logs full ordinary link payloads and redacts sensitive CSM payloads', 0, () => {
      const ordinaryBody = new Uint8Array(300).fill(0x5a);
      const ordinary = formatIap2LinkPayloadDiagnostic('RX', encodeIap2Control(0x1d01, ordinaryBody));
      expect(ordinary.includes('body=300B hex=')).assertTrue();
      expect(ordinary.includes('bytes omitted')).assertFalse();

      const signature = new Uint8Array([0xde, 0xad, 0xbe, 0xef]);
      const mfi = formatIap2LinkPayloadDiagnostic('RX', encodeIap2Control(
        0xaa03,
        encodeIap2Parameter(0, signature)
      ));
      expect(mfi.includes('[REDACTED:MFi]')).assertTrue();
      expect(mfi.includes('de ad be ef')).assertFalse();

      const password = encodeUtf8('private-wifi-password');
      const wifi = formatIap2LinkPayloadDiagnostic('RX', encodeIap2Control(
        0x5703,
        encodeIap2Parameter(2, password)
      ));
      expect(wifi.includes('[REDACTED:Wi-Fi password]')).assertTrue();
      expect(wifi.includes('private-wifi-password')).assertFalse();
    });

    it('keeps absent or malformed iAP2 capability lists unknown', 0, () => {
      expect(readMessageIds(undefined)).assertUndefined();
      expect(readMessageIds(new Uint8Array([0x43]))).assertUndefined();
      const ids = readMessageIds(new Uint8Array([0x43, 0x00, 0x57, 0x02]));
      expect(ids?.length).assertEqual(2);
      expect(ids?.[0]).assertEqual(0x4300);
      expect(ids?.[1]).assertEqual(0x5702);
    });

    it('combines the xcertplay BAA leaf and intermediate certificate parameters', 0, () => {
      const leaf = new Uint8Array([0x30, 0x03, 0x02, 0x01, 0x01]);
      const intermediate = new Uint8Array([0x30, 0x03, 0x02, 0x01, 0x02]);
      const body = concatBytes(
        encodeIap2Parameter(0, leaf),
        encodeIap2Parameter(1, new Uint8Array([1])),
        encodeIap2Parameter(2, intermediate)
      );
      const parsed = parseMfiCertificatePayload(body);
      expect(parsed.length).assertEqual(leaf.length + intermediate.length);
      expect(parsed[0]).assertEqual(leaf[0]);
      expect(parsed[leaf.length]).assertEqual(intermediate[0]);
    });

    it('decodes compact unsigned plist integers and preserves signed 64-bit values', 0, () => {
      const fixtures: Uint8Array[] = [
        new Uint8Array([0x10, 0xff]),
        new Uint8Array([0x11, 0xc3, 0x50]),
        new Uint8Array([0x12, 0x80, 0x00, 0x00, 0x00])
      ];
      const expected: bigint[] = [BigInt(255), BigInt(50000), BigInt('2147483648')];
      for (let index = 0; index < fixtures.length; index++) {
        const fixture = fixtures[index];
        const bytes = new Uint8Array(8 + fixture.length + 1 + 32);
        bytes.set(encodeUtf8('bplist00'), 0);
        bytes.set(fixture, 8);
        bytes[8 + fixture.length] = 8;
        const trailer = bytes.length - 32;
        bytes[trailer + 6] = 1;
        bytes[trailer + 7] = 1;
        bytes[trailer + 15] = 1;
        bytes[trailer + 31] = 8 + fixture.length;
        expect(BinaryPlist.decode(bytes).integerValue.toString()).assertEqual(expected[index].toString());
      }
      const negative = BinaryPlist.encode(PlistNode.integer(-1));
      expect(negative[8]).assertEqual(0x13);
      expect(BinaryPlist.decode(negative).integerValue.toString()).assertEqual('-1');
    });

    it('raises low H.264 SPS level to 4.0 without lowering higher levels', 0, () => {
      const lowLevelSps = new Uint8Array([0x67, 0x64, 0x00, 0x1f, 0x80]);
      const highLevelSps = new Uint8Array([0x67, 0x64, 0x00, 0x2a, 0x80]);
      expect(patchH264SpsLevel(lowLevelSps)[3]).assertEqual(0x28);
      expect(lowLevelSps[3]).assertEqual(0x1f);
      expect(patchH264SpsLevel(highLevelSps)).assertEqual(highLevelSps);
    });
  });
}