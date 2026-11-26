const { assert, fs, path, vm, test, ts, sourceRoot, audioSenderFixture, loadEts, loadMethods,
  loadProjectionSettingsController, videoSenderFixture } = require('../ProjectionBehaviorSupport.cjs');

test('Dock taps use measured bounds and window density while hidden map areas cannot steal grid taps', () => {
  const routerSource = fs.readFileSync(path.join(sourceRoot, 'pages/ProjectionTouchRouter.ets'), 'utf8');
  assert.match(routerSource, /area\.group === 'dock'/);
  assert.match(routerSource, /area\.group === 'grid' && dashboardView !== 'apps'/);
  const Target = loadMethods('pages/ProjectionDashboard.ets', 'ProjectionDashboard', [
    'touchHandler', 'screenToContentPoint', 'canvasPixelToContentPoint'
  ], {
    AppStorage: { get: key => ({
      carplayProjectionHomeActive: true, carplayProjectionDisplayId: 7, carplayProjectionDensity: 1.333
    })[key] }
  });
  const target = new Target();
  target.contentScalePercent = 100;
  target.contentOffsetXPercent = 0;
  target.contentOffsetYPercent = 0;
  target.projectionViewportWidth = 1000;
  target.projectionViewportHeight = 600;
  target.viewAreaOriginX = 0;
  target.viewAreaOriginY = 0;
  let density = 3;
  target.getUIContext = () => ({ px2vp: value => value / density });
  target.touchBounds = new Map([
    ['dock', { left: 0, top: 0, right: 60, bottom: 200 }],
    ['map', { left: 80, top: 0, right: 300, bottom: 180 }],
    ['grid', { left: 80, top: 0, right: 300, bottom: 180 }]
  ]);
  let mapOpened = false;
  let gridOpened = false;
  let longPresses = 0;
  const selected = [];
  target.touchAreas = new Map([
    ['dock-first', { group: 'dock', left: 4, top: 8, right: 56, bottom: 31,
      action: () => selected.push('first') }],
    ['dock-second', { group: 'dock', left: 4, top: 38, right: 56, bottom: 54,
      action: () => selected.push('second'), longPress: () => { longPresses++; } }],
    ['map', { group: 'map', left: 80, top: 0, right: 300, bottom: 180, action: () => { mapOpened = true; } }],
    ['grid', { group: 'grid', left: 80, top: 0, right: 300, bottom: 180, action: () => { gridOpened = true; } }]
  ]);
  const tap = (x, y) => target.touchHandler({ data: {
    displayId: 7, startX: x, endX: x, startY: y, endY: y
  } });
  for (const scale of [1, 1.333, 2, 3]) {
    density = scale;
    tap(10 * scale, 50 * scale);
    assert.equal(selected.at(-1), 'second');
    const count = selected.length;
    tap(10 * scale, 35 * scale);
    tap(59 * scale, 50 * scale);
    assert.equal(selected.length, count, 'spacing and side padding must not open an app');
  }
  assert.equal(selected.length, 4);
  density = 3;
  target.touchHandler({ data: {
    displayId: 7, startX: 30, endX: 30, startY: 150, endY: 150, durationMs: 800
  } });
  assert.equal(longPresses, 1);
  assert.equal(selected.length, 4, 'long press must not also launch an app');
  target.dashboardView = 'apps';
  target.activeAppLabel = '';
  tap(300, 60);
  assert.equal(mapOpened, false);
  assert.equal(gridOpened, true);
  target.touchBounds.set('media', { left: 320, top: 0, right: 400, bottom: 180 });
  let mediaCommands = 0;
  target.touchAreas.set('media', {
    group: 'media', left: 320, top: 0, right: 400, bottom: 180,
    action: () => { mediaCommands++; }
  });
  target.dashboardView = 'home';
  target.activeAppLabel = 'Amap';
  target.navigationPreview = true;
  tap(1050, 60);
  assert.equal(mediaCommands, 1, 'home music controls must work alongside an active map preview');
  target.navigationPreview = false;
  tap(1050, 60);
  assert.equal(mediaCommands, 1, 'hidden home music controls must not intercept full map touches');
  const menuBounds = { left: 80, top: 0, right: 300, bottom: 180 };
  target.touchBounds.set('maps', menuBounds);
  target.touchBounds.set('music', menuBounds);
  const menus = [];
  target.touchAreas.set('maps', { ...menuBounds, group: 'maps', action: () => menus.push('map') });
  target.touchAreas.set('music', { ...menuBounds, group: 'music', action: () => menus.push('music') });
  target.dashboardView = 'music';
  tap(300, 60);
  assert.deepEqual(menus, ['music'], 'a hidden map menu must not intercept music selections');
  target.dashboardView = 'maps';
  tap(300, 60);
  assert.deepEqual(menus, ['music', 'map']);
  density = 2;
  target.viewAreaOriginX = 200;
  target.viewAreaOriginY = 100;
  target.contentScalePercent = 200;
  const mapped = target.canvasPixelToContentPoint(400, 300);
  assert.deepEqual([mapped.x, mapped.y], [400, 250]);
});

