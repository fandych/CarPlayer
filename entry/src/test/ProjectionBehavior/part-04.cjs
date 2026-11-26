const { assert, fs, path, vm, test, ts, sourceRoot, audioSenderFixture, loadEts, loadMethods,
  loadProjectionSettingsController, videoSenderFixture } = require('../ProjectionBehaviorSupport.cjs');

test('session lifecycle tokens advance exactly and reject malformed values in ArkTS', () => {
  const { advanceSessionGeneration, isCurrentSessionGeneration } =
    loadEts('session/NativeSessionLifecycle.ets');
  const first = advanceSessionGeneration();
  assert.equal(isCurrentSessionGeneration(first), true);
  const second = advanceSessionGeneration();
  assert.notEqual(first, second);
  assert.equal(isCurrentSessionGeneration(first), false);
  assert.equal(isCurrentSessionGeneration(second), true);
  assert.throws(() => isCurrentSessionGeneration('0'), /Invalid session generation token/);
  assert.throws(() => isCurrentSessionGeneration('18446744073709551616'), /Invalid session generation token/);
});

test('recoverable CMS signer-certificate fallback is classified as a warning', () => {
  const Target = loadMethods('pages/Index.ets', 'Index', ['resolveProtocolLogLevel']);
  const target = new Target();
  assert.equal(target.resolveProtocolLogLevel(
    'WARN: CMS SIGNER_CERTS extraction unavailable; using available certificate chain (1 certificate(s))',
    'INFO'
  ), 'WARN');
});

