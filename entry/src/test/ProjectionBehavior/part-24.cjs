const { assert, fs, path, vm, test, ts, sourceRoot, audioSenderFixture, loadEts, loadMethods,
  loadProjectionSettingsController, videoSenderFixture } = require('../ProjectionBehaviorSupport.cjs');

test('volume control works on systems that do not grant media mute', async () => {
  const calls = [];
  const manager = {
    async isMute() { return false; },
    async mute(type, value) { calls.push(value); throw new Error('mute not permitted'); },
    getVolumeManager() { return { on() {}, off() {} }; }
  };
  const { CarAudioOutput } = loadEts('audio/CarAudioOutput.ets', {
    '@ohos.multimedia.audio': {
      AudioVolumeType: { MEDIA: 3 }, StreamUsage: { STREAM_USAGE_MEDIA: 1 },
      getAudioManager: () => manager
    }
  });
  const route = new CarAudioOutput();
  await route.start();
  await route.stop();
  assert.deepEqual(calls, []);
});

test('phone media volume changes update car gain and the route releases its subscription', async () => {
  let muted = false;
  const systemWrites = [];
  let listener;
  let removed = false;
  const volumeManager = {
    getMaxVolumeByStream() { return 15; },
    getVolumeByStream() { return 9; },
    on(type, usage, callback) { listener = callback; },
    off(type, callback) { removed = callback === listener; }
  };
  const manager = {
    async isMute() { return muted; },
    async mute(type, value) { muted = value; systemWrites.push(value); },
    getVolumeManager() { return volumeManager; }
  };
  const storage = global.AppStorage;
  let value;
  try {
    global.AppStorage = { setOrCreate(name, next) { value = next; } };
    const { CarAudioOutput } = loadEts('audio/CarAudioOutput.ets', {
      '@ohos.multimedia.audio': {
        AudioVolumeType: { MEDIA: 3 }, StreamUsage: { STREAM_USAGE_MEDIA: 1 },
        getAudioManager: () => manager
      }
    });
    const route = new CarAudioOutput();
    await route.start();
    assert.equal(value, 60);
    listener({ volume: 6, updateUi: false });
    assert.equal(value, 40);
    listener({ volume: 10, updateUi: true });
    assert.equal(value, 67);
    listener({ volume: 4, updateUi: true });
    assert.equal(value, 27);
    listener({ volume: 0, updateUi: true });
    assert.equal(value, 0);
    listener({ volume: 1, updateUi: true });
    assert.equal(value, 7);
    await route.stop();
    assert.deepEqual(systemWrites, []);
    assert.equal(removed, true);
    assert.equal(muted, false);
  } finally { global.AppStorage = storage; }
});