test('disabled media commands cannot be invoked through fallback touch', async () => {
  const { ProjectionMediaCoordinator } = loadEts('pages/ProjectionMediaCoordinator.ets', {
    '@ohos.abilityAccessCtrl': {},
    '@ohos.app.ability.common': {},
    '../session/MediaSessionBridge': {
      EMPTY_PROJECTION_MEDIA: { title: '', artist: '', lyric: '', positionMs: 0, durationMs: 0,
        isPlaying: false, commands: [], queue: [], message: '' }
    },
    './ProjectionAppCatalog': { includeMediaSessionApp: apps => apps }
  });
  const commands = [];
  let state = { commands: ['play'], isPlaying: false };
  const target = new ProjectionMediaCoordinator({
    getSnapshot: () => state,
    onSnapshot: snapshot => { state = snapshot; },
    getApps: () => [],
    onAppsChanged: () => {},
    onActionMessage: () => {},
    onLog: () => {},
    getContext: () => ({})
  });
  target.bridge = {
    async send(command) { commands.push(command); },
    async refresh() { return state; }
  };
  await target.send('playNext');
  await target.send('play');
  assert.deepEqual(commands, ['play']);
});

test('split dashboard has independent navigation and app surfaces', () => {
  const source = fs.readFileSync(path.join(sourceRoot, 'pages/ProjectionDashboard.ets'), 'utf8');
  const contentSource = fs.readFileSync(path.join(sourceRoot, 'pages/ProjectionDashboardContent.ets'), 'utf8');
  const shellSource = fs.readFileSync(path.join(sourceRoot, 'pages/ProjectionDashboardShell.ets'), 'utf8');
  const shellLayoutSource = fs.readFileSync(
    path.join(sourceRoot, 'pages/ProjectionDashboardShellLayout.ets'), 'utf8'
  );
  const appControllerSource = fs.readFileSync(
    path.join(sourceRoot, 'pages/ProjectionDashboardAppController.ets'), 'utf8'
  );
  assert.match(contentSource, /surfaceName: 'projectionSplitMapSurface'/);
  assert.match(contentSource, /surfaceName: 'projectionSplitMusicSurface'/);
  assert.doesNotMatch(contentSource, /Text\('导航 APP'\)|Text\('音乐 APP'\)/);
  assert.match(contentSource, /this\.dashboardView === 'split'/);
  assert.match(contentSource, /this\.hasActiveMusicApp\(\)/);
  assert.match(shellLayoutSource, /this\.DockPanel\(false\)/);
  assert.match(shellLayoutSource, /this\.DockPanel\(true\)/);
  assert.match(appControllerSource, /showDashboardView/);
});

test('split mode keeps the navigation display while selecting a verified music app', async () => {
  let releasedMap = 0;
  const Target = loadMethods('pages/ProjectionHome.ets', 'ProjectionHome', ['selectApp'], {
    AppStorage: { get: () => 'split' },
    isProjectionAppLaunchable: app => app.launchState === 'VERIFIED' && !!app.launchTarget
  });
  const target = new Target();
  target.appSwitching = false;
  target.mapDisplay = {
    displayId: 42,
    invalidate() {},
    async releaseDisplay() { releasedMap++; }
  };
  target.appDisplay = { displayId: -1, moveExistingInstance: false };
  target.logProjection = () => {};
  await target.selectApp({
    appId: 'verified-music',
    uri: 'carplay-client://v1/apps/verified-music/launch',
    label: 'Verified Music',
    category: 'music',
    launchState: 'VERIFIED',
    launchTarget: { kind: 'appLink', uri: 'verified-music-link' }
  });
  assert.equal(releasedMap, 0);
  assert.equal(target.activeApp.appId, 'verified-music');
});