test('AirPlay requests /info with a plist body only after initial SETUP', () => {
  const pairingSource = fs.readFileSync(path.join(sourceRoot, 'airplay/AirPlayPairingClient.ets'), 'utf8');
  const sessionSource = [
    'AirPlayMediaSessionStart.ets',
    'AirPlayMediaSessionLifecycle.ets'
  ].map(file => fs.readFileSync(path.join(sourceRoot, 'airplay/media', file), 'utf8')).join('\n');
  const rtspSource = fs.readFileSync(path.join(sourceRoot, 'airplay/AirPlayRtspClient.ets'), 'utf8');
  assert.doesNotMatch(pairingSource, /['"]\/info['"]/);
  const setupPosition = sessionSource.indexOf("'initial session SETUP'");
  const infoPosition = sessionSource.indexOf("'receiver /info after initial session SETUP'");
  assert.ok(setupPosition >= 0);
  assert.ok(infoPosition > setupPosition);
  assert.match(sessionSource,
    /this\.request\(\s*'GET',\s*'\/info',\s*BinaryPlist\.encode\(PlistNode\.dictionary\(new Map<string, PlistNode>\(\)\)\)/);
  assert.match(sessionSource, /contentType: 'application\/x-apple-binary-plist'/);
  assert.match(rtspSource, /RTSP_REQUEST_TIMEOUT_MS:\s*number\s*=\s*10_000/);
  assert.match(rtspSource, /'bodySummary',\s*formatRtspBodySummary/);
  assert.doesNotMatch(sessionSource, /client\.request\(\s*'OPTIONS'/);
  assert.doesNotMatch(rtspSource, /X-Apple-Device-ID|X-Apple-Client-Name|Connection: keep-alive/);
});

test('socket error formatting preserves platform error codes and messages', () => {
  const { formatNetworkError } = loadEts('network/WifiNetworkErrors.ets', {}, 'formatNetworkError');
  assert.equal(formatNetworkError(new Error('connection refused')), 'connection refused');
  assert.equal(formatNetworkError({ code: 2300026, message: 'link-local scope unavailable' }),
    'code=2300026: link-local scope unavailable');
});

test('Bluetooth audio preference defaults off and initialization preserves the saved selection', () => {
  const source = fs.readFileSync(path.join(sourceRoot, 'video/ProjectionSettings.ets'), 'utf8');
  const javascript = ts.transpileModule(source, {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
  }).outputText;
  const requireSettingsModule = name => {
    if (name === './ProjectionSettingsTypes') {
      return loadEts('video/ProjectionSettingsTypes.ets');
    }
    assert.equal(name, './ProjectionSplitSettings');
    return loadEts('video/ProjectionSplitSettings.ets', {
      './ProjectionSettingsTypes': loadEts('video/ProjectionSettingsTypes.ets')
    });
  };
  for (const saved of [undefined, true, false]) {
    const stored = new Map();
    if (saved !== undefined) stored.set('carplayUseBluetoothAudio', saved);
    const calls = [];
    const exports = {};
    vm.runInNewContext(javascript, {
      exports,
      require: requireSettingsModule,
      PersistentStorage: { persistProp(key, value) {
        calls.push(key);
        if (!stored.has(key)) stored.set(key, value);
      } }
    });
    exports.initializeProjectionSettings();
    exports.initializeProjectionSettings();
    assert.equal(stored.get('carplayUseBluetoothAudio'), saved ?? false);
    assert.equal(calls.filter(key => key === 'carplayUseBluetoothAudio').length, 1);
    assert.equal(stored.get('carplayDockPosition'), 'left');
    assert.equal(stored.get('carplayTheme'), 'aurora');
    assert.equal(stored.get('carplayAccent'), '#0A84FF');
    assert.equal(stored.get('carplayDayNightMode'), 'NIGHT');
    assert.equal(calls.filter(key => key === 'carplayDockPosition').length, 1);
    assert.equal(calls.filter(key => key === 'carplayDayNightMode').length, 1);
  }

  const savedTheme = new Map([['carplayTheme', 'forest'], ['carplayAccent', '#FF9F0A']]);
  const preservedExports = {};
  vm.runInNewContext(javascript, {
    exports: preservedExports,
    require: requireSettingsModule,
    PersistentStorage: {
      persistProp(key, value) {
        if (!savedTheme.has(key)) savedTheme.set(key, value);
      }
    }
  });
  preservedExports.initializeProjectionSettings();
  assert.equal(savedTheme.get('carplayTheme'), 'forest');
  assert.equal(savedTheme.get('carplayAccent'), '#FF9F0A');
});

test('vehicle Bluetooth audio touch area is active only on the settings page', () => {
  const Target = loadMethods('pages/ProjectionDashboard.ets', 'ProjectionDashboard', [
    'touchHandler', 'canvasPixelToContentPoint'
  ], {
    AppStorage: { get: key => key === 'carplayProjectionHomeActive' ? true : 7 }
  });
  const target = new Target();
  const { ProjectionTouchRouter } = loadEts('pages/ProjectionTouchRouter.ets');
  target.touchRouter = new ProjectionTouchRouter();
  let toggles = 0;
  target.getUIContext = () => ({ px2vp: value => value });
  target.canvasPixelToContentPoint = (x, y) => ({ x, y });
  target.touchRouter.touchBounds = new Map([['settings', { left: 0, top: 0, right: 20, bottom: 20 }]]);
  target.touchRouter.touchAreas = new Map([['settings:bluetoothAudio', {
    group: 'settings', left: 0, top: 0, right: 20, bottom: 20, action: () => { toggles++; }
  }]]);
  const event = { data: { displayId: 7, startX: 10, startY: 10, endX: 10, endY: 10 } };
  for (const view of ['home', 'apps', 'themes']) {
    target.dashboardView = view;
    target.touchHandler(event);
  }
  assert.equal(toggles, 0);
  target.dashboardView = 'settings';
  target.touchHandler(event);
  assert.equal(toggles, 1);
});

test('third-party launch targets come from the reference and URI probes control availability', async () => {
  const { PROJECTION_APP_CANDIDATES, PROJECTION_VEHICLE_APPS, resolveProjectionApps } =
    loadEts('pages/ProjectionAppCatalog.ets');
  assert.equal(PROJECTION_APP_CANDIDATES.length, 10);
  for (const app of PROJECTION_APP_CANDIDATES) {
    assert.ok(app.icon, app.label);
    assert.ok(app.category === 'map' || app.category === 'music');
    assert.match(app.uri, /^carplay-client:\/\/v1\/apps\//);
    assert.equal(app.launchState, 'UNVERIFIED');
  }
  const amap = PROJECTION_APP_CANDIDATES.find(app => app.appId === 'amap');
  assert.equal(amap.launchTarget.kind, 'ability');
  assert.equal(amap.launchTarget.bundleName, 'com.amap.hmapp');
  assert.equal(amap.launchTarget.abilityName, 'EntryAbility');
  assert.equal(amap.launchTarget.probeUri, 'amapuri://');
  assert.equal(PROJECTION_APP_CANDIDATES.find(app => app.appId === 'baidu-map').launchTarget.uri,
    'baidumap://map');
  assert.equal(PROJECTION_APP_CANDIDATES.find(app => app.appId === 'tencent-map').launchTarget.uri,
    'qqmap://');
  const huaweiMusic = PROJECTION_APP_CANDIDATES.find(app => app.appId === 'huawei-music');
  assert.equal(huaweiMusic.bundleName, 'com.huawei.hmsapp.music');
  assert.equal(huaweiMusic.abilityName, 'MainAbility');
  assert.equal(huaweiMusic.launchTarget.uri, 'hwmusic://com.huawei.hmsapp.music');
  const petal = PROJECTION_APP_CANDIDATES.find(app => app.appId === 'petal-maps');
  assert.equal(petal.label, '地图');
  assert.equal(petal.bundleName, 'com.huawei.hmos.maps.app');
  assert.equal(petal.launchTarget.uri, 'petalmaps://');
  const tangxin = PROJECTION_APP_CANDIDATES.find(app => app.appId === 'tangshui-music');
  assert.equal(tangxin.bundleName, 'com.salmon.sweetmusic');
  assert.equal(tangxin.launchTarget.uri, 'sweetmusic://');
  const kuwo = PROJECTION_APP_CANDIDATES.find(app => app.appId === 'kuwo-music');
  assert.equal(kuwo.bundleName, 'com.hmkuwo.cn');
  assert.equal(kuwo.abilityName, 'KuWoAbility');
  assert.equal(kuwo.launchTarget.uri, 'kwapp://');
  assert.equal(PROJECTION_APP_CANDIDATES.find(app => app.appId === 'kugou-music').launchTarget.uri,
    'kugou://m.kugou.com');
  assert.deepEqual(PROJECTION_VEHICLE_APPS.map(app => app.view), ['receiver', 'settings', 'themes', 'split']);
  const probedLinks = [];
  const resolved = await resolveProjectionApps(uri => {
    probedLinks.push(uri);
    return [
      'amapuri://',
      'baidumap://map',
      'petalmaps://',
      'qqmap://',
      'hwmusic://com.huawei.hmsapp.music',
      'qqmusic://',
      'orpheus://',
      'kugou://m.kugou.com',
      'sweetmusic://',
      'kwapp://'
    ].includes(uri);
  });
  assert.deepEqual(resolved.filter(app => app.launchState === 'VERIFIED').map(app => app.appId),
    ['amap', 'baidu-map', 'petal-maps', 'tencent-map', 'huawei-music', 'qq-music', 'netease-music',
      'kugou-music', 'tangshui-music', 'kuwo-music']);
  assert.ok(probedLinks.includes('amapuri://'));
  assert.ok(probedLinks.includes('baidumap://map'));
  assert.ok(probedLinks.includes('petalmaps://'));
  assert.ok(probedLinks.includes('qqmap://'));
  assert.ok(probedLinks.includes('hwmusic://com.huawei.hmsapp.music'));
  assert.ok(probedLinks.includes('qqmusic://'));
  assert.ok(probedLinks.includes('orpheus://'));
  assert.ok(probedLinks.includes('kugou://m.kugou.com'));
  assert.ok(probedLinks.includes('sweetmusic://'));
  assert.ok(probedLinks.includes('kwapp://'));
  for (const uri of ['snssdk1128://', 'kwai://', 'emoh://eastmoney.com', 'tenvideo2://']) {
    assert.equal(probedLinks.includes(uri), false);
  }
  const moduleManifest = fs.readFileSync(path.join(sourceRoot, '../module.json5'), 'utf8');
  for (const scheme of [
    'amapuri', 'baidumap', 'petalmaps', 'hwmusic', 'qqmap', 'qqmusic', 'orpheus', 'kugou', 'sweetmusic',
    'kwapp'
  ]) {
    assert.match(moduleManifest, new RegExp(`"${scheme}"`), `querySchemes must include ${scheme}`);
  }
  assert.doesNotMatch(moduleManifest, /ohos\.permission\.GET_BUNDLE_INFO/);
  assert.doesNotMatch(moduleManifest, /"snssdk1128"|"kwai"|"emoh"|"tenvideo2"/);
});

test('project branding and legacy app icons use the provided resources', () => {
  const appConfig = JSON.parse(fs.readFileSync(path.join(sourceRoot, '../../../../AppScope/app.json5'), 'utf8'));
  const appStrings = JSON.parse(fs.readFileSync(
    path.join(sourceRoot, '../../../../AppScope/resources/base/element/string.json'), 'utf8'));
  assert.equal(appConfig.app.bundleName, 'com.fandy.carplayer');
  assert.equal(appConfig.app.icon, '$media:logo_512');
  assert.equal(appStrings.string.find(entry => entry.name === 'app_name')?.value, 'CarPlayer');
  assert.ok(fs.existsSync(path.join(sourceRoot, '../../../../AppScope/resources/base/media/logo_512.png')));

  const { PROJECTION_APP_CANDIDATES } = loadEts('pages/ProjectionAppCatalog.ets');
  const legacyIcons = {
    amap: 'app_amap',
    'baidu-map': 'app_baidu',
    'tencent-map': 'app_tencent_map',
    'huawei-music': 'app_huawei_music',
    'qq-music': 'app_qqmusic',
    'netease-music': 'app_netease',
    'kugou-music': 'app_kugou'
  };
  const media = path.join(sourceRoot, '../resources/base/media');
  for (const [appId, iconName] of Object.entries(legacyIcons)) {
    const app = PROJECTION_APP_CANDIDATES.find(candidate => candidate.appId === appId);
    assert.equal(app.icon, `app.media.${iconName}`);
    assert.ok(fs.existsSync(path.join(media, `${iconName}.png`)), `missing icon for ${appId}`);
  }
});
