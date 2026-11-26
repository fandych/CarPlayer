import { it, expect } from '@ohos/hypium';
import { AirPlayHidReportSummaryWindow } from '../main/ets/airplay/AirPlayEventChannel';
import { correlateAirPlayIdentity } from '../main/ets/network/AirPlayIdentityCorrelation';
import { PlistNode } from '../main/ets/airplay/BinaryPlist';
import { extractCarPlayTouchReport, parseCarPlayTouchReport } from '../main/ets/airplay/CarPlayTouchReport';
import { isAirPlayStartReady } from '../main/ets/session/SessionController';
import { activeProjectionMusicApp, findLaunchableProjectionApp, isProjectionAppInstanceMigratable, projectionAppLaunchTarget, ProjectionApp, PROJECTION_APP_CANDIDATES, PROJECTION_MAP_URI, resolveProjectionApps } from '../main/ets/pages/ProjectionAppCatalog';

export default function LocalUnitPart01(): void {
  it('assertContain', 0, () => {
        // Defines a test case. This API supports three parameters: test case name, filter parameter, and test case function.
        let a = 'abc';
        let b = 'b';
        // Defines a variety of assertion methods, which are used to declare expected boolean conditions.
        expect(a).assertContain(b);
        expect(a).assertEqual(a);
      });
  
  it('restores reference app targets and keeps them disabled before device checks', 0, async (): Promise<void> => {
        expect(PROJECTION_APP_CANDIDATES.length).assertEqual(14);
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
  
  it('allows a discovered AirPlay service to release the invite wait', 0, () => {
        expect(isAirPlayStartReady(true, true, false, true)).assertTrue();
        expect(isAirPlayStartReady(true, false, true)).assertTrue();
        expect(isAirPlayStartReady(true, false, false, true)).assertTrue();
        expect(isAirPlayStartReady(true, true, false, false, true)).assertTrue();
        expect(isAirPlayStartReady(true, false, false, false, true)).assertFalse();
        expect(isAirPlayStartReady(false, true, true, true)).assertFalse();
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
}