test('Dock supports Apps, Home, split and map/music alternative menus', () => {
  const { findLaunchableProjectionApp, isProjectionAppLaunchable } = loadEts('pages/ProjectionAppCatalog.ets');
  const Target = loadMethods('pages/ProjectionDashboard.ets', 'ProjectionDashboard',
    ['activateDock', 'isDashboardHome', 'activeAppHasCategory', 'isDockItemSelected',
      'categoryApp', 'launchableCategoryApp', 'dockItems'], {
      HOME_APP: { uri: 'home' },
      PROJECTION_MAP_URI: 'amap',
      findLaunchableProjectionApp,
      isProjectionAppLaunchable,
      AppStorage: { get: () => -1, setOrCreate() {} }
    });
  const dashboardSource = fs.readFileSync(path.join(sourceRoot, 'pages/ProjectionDashboard.ets'), 'utf8');
  const dockSource = fs.readFileSync(path.join(sourceRoot, 'pages/ProjectionDock.ets'), 'utf8');
  const dockMenuSource = fs.readFileSync(path.join(sourceRoot, 'pages/ProjectionDockMenu.ets'), 'utf8');
  assert.match(dockSource, /Scroll\(this\.scroller\)/);
  assert.match(dockSource, /\.width\(vertical \? '100%' : 64\)/);
  assert.match(dockSource, /\.height\(vertical \? 48 : '100%'\)/);
  const dockItemStart = dockSource.indexOf('private DockItem');
  const dockItemEnd = dockSource.indexOf('@Builder', dockItemStart + 1);
  assert.doesNotMatch(dockSource.slice(dockItemStart, dockItemEnd), /\.layoutWeight\(1\)/);
  assert.match(dockMenuSource, /accessibilityText\(this\.mapOnPhone \? '切换地图到虚拟屏' : '切换地图到手机'\)/);
  assert.match(dockMenuSource, /'maps', 'toggleDisplay', newArea, \(\): void => this\.onToggleMapDisplay\(\)/);
  assert.match(dockMenuSource, /this\.onToggleAppDisplay\(\)/);
  const dockTarget = new Target();
  dockTarget.dashboardView = 'music';
  assert.equal(JSON.stringify(dockTarget.dockItems().map(item => [item.id, item.selected])), JSON.stringify([
    ['home', false], ['apps', false], ['map', false], ['music', true], ['split', false], ['settings', false]
  ]));
  const target = new Target();
  target.apps = [
    { appId: 'amap', uri: 'amap', category: 'map', launchState: 'VERIFIED',
      launchTarget: { kind: 'ability', bundleName: 'com.amap.hmapp', abilityName: 'EntryAbility' } },
    { appId: 'baidu-map', uri: 'baidu', category: 'map', launchState: 'VERIFIED',
      launchTarget: { kind: 'appLink', uri: 'baidumap://map' } },
    { appId: 'huawei-music', uri: 'music', category: 'music', launchState: 'VERIFIED',
      launchTarget: { kind: 'appLink', uri: 'hwmusic://com.huawei.hmsapp.music' } },
    { appId: 'other-music', uri: 'otherMusic', category: 'music', launchState: 'VERIFIED',
      launchTarget: { kind: 'appLink', uri: 'other-music://' } }
  ];
  target.mediaState = {};
  target.selectedMapUri = 'amap';
  target.selectedMusicUri = 'music';
  target.activeAppLabel = '';
  target.dashboardView = 'home';
  target.navigationPreview = true;
  target.activeAppUri = 'amap';
  assert.equal(target.isDockItemSelected('home'), true);
  assert.equal(target.isDockItemSelected('map'), false);
  target.navigationPreview = false;
  target.activeAppLabel = 'Map';
  assert.equal(target.isDockItemSelected('home'), false);
  assert.equal(target.isDockItemSelected('map'), true);
  target.activeAppUri = 'otherMusic';
  target.activeAppLabel = 'Music';
  target.selectedMusicUri = 'music';
  assert.equal(target.isDockItemSelected('music'), true,
    'highlight follows the running music app rather than the previous selection');
  target.dashboardView = 'maps';
  assert.equal(target.isDockItemSelected('map'), true);
  assert.equal(target.isDockItemSelected('music'), false);
  target.dashboardView = 'split';
  assert.equal(target.isDockItemSelected('split'), true);
  assert.equal(target.isDockItemSelected('map'), false);
  target.dashboardView = 'home';
  target.activeAppUri = '';
  const openedApps = [];
  target.onAppClick = app => openedApps.push(app.uri);
  target.activateDock('apps');
  assert.equal(target.dashboardView, 'apps');
  target.dashboardView = 'home';
  target.activeAppLabel = 'Map';
  target.navigationPreview = false;
  target.activateDock('home');
  assert.equal(target.navigationPreview, true);
  assert.deepEqual(openedApps, ['amap']);
  openedApps.length = 0;
  target.activateDock('map');
  assert.deepEqual(openedApps, ['amap']);
  target.selectedMapUri = 'baidu';
  target.activateDock('map');
  assert.deepEqual(openedApps, ['amap', 'baidu']);
  target.activateDock('map', true);
  assert.equal(target.dashboardView, 'maps');
  target.dashboardView = 'home';
  target.activateDock('music');
  assert.equal(openedApps[2], 'music');
  target.selectedMusicUri = 'otherMusic';
  target.activateDock('music');
  assert.equal(openedApps[3], 'otherMusic');
  target.activateDock('music', true);
  assert.equal(target.dashboardView, 'music');
  target.activeAppUri = 'otherMusic';
  target.activateDock('split');
  assert.equal(target.dashboardView, 'split');
  target.activateDock('settings');
  assert.equal(target.dashboardView, 'settings');
});

