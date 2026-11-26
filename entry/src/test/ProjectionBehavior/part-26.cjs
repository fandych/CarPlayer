const { assert, fs, path, vm, test, ts, sourceRoot, audioSenderFixture, loadEts, loadMethods,
  loadProjectionSettingsController, videoSenderFixture } = require('../ProjectionBehaviorSupport.cjs');

test('resizing an app surface recreates its virtual screen with matching dimensions', async () => {
  const Target = loadMethods('pages/ProjectionHomeAppDisplay.ets', 'ProjectionHomeAppDisplay',
    ['updateSurface', 'publishTouchBounds'], {
    AppStorage: { get: key => key === 'carplayProjectionDensity' ? 2 : undefined },
    projectionContentDisplayConfig: (width, height, density) => ({
      width: width * 2, height: height * 2, density: density * 2, scale: 2
    }),
    display: {
      async createVirtualScreen(options) {
        events.push(['create', options.width, options.height, options.density]);
        return 31;
      },
      async setVirtualScreenSurface(id, surfaceId) { events.push(['surface', id, surfaceId]); },
      async makeUnique(id) { events.push(['unique', id]); }
    }
  });
  const events = [];
  const target = new Target();
  target.displayId = 23;
  target.contentWidth = 1200;
  target.contentHeight = 700;
  target.displayGeneration = 0;
  target.surfaceGeneration = 0;
  target.activeSurface = { surfaceId: 'old', width: 1200, height: 700 };
  target.surfaceAttached = true;
  target.moveExistingInstance = false;
  target.callbacks = {
    getActiveApp: () => ({ appId: 'music' }),
    getAppOnPhone: () => false,
    setAppOnPhone() {},
    setLaunchMessage() {},
    getLaunchMessage: () => '',
    isSwitching: () => false,
    setSwitching() {},
    logProjection() {}
  };
  target.releaseDisplay = async () => {
    events.push(['release', target.displayId]);
    target.displayId = -1;
    target.contentWidth = 0;
    target.contentHeight = 0;
    target.activeSurface = undefined;
    target.surfaceAttached = false;
  };
  target.launchApp = async (_app, id) => events.push(['launch', id]);
  target.publishTouchBounds = surface => events.push(['publish', surface.width, surface.height]);
  await target.updateSurface({
    surfaceId: 'resized', left: 80, top: 10, width: 800, height: 640
  });
  assert.deepEqual(events, [
    ['release', 23],
    ['create', 1600, 1280, 4],
    ['surface', 31, 'resized'],
    ['unique', 31],
    ['launch', 31],
    ['publish', 800, 640]
  ]);
  assert.equal(target.contentWidth, 1600);
  assert.equal(target.contentHeight, 1280);
});

test('map card opens its link on the phone before releasing the content display', async () => {
  const order = [];
  const Target = loadMethods('pages/ProjectionHomeMapDisplay.ets', 'ProjectionHomeMapDisplay',
    ['releaseDisplay'], {
    AppStorage: { setOrCreate() {} },
    display: {
      getDefaultDisplaySync: () => ({ id: 0 }),
      async destroyVirtualScreen(id) { order.push(['destroy', id]); }
    }
  });
  const target = new Target();
  target.displayId = 23;
  target.app = { uri: 'carplay-client://v1/apps/amap/launch' };
  target.onPhone = false;
  target.callbacks = { setMapState() {}, logProjection() {} };
  target.appDisplay = {
    async launchApp(app, id) { order.push(['link', app.uri, id]); }
  };
  await target.releaseDisplay();
  assert.deepEqual(order, [['link', 'carplay-client://v1/apps/amap/launch', 0], ['destroy', 23]]);
  await target.releaseDisplay();
  assert.equal(order.length, 2);
});