test('app display manager toggles between phone and virtual display without losing state on failure', async () => {
  const launches = [];
  const { ProjectionHomeAppDisplay } = loadEts('pages/ProjectionHomeAppDisplay.ets', {
    '@ohos.app.ability.common': {},
    '@ohos.display': { getDefaultDisplaySync: () => ({ id: 0 }) },
    '../video/CarPlayVirtualDisplay': {
      projectionContentDisplayConfig: () => ({}),
      projectionDisplayToggleTarget: (onPhone, phoneId, displayId) => onPhone ? displayId : phoneId
    },
    './ProjectionDashboard': {},
    './ProjectionAppCatalog': {},
    './ProjectionAppLauncher': {
      async launchProjectionApp(_context, app, displayId) { launches.push([app.uri, displayId]); }
    }
  });
  let onPhone = true;
  let switching = false;
  let message = '';
  const app = { appId: 'music', uri: 'music-link', label: 'Music' };
  const manager = new ProjectionHomeAppDisplay({
    getHostContext: () => ({}),
    getActiveApp: () => app,
    getAppOnPhone: () => onPhone,
    setAppOnPhone: value => { onPhone = value; },
    setLaunchMessage: value => { message = value; },
    getLaunchMessage: () => message,
    isSwitching: () => switching,
    setSwitching: value => { switching = value; },
    logProjection: () => {}
  });
  manager.displayId = 12;
  const previousAppStorage = global.AppStorage;
  global.AppStorage = { setOrCreate() {} };
  try {
    await manager.toggleDisplay();
    assert.deepEqual(launches, [['music-link', 12]]);
    assert.equal(onPhone, false);
    await manager.toggleDisplay();
    assert.deepEqual(launches[1], ['music-link', 0]);
    assert.equal(onPhone, true);
  } finally {
    if (previousAppStorage === undefined) {
      delete global.AppStorage;
    } else {
      global.AppStorage = previousAppStorage;
    }
  }
});

test('Wi-Fi link addresses are formatted with the first octet in the most significant byte', () => {
  const { formatWifiIpv4Address } = loadEts('network/WifiIpv4Address.ets', {}, 'formatWifiIpv4Address');
  assert.equal(formatWifiIpv4Address(0xc0a889ab), '192.168.137.171');
  assert.equal(formatWifiIpv4Address(0x0a24e843), '10.36.232.67');
});

test('touch HID UUID and logical extents come from /info and reports scale to the encoded video', () => {
  const touch = loadEts('airplay/CarPlayTouchReport.ets');
  const descriptor = new Uint8Array([
    0x05, 0x0d, 0x09, 0x04, 0xa1, 0x01, 0x05, 0x0d, 0x09, 0x22, 0xa1, 0x02,
    0x09, 0x38, 0x75, 0x08, 0x95, 0x01, 0x81, 0x02,
    0x05, 0x01, 0x26, 0xff, 0x09, 0x09, 0x30, 0x75, 0x10, 0x81, 0x02,
    0x26, 0xcf, 0x02, 0x09, 0x31, 0x81, 0x02, 0xc0, 0xc0
  ]);
  assert.deepEqual({ ...touch.parseHidPointerExtents(descriptor) },
    { touchScreen: true, logicalMaxX: 2559, logicalMaxY: 719 });
  const node = (kind, values) => ({ kind, ...values, get(key) { return this.dictionaryValue.get(key); } });
  const device = node('dictionary', { dictionaryValue: new Map([
    ['uuid', { kind: 'string', stringValue: 'e5f7a68d' }],
    ['displayUUID', { kind: 'string', stringValue: 'display-1' }],
    ['hidDescriptor', { kind: 'data', dataValue: descriptor }]
  ]) });
  const info = node('dictionary', { dictionaryValue: new Map([['hidDevices', { kind: 'array', arrayValue: [device] }]]) });
  const found = touch.findTouchHidDevice(info, 'display-1');
  assert.equal(found.uuid, 'e5f7a68d');
  assert.equal(touch.findTouchHidDevice(info, 'display-2'), undefined);
  const report = new Uint8Array([0, 1, 0xff, 0x09, 0xcf, 0x02, 1, 0, 0, 0, 0, 0]);
  const scaled = touch.scaleCarPlayTouchReport(report, found, 1920, 540);
  assert.deepEqual([...scaled.subarray(2, 6)], [0x7f, 0x07, 0x1b, 0x02]);
  assert.deepEqual([...scaled.subarray(6)], [1, 0, 0, 0, 0, 0]);

  const integerUuid = node('dictionary', { dictionaryValue: new Map([
    ['uuid', { kind: 'integer', integerValue: BigInt('0x2a2a2a2a') }],
    ['displayUUID', { kind: 'string', stringValue: 'display-1' }],
    ['hidDescriptor', { kind: 'data', dataValue: descriptor }]
  ]) });
  const integerInfo = node('dictionary', { dictionaryValue: new Map([[
    'hidDevices', { kind: 'array', arrayValue: [integerUuid] }
  ]]) });
  const integerDevice = touch.findTouchHidDevice(integerInfo, 'display-1');
  assert.deepEqual(integerDevice, { uuid: '2a2a2a2a', logicalMaxX: 2559, logicalMaxY: 719 });
  const integerCommand = node('dictionary', { dictionaryValue: new Map([
    ['type', { kind: 'string', stringValue: 'hidSendReport' }],
    ['params', node('dictionary', { dictionaryValue: new Map([
      ['uuid', { kind: 'integer', integerValue: BigInt('0x2a2a2a2a') }],
      ['hidReport', { kind: 'data', dataValue: report }]
    ]) })]
  ]) });
  assert.deepEqual([...touch.extractCarPlayTouchReport(integerCommand, integerDevice.uuid)], [...report]);
});