test('Dock selection follows the active app and current dashboard view', () => {
  const Target = loadMethods('pages/ProjectionDashboard.ets', 'ProjectionDashboard', [
    'isDashboardHome', 'activeAppHasCategory', 'isDockItemSelected'
  ]);
  const target = new Target();
  target.apps = [
    { uri: 'map-a', category: 'map' },
    { uri: 'music-a', category: 'music' },
    { uri: 'music-b', category: 'music' }
  ];
  target.dashboardView = 'home';
  target.activeAppLabel = '音乐';
  target.activeAppUri = 'music-b';
  target.navigationPreview = false;
  assert.equal(target.isDockItemSelected('music'), true);
  assert.equal(target.isDockItemSelected('map'), false);

  target.activeAppUri = 'map-a';
  assert.equal(target.isDockItemSelected('map'), true);
  target.navigationPreview = true;
  assert.equal(target.isDockItemSelected('home'), true);
  assert.equal(target.isDockItemSelected('map'), false);

  target.dashboardView = 'music';
  assert.equal(target.isDockItemSelected('music'), true);
  target.dashboardView = 'split';
  assert.equal(target.isDockItemSelected('split'), true);
  assert.equal(target.isDockItemSelected('music'), false);
});

test('active projection apps are observable and both Dock layouts invalidate selected item nodes', () => {
  const homeSource = fs.readFileSync(path.join(sourceRoot, 'pages/ProjectionHome.ets'), 'utf8');
  assert.match(homeSource, /@State private activeApp: ProjectionApp \| undefined = undefined/);
  assert.match(homeSource, /@State private mapApp: ProjectionApp \| undefined = undefined/);
  assert.match(homeSource, /activeAppUri: this\.activeApp\?\.uri \?\? ''/);
  assert.match(homeSource, /mapAppUri: this\.mapApp\?\.uri \?\? ''/);
  const dockSource = fs.readFileSync(path.join(sourceRoot, 'pages/ProjectionDock.ets'), 'utf8');
  const parsed = ts.createSourceFile('Dock.ts', dockSource, ts.ScriptTarget.Latest, true);
  const keys = [];
  function visit(node) {
    if (ts.isCallExpression(node) && node.expression.getText(parsed) === 'ForEach') {
      keys.push(node.arguments[2].getText(parsed));
    }
    ts.forEachChild(node, visit);
  }
  visit(parsed);
  assert.equal(keys.length, 2);
  for (const keySource of keys) {
    const javascript = ts.transpileModule(`const key = ${keySource}; key;`, {
      compilerOptions: { target: ts.ScriptTarget.ES2020 }
    }).outputText;
    const key = vm.runInNewContext(javascript);
    for (const id of ['home', 'map', 'music', 'apps', 'split', 'settings']) {
      assert.notEqual(key({ id, selected: true }), key({ id, selected: false }));
      assert.equal(key({ id, selected: true }), key({ id, selected: true }));
    }
  }
  const Target = loadMethods('pages/ProjectionDashboardContent.ets', 'ProjectionDashboardContent', ['isActiveMap']);
  const target = new Target();
  target.apps = [{ uri: 'amap', category: 'map' }, { uri: 'music', category: 'music' }];
  for (const [uri, expected] of [['', false], ['amap', true], ['music', false], ['amap', true]]) {
    target.activeAppUri = uri;
    assert.equal(target.isActiveMap(), expected);
  }
});

test('Apps grid includes only launchable third-party apps and adapts from three to six columns', () => {
  const vehicleApps = [{ appId: 'shell-settings', uri: 'settings', category: 'vehicle' }];
  const Target = loadMethods('pages/ProjectionDashboard.ets', 'ProjectionDashboard', [
    'visibleApps', 'updateAppsGridColumns', 'appsGridTemplate'
  ], {
    PROJECTION_VEHICLE_APPS: vehicleApps,
    isProjectionAppLaunchable: app => app.launchState === 'VERIFIED' && !!app.launchTarget
  });
  const target = new Target();
  target.apps = [
    { appId: 'verified', uri: 'verified', launchState: 'VERIFIED', launchTarget: { uri: 'open' } },
    { appId: 'unverified', uri: 'unverified', launchState: 'UNVERIFIED', launchTarget: { uri: 'unknown' } }
  ];
  assert.equal(target.visibleApps().map(app => app.appId).join(','), 'shell-settings,verified');
  for (const [width, columns] of [[320, 3], [400, 4], [520, 5], [700, 6]]) {
    target.updateAppsGridColumns(width);
    assert.equal(target.appsGridColumns, columns);
    assert.equal(target.appsGridTemplate().split(' ').length, columns);
  }
});