test('resizing the map split surface rebuilds its virtual display without a phone handoff', async () => {
  const mapApp = {
    appId: 'amap', uri: 'map', category: 'map', launchState: 'VERIFIED',
    launchTarget: { kind: 'appLink', uri: 'map-link' }
  };
  const events = [];
  const Target = loadMethods('pages/ProjectionHomeMapDisplay.ets', 'ProjectionHomeMapDisplay',
    ['updateSurface', 'releaseDisplay', 'publishTouchBounds'], {
    AppStorage: { get: key => key === 'carplaySelectedMapAppId' ? 'amap' : 2, setOrCreate() {} },
    discoverProjectionApps: async () => [mapApp],
    isProjectionAppLaunchable: () => true,
    PROJECTION_APP_CANDIDATES: [],
    projectionContentDisplayConfig: (width, height, density) => ({
      width: width * 2, height: height * 2, density: density * 2, scale: 2
    }),
    display: {
      async destroyVirtualScreen(id) { events.push(['destroy', id]); },
      async createVirtualScreen(options) { events.push(['create', options.width, options.height]); return 24; },
      async setVirtualScreenSurface(id, surfaceId) { events.push(['surface', id, surfaceId]); },
      async makeUnique(id) { events.push(['unique', id]); }
    }
  });
  const target = new Target();
  target.displayId = 23;
  target.app = mapApp;
  target.onPhone = false;
  target.displayGeneration = 0;
  target.activeSurface = { surfaceId: 'map-surface', left: 0, top: 0, width: 600, height: 400 };
  target.callbacks = {
    getActiveApp: () => undefined,
    getAppOnPhone: () => false,
    appDisplayId: () => -1,
    setMapState: (app, onPhone) => { target.app = app; target.onPhone = onPhone; },
    setMapMessage() {},
    setLaunchMessage() {},
    isSwitching: () => false,
    setSwitching() {},
    logProjection() {}
  };
  target.appDisplay = {
    async launchApp(app, displayId) { events.push(['launch', app.appId, displayId]); }
  };
  target.publishTouchBounds = () => {};
  await target.updateSurface({ surfaceId: 'map-surface', left: 0, top: 0, width: 800, height: 400 });
  assert.deepEqual(events, [
    ['destroy', 23], ['create', 1600, 800], ['surface', 24, 'map-surface'], ['unique', 24],
    ['launch', 'amap', 24]
  ]);
});

test('selecting map from split promotes it to the content display without a phone handoff', async () => {
  const Target = loadMethods('pages/ProjectionHome.ets', 'ProjectionHome', ['selectApp'], {
    AppStorage: { get: () => 'home' },
    isProjectionAppLaunchable: app => app.launchState === 'VERIFIED' && !!app.launchTarget
  });
  const target = new Target();
  const events = [];
  target.logProjection = () => {};
  target.appSwitching = false;
  target.appDisplay = {
    displayId: 42,
    moveExistingInstance: false,
    async launchApp(app, displayId) { events.push(['launch', app.uri, displayId]); },
    publishTouchBounds() {}
  };
  target.appOnPhone = false;
  target.mapDisplay = {
    displayId: 23,
    invalidate() {},
    async releaseDisplay(restoreToPhone) { events.push(['releaseMap', restoreToPhone]); }
  };
  target.activeApp = { uri: 'music', category: 'music' };
  await target.selectApp({
    uri: 'map', label: '地图', category: 'map', launchState: 'VERIFIED',
    launchTarget: { kind: 'appLink', uri: 'map-link' }
  });
  assert.deepEqual(events, [['releaseMap', false], ['launch', 'map', 42]]);
  assert.equal(target.activeApp.uri, 'map');
  assert.equal(target.appOnPhone, false);
});

