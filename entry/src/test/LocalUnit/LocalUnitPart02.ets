import { it, expect } from '@ohos/hypium';
import { isForceKeyFrameCommand } from '../main/ets/airplay/AirPlayMediaSession';
import { PlistNode } from '../main/ets/airplay/BinaryPlist';
import { AirPlayVideoStreamSender, buildAirPlayVideoConfigHeader } from '../main/ets/airplay/AirPlayVideoStream';
import { advanceAudioRtpTimestamp, buildAudioRtpSyncPacket } from '../main/ets/audio/AudioRtpSender';
import { CarPlayTouchInput, CarPlayTouchReport, CarPlayTouchTap } from '../main/ets/video/CarPlayTouchInput';
import { projectionDisplayDensity, projectionDisplayToggleTarget } from '../main/ets/video/CarPlayVirtualDisplay';
import { ProjectionShakeDetector } from '../main/ets/video/ProjectionShakeDetector';
import { ProjectionMapBounds, ProjectionMapGesture } from '../main/ets/video/ProjectionMapGesture';

export default function LocalUnitPart02(): void {
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
}
