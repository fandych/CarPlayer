const { assert, fs, path, vm, test, ts, sourceRoot, audioSenderFixture, loadEts, loadMethods,
  loadProjectionSettingsController, videoSenderFixture } = require('../ProjectionBehaviorSupport.cjs');

test('split dashboard exposes ratio controls and requires an opened music app', () => {
  const source = fs.readFileSync(path.join(sourceRoot, 'pages/ProjectionDashboard.ets'), 'utf8');
  const contentSource = fs.readFileSync(path.join(sourceRoot, 'pages/ProjectionDashboardContent.ets'), 'utf8');
  const displaySource = fs.readFileSync(path.join(sourceRoot, 'pages/ProjectionDisplaySettingsPane.ets'), 'utf8');
  assert.match(source, /splitMapRatio/);
  assert.match(source, /splitMusicRatio/);
  assert.match(displaySource, /TextInput\(\{[\s\S]*splitMapRatioInput/);
  assert.match(contentSource, /\.layoutWeight\(this\.splitMapRatio\)/);
  assert.match(contentSource, /\.layoutWeight\(this\.splitMusicRatio\)/);
  assert.equal((contentSource.match(/\.layoutWeight\(this\.splitMapRatio\)/g) || []).length, 3);
  assert.equal((contentSource.match(/\.layoutWeight\(this\.splitMusicRatio\)/g) || []).length, 1);
  const mediaSidebar = fs.readFileSync(path.join(sourceRoot, 'pages/ProjectionMediaSidebar.ets'), 'utf8');
  assert.match(mediaSidebar, /\.layoutWeight\(this\.splitMusicRatio\)/);
  assert.doesNotMatch(source, /\.width\('22%'\)/);
  const splitStart = contentSource.indexOf('SplitPage()');
  const splitEnd = contentSource.indexOf('private DashboardSidebar()', splitStart);
  const splitSource = contentSource.slice(splitStart, splitEnd);
  assert.match(splitSource, /\.layoutWeight\(this\.splitMapRatio\)\s*\.height\('100%'\)/);
  assert.match(splitSource, /\.layoutWeight\(this\.splitMusicRatio\)\s*\.height\('100%'\)/);
  assert.match(splitSource, /surfaceName: 'projectionSplitMapSurface'[\s\S]*?\.width\('100%'\)\s*\.height\('100%'\)/);
  assert.doesNotMatch(splitSource, /surfaceName: 'projectionSplitMapSurface'[\s\S]*?\.aspectRatio\(/);
  const mainPanelStart = contentSource.indexOf('private MainPanel()');
  const mainPanelEnd = contentSource.indexOf('build()', mainPanelStart);
  const mainPanelSource = contentSource.slice(mainPanelStart, mainPanelEnd);
  assert.match(mainPanelSource, /surfaceName: 'projectionAppSurface'[\s\S]*?\.width\('100%'\)\s*\.height\('100%'\)/);
  assert.doesNotMatch(mainPanelSource, /surfaceName: 'projectionAppSurface'[\s\S]*?\.aspectRatio\(/);
  assert.doesNotMatch(source, /\b[345] : 1\b/);
  const appControllerSource = fs.readFileSync(
    path.join(sourceRoot, 'pages/ProjectionDashboardAppController.ets'), 'utf8'
  );
  assert.match(appControllerSource, /view === 'split' && !this\.activeMusicApp\(state\)/);
  const Target = loadMethods('pages/ProjectionDashboard.ets', 'ProjectionDashboard', ['showDashboardView'], {
    AppStorage: { get: () => -1, setOrCreate: () => {} }
  });
  const target = new Target();
  target.dashboardView = 'home';
  target.touchBounds = new Map();
  target.apps = [];
  target.appOnPhone = false;
  target.activeAppUri = '';
  target.showDashboardView('split');
  assert.equal(target.dashboardView, 'home');
  assert.match(target.dockActionMessage, /音乐 app/);
  target.apps = [{
    appId: 'huawei-music', uri: 'music-uri', category: 'music',
    launchState: 'VERIFIED', launchTarget: { uri: 'music-link' }
  }];
  target.activeAppUri = 'music-uri';
  target.showDashboardView('split');
  assert.equal(target.dashboardView, 'split');
});

test('socket shutdown deadlines settle stalled operations instead of hanging recovery', async () => {
  const { settleSocketWithin } = loadEts('network/SocketDeadline.ets');
  await assert.rejects(settleSocketWithin(new Promise(() => {}), 1, 'stalled socket'), /stalled socket/);
  assert.equal(await settleSocketWithin(Promise.resolve(42), 1000, 'unexpected'), 42);
});

test('audio closes its socket before waiting for a blocked packet write', async () => {
  const { sender, session } = audioSenderFixture();
  await sender.start(session);
  let release;
  const events = [];
  sender.sendQueue = new Promise(resolve => { release = resolve; });
  sender.socket.close = async () => { events.push('close'); release(); };
  await sender.stop();
  assert.deepEqual(events, ['close']);
  assert.equal(sender.socket, undefined);
});

test('shake toggles the existing app display and preserves state on failure', async () => {
  const Target = loadMethods('pages/ProjectionHome.ets', 'ProjectionHome', ['toggleAppDisplay']);
  const target = new Target();
  let toggles = 0;
  target.appDisplay = { async toggleDisplay() { toggles++; } };
  await target.toggleAppDisplay();
  assert.equal(toggles, 1);
});

test('projection launches only verified targets on the requested display', async () => {
  const catalog = loadEts('pages/ProjectionAppCatalog.ets');
  const { launchProjectionApp } = loadEts('pages/ProjectionAppLauncher.ets', {
    './ProjectionAppCatalog': {
      isProjectionAppLaunchable: catalog.isProjectionAppLaunchable,
      projectionAppLaunchTarget: catalog.projectionAppLaunchTarget
    }
  });
  const source = fs.readFileSync(path.join(sourceRoot, 'pages/ProjectionHomeAppDisplay.ets'), 'utf8');
  assert.match(source, /launchProjectionApp\([\s\S]*app,\s*displayId,\s*preserveExistingInstance/);
  const calls = [];
  const hostContext = {
    async startAbility(want, options) { calls.push(JSON.parse(JSON.stringify({ want, options }))); }
  };
  await launchProjectionApp(() => hostContext, {
    appId: 'verified-music',
    uri: 'carplay-client://v1/apps/verified-music/launch',
    label: 'Verified Music',
    launchState: 'VERIFIED',
    launchTarget: { kind: 'appLink', uri: 'verified-music-link://' }
  }, 12);
  assert.deepEqual(calls, [{ want: { action: 'ohos.want.action.viewData', uri: 'verified-music-link://' },
    options: { displayId: 12 } }]);
  await launchProjectionApp(() => hostContext, {
    appId: 'verified-map',
    uri: 'carplay-client://v1/apps/verified-map/launch',
    label: 'Verified Map',
    launchState: 'VERIFIED',
    launchTarget: { kind: 'ability', bundleName: 'org.example.verified', abilityName: 'EntryAbility' }
  }, 15);
  assert.deepEqual(calls[1], { want: {
    bundleName: 'org.example.verified', abilityName: 'EntryAbility'
  },
    options: { displayId: 15 } });
  assert.equal(Object.hasOwn(calls[1].want, 'uri'), false);
  assert.equal(Object.hasOwn(calls[1].want, 'flags'), false);
  const amap = {
    appId: 'amap',
    uri: 'carplay-client://v1/apps/amap/launch',
    bundleName: 'com.amap.hmapp',
    moduleName: 'entry',
    abilityName: 'EntryAbility',
    label: '高德地图',
    launchState: 'VERIFIED',
    launchTarget: {
      kind: 'ability',
      bundleName: 'com.amap.hmapp',
      moduleName: 'entry',
      abilityName: 'EntryAbility',
      isSingleton: true,
      probeUri: 'amapuri://'
    }
  };
  await launchProjectionApp(() => hostContext, amap, 18);
  assert.deepEqual(calls[2], {
    want: { action: 'ohos.want.action.viewData', uri: 'amapuri://' },
    options: { displayId: 18 }
  });
  await launchProjectionApp(() => hostContext, amap, 19, true);
  assert.deepEqual(calls[3], {
    want: { bundleName: 'com.amap.hmapp', moduleName: 'entry', abilityName: 'EntryAbility' },
    options: { displayId: 19 }
  });
  const nonSingletonAmap = {
    ...amap,
    launchTarget: { ...amap.launchTarget, isSingleton: false }
  };
  await assert.rejects(launchProjectionApp(() => hostContext, nonSingletonAmap, 20, true), /拒绝重新启动/);
  let contextRequests = 0;
  await assert.rejects(launchProjectionApp(() => {
    contextRequests++;
    return hostContext;
  }, {
    appId: 'amap',
    uri: 'carplay-client://v1/apps/amap/launch',
    label: 'Amap',
    launchState: 'UNVERIFIED'
  }, 17), /启动入口尚未验证/);
  assert.equal(contextRequests, 0);
});

test('app surface replacement retains the display and never relaunches the navigation app', async () => {
  const calls = [];
  let releaseSurface;
  const Target = loadMethods('pages/ProjectionHomeAppDisplay.ets', 'ProjectionHomeAppDisplay',
    ['updateSurface', 'publishTouchBounds'], {
    AppStorage: { setOrCreate() {} },
    display: { async setVirtualScreenSurface(id, surfaceId) {
      if (surfaceId === 'broken') throw new Error('surface unavailable');
      if (surfaceId === 'delayed') await new Promise(resolve => { releaseSurface = resolve; });
      calls.push([id, surfaceId]);
    } }
  });
  const target = new Target();
  target.displayId = 23;
  target.contentWidth = 1200;
  target.contentHeight = 700;
  target.displayGeneration = 0;
  target.surfaceGeneration = 0;
  target.activeSurface = { surfaceId: 'old', width: 1200, height: 700 };
  target.surfaceAttached = true;
  let launchMessage = '';
  target.callbacks = {
    getAppOnPhone: () => false,
    getLaunchMessage: () => launchMessage,
    setLaunchMessage: message => { launchMessage = message; },
    logProjection: () => {}
  };
  let published;
  target.publishTouchBounds = surface => { published = surface; };
  const surface = { surfaceId: 'new', left: 80, top: 10, width: 1200, height: 700 };
  await target.updateSurface(surface);
  assert.deepEqual(calls, [[23, 'new']]);
  assert.equal(target.displayId, 23);
  assert.equal(published, surface);
  const repositioned = { ...surface, left: 100 };
  await target.updateSurface(repositioned);
  assert.equal(target.displayId, 23);
  assert.equal(published, repositioned);
  assert.equal(calls.length, 1);
  await target.updateSurface({ ...repositioned, surfaceId: 'broken' });
  assert.equal(target.displayId, 23);
  assert.equal(published, repositioned);
  assert.equal(target.activeSurface, repositioned);
  assert.match(launchMessage, /surface unavailable/);
  await target.updateSurface(undefined);
  assert.equal(target.displayId, 23);
  assert.equal(published, undefined);
  await target.updateSurface(repositioned);
  assert.equal(target.displayId, 23);
  assert.equal(published, repositioned);
  assert.deepEqual(calls, [[23, 'new'], [23, 'new']]);
  assert.equal(launchMessage, '');
  const pending = target.updateSurface({ ...repositioned, surfaceId: 'delayed' });
  await target.updateSurface(undefined);
  releaseSurface();
  await pending;
  assert.equal(published, undefined, 'late binding must not restore a detached touch target');
  assert.equal(target.surfaceAttached, false);
});