test('abnormal video shutdown closes TCP before draining and does not send TEARDOWN', async () => {
  const source = fs.readFileSync(path.join(sourceRoot, 'airplay/media/AirPlayMediaSessionLifecycle.ets'), 'utf8');
  const parsed = ts.createSourceFile('AirPlayMediaSessionLifecycle.ts', source, ts.ScriptTarget.Latest, true);
  const declaration = parsed.statements.find(statement =>
    ts.isClassDeclaration(statement) && statement.name?.text === 'AirPlayMediaSessionLifecycle');
  const method = declaration.members.find(member => member.name?.text === 'stop');
  const javascript = ts.transpileModule(`class Target { ${method.getText(parsed)} }`, {
    compilerOptions: { target: ts.ScriptTarget.ES2020 }
  }).outputText;
  const { settleSocketWithin } = loadEts('network/SocketDeadline.ets');
  const Target = vm.runInNewContext(`${javascript}\nTarget`, {
    settleSocketWithin, clearInterval, clearTimeout
  });
  const target = new Target();
  const order = [];
  let release;
  const blocked = new Promise(resolve => { release = resolve; });
  target.log = () => {};
  target.recorded = true;
  target.client = { isConnected: true };
  target.request = () => { throw new Error('must not TEARDOWN a broken connection'); };
  target.videoDataSocket = { async close() { order.push('close'); release(); } };
  target.videoStreamSender = {
    async flush() { order.push('drain'); await blocked; },
    async finish() {}
  };
  target.videoWriteQueue = blocked;
  await target.stop(true);
  assert.deepEqual(order, ['close', 'drain']);
  assert.equal(target.videoDataSocket, undefined);
  assert.equal(target.videoStreamSender, undefined);
  assert.equal(target.recorded, false);
});

test('embedded app and map hit rectangles use the actual window density, not the requested virtual density', () => {
  const Target = loadMethods('pages/ProjectionDashboard.ets', 'ProjectionDashboard', [
    'handleAppSurfaceChange', 'handleMapSurfaceChange'
  ]);
  const target = new Target();
  target.getUIContext = () => ({ vp2px: value => value * 3, px2vp: value => value / 3 });
  const area = {
    globalPosition: { x: 70, y: 8 }, width: 300, height: 200
  };
  let app;
  let map;
  target.onAppSurfaceChange = surface => { app = JSON.parse(JSON.stringify(surface)); };
  target.onMapSurfaceChange = surface => { map = JSON.parse(JSON.stringify(surface)); };
  target.handleAppSurfaceChange('app', area, true);
  target.handleMapSurfaceChange('map', area, true);
  assert.deepEqual(app, { surfaceId: 'app', left: 210, top: 24, width: 900, height: 600 });
  assert.deepEqual(map, { ...app, surfaceId: 'map' });
  assert.ok(120 < app.left, 'a Dock touch must stay outside the embedded app');
});

test('CarPlay tap hit testing tolerates small finger drift by targeting the contact midpoint', () => {
  const Target = loadMethods('pages/ProjectionDashboard.ets', 'ProjectionDashboard', [
    'touchHandler', 'canvasPixelToContentPoint', 'screenToContentPoint'
  ], {
    AppStorage: { get: key => ({ carplayProjectionHomeActive: true, carplayProjectionDisplayId: 7 })[key] }
  });
  const target = new Target();
  target.viewAreaOriginX = 0;
  target.viewAreaOriginY = 0;
  target.contentScalePercent = 100;
  target.contentOffsetXPercent = 0;
  target.contentOffsetYPercent = 0;
  target.projectionViewportWidth = 400;
  target.projectionViewportHeight = 200;
  target.getUIContext = () => ({ px2vp: value => value });
  const bounds = { left: 10, top: 10, right: 60, bottom: 60 };
  let activated = 0;
  target.touchBounds = new Map([['dock', bounds]]);
  target.touchAreas = new Map([['dock:map', {
    group: 'dock', ...bounds, action: () => { activated++; }
  }]]);
  target.touchHandler({ data: {
    displayId: 7, startX: 54, endX: 62, startY: 30, endY: 30, maxDistance: 8, durationMs: 120
  } });
  assert.equal(activated, 1);
  const settingsBounds = { left: 100, top: 10, right: 160, bottom: 60 };
  let settingsActivated = 0;
  target.dashboardView = 'settings';
  target.touchBounds.set('settings', settingsBounds);
  target.touchAreas.set('settings:dayNight', {
    group: 'settings', ...settingsBounds, action: () => { settingsActivated++; }
  });
  target.touchHandler({ data: {
    displayId: 7, startX: 120, endX: 120, startY: 30, endY: 30, maxDistance: 0, durationMs: 800
  } });
  assert.equal(settingsActivated, 1, 'a slow non-Dock touch must still activate on release');
});
