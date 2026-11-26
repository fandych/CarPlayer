const { assert, fs, path, vm, test, ts, sourceRoot, audioSenderFixture, loadEts, loadMethods,
  loadProjectionSettingsController, videoSenderFixture } = require('../ProjectionBehaviorSupport.cjs');

test('shake switching ignores vibration, requires three pulses, and cools down', () => {
  const { ProjectionShakeDetector } = loadEts('video/ProjectionShakeDetector.ets');
  const detector = new ProjectionShakeDetector();
  assert.equal(detector.update(0, 0, 9.8, 0), false);
  assert.equal(detector.update(1, 0, 9.8, 100), false);
  assert.equal(detector.update(22, 0, 9.8, 200), false);
  assert.equal(detector.update(-22, 0, 9.8, 350), false);
  assert.equal(detector.update(22, 0, 9.8, 500), true);
  assert.equal(detector.update(-22, 0, 9.8, 650), false);
  assert.equal(detector.update(Number.NaN, 0, 0, 1000), false);
  assert.equal(detector.update(22, 0, 9.8, 3100), false);
  assert.equal(detector.update(-22, 0, 9.8, 3250), false);
  assert.equal(detector.update(22, 0, 9.8, 3400), true);
});

test('touch reports are routed to the CarPlayer shell without third-party injection', () => {
  const reports = loadEts('airplay/CarPlayTouchReport.ets');
  const { CarPlayTouchInput } = loadEts('video/CarPlayTouchInput.ets', {
    '@ohos.events.emitter': { emit() {} }, '../airplay/CarPlayTouchReport': reports
  });
  const taps = [];
  const routed = [];
  const input = new CarPlayTouchInput(tap => taps.push(tap), report => routed.push(report));
  input.start(42, 320, 240);
  input.handleReport(new Uint8Array([1, 100, 0, 50, 0]));
  input.handleReport(new Uint8Array([1, 105, 0, 55, 0]));
  input.handleReport(new Uint8Array([0, 0, 0, 0, 0]));
  assert.equal(routed.length, 3);
  assert.equal(taps.length, 1);
  assert.equal(taps[0].displayId, 42);
  assert.equal(taps[0].endX, 105);
  input.handleReport(new Uint8Array([1, 120, 0, 70, 0]));
  input.stop();
  assert.deepEqual(routed.at(-1), { displayId: 42, contacts: [] });
});

test('fallback touch preserves long press duration and rejects moved contacts', () => {
  const { CarPlayTouchInput } = loadEts('video/CarPlayTouchInput.ets', {
    '@ohos.events.emitter': { emit() {} },
    '../airplay/CarPlayTouchReport': loadEts('airplay/CarPlayTouchReport.ets')
  });
  const taps = [];
  const input = new CarPlayTouchInput(tap => taps.push(tap), () => {});
  input.start(7, 800, 480);
  input.handleReport(new Uint8Array([1, 100, 0, 50, 0]));
  input.startedAt = Date.now() - 1500;
  input.handleReport(new Uint8Array([0, 0, 0, 0, 0]));
  assert.equal(taps.length, 1);
  assert.ok(taps[0].durationMs >= 1500);
  input.handleReport(new Uint8Array([1, 100, 0, 50, 0]));
  input.handleReport(new Uint8Array([1, 150, 0, 50, 0]));
  input.startedAt = Date.now() - 1500;
  input.handleReport(new Uint8Array([0, 0, 0, 0, 0]));
  assert.equal(taps.length, 1);
  input.stop();
});

test('phone touch handling contains no third-party input injection fallback', () => {
  const source = fs.readFileSync(path.join(sourceRoot, 'session/SessionController.ets'), 'utf8');
  const input = fs.readFileSync(path.join(sourceRoot, 'video/CarPlayTouchInput.ets'), 'utf8');
  const module = fs.readFileSync(path.join(sourceRoot, '../module.json5'), 'utf8');
  assert.doesNotMatch(source, /injectProjectionTouch|injectTouchEvent|requestTouchInjection/);
  assert.doesNotMatch(input, /CarPlayTouchInjector|injectContacts|injectBackKey/);
  assert.doesNotMatch(module, /ohos\.permission\.CONTROL_DEVICE/);
});

test('navigation preview and full view share the running app without returning it to the phone', () => {
  const contentSource = fs.readFileSync(path.join(sourceRoot, 'pages/ProjectionDashboardContent.ets'), 'utf8');
  const stored = new Map();
  const Target = loadMethods('pages/ProjectionDashboard.ets', 'ProjectionDashboard', [
    'selectApp', 'showHome', 'setNavigationPreview'
  ], {
    AppStorage: {
      setOrCreate: (name, value) => stored.set(name, value),
      get: key => stored.get(key)
    }
  });
  const target = new Target();
  target.activeAppUri = 'carplay-client://v1/apps/amap/launch';
  target.activeAppLabel = 'Amap';
  target.onHomeClick = () => { throw new Error('must not release navigation on preview'); };
  target.onAppClick = () => { throw new Error('must not relaunch navigation on expansion'); };
  target.selectApp({ appId: 'shell-home', uri: 'carplay-client://v1/shell/home', category: 'home' });
  assert.equal(target.navigationPreview, true);
  assert.equal(stored.get('carplayNavigationPreview'), true);
  target.setNavigationPreview(false);
  assert.equal(stored.get('carplayNavigationPreview'), false);
  assert.equal((contentSource.match(/surfaceName: 'projectionAppSurface'/g) || []).length, 1);
});

test('home selects a map preview and shows HTML-style music and weather cards', async () => {
  const contentSource = fs.readFileSync(path.join(sourceRoot, 'pages/ProjectionDashboardContent.ets'), 'utf8');
  const map = {
    appId: 'amap',
    uri: 'carplay-client://v1/apps/amap/launch',
    label: '高德地图',
    category: 'map',
    launchState: 'VERIFIED',
    launchTarget: { kind: 'appLink', uri: 'verified-amap-link' }
  };
  const stored = new Map();
  const Target = loadMethods('pages/ProjectionDashboard.ets', 'ProjectionDashboard', [
    'selectApp', 'showHome', 'setNavigationPreview', 'discoverApps'
  ], {
    AppStorage: {
      setOrCreate: (name, value) => stored.set(name, value),
      get: key => stored.get(key)
    },
    PROJECTION_MAP_URI: map.uri,
    discoverProjectionApps: () => [map],
    projectionAppCatalog: () => [map],
  });
  const target = new Target();
  target.apps = [map];
  target.activeAppUri = 'hwmusic://com.huawei.hmsapp.music';
  target.activeAppLabel = 'Music';
  const opened = [];
  target.onAppClick = app => opened.push(app.uri);
  target.onHomeClick = () => { throw new Error('Home must retain the content display'); };
  target.selectApp({ appId: 'shell-home', uri: 'carplay-client://v1/shell/home', category: 'home' });
  assert.equal(target.navigationPreview, true);
  assert.deepEqual(opened, [map.uri]);
  target.activeAppUri = map.uri;
  target.selectApp({ appId: 'shell-home', uri: 'carplay-client://v1/shell/home', category: 'home' });
  assert.deepEqual(opened, [map.uri], 'returning from full map must not reopen it');
  target.activeAppUri = '';
  target.activeAppLabel = '';
  await target.discoverApps();
  assert.equal(stored.get('carplayNavigationPreview'), true);
  assert.deepEqual(opened, [map.uri, map.uri]);
  assert.match(contentSource, /private DashboardSidebar\(\)/);
  const sidebarSource = fs.readFileSync(path.join(sourceRoot, 'pages/ProjectionMediaSidebar.ets'), 'utf8');
  const musicCardEnd = sidebarSource.indexOf("Stack({ alignContent: Alignment.TopStart })");
  const musicCardSource = sidebarSource.slice(0, musicCardEnd);
  assert.doesNotMatch(musicCardSource, /projection_album_art|Image\(/);
  assert.equal((sidebarSource.match(/\.border\(\{ width: 1, color: this\.cardStrokeColor \}\)/g) || []).length, 2);
  assert.match(musicCardSource, /Text\(this\.title\)/);
  assert.match(musicCardSource, /Text\(this\.lyric \|\| '暂无歌词'\)/);
  assert.match(musicCardSource, /this\.MediaControl\('playPrevious'/);
  assert.match(musicCardSource, /this\.MediaControl\('playNext'/);
  assert.match(musicCardSource, /this\.progressPercent\(\)/);
  assert.match(sidebarSource, /app\.media\.projection_weather_sun/);
  assert.match(sidebarSource, /Text\('上海'\)/);
  assert.doesNotMatch(contentSource, /在手机打开地图/);
  assert.ok(!contentSource.includes('this.navigationPreview ? 0.7'), 'preview uses actual layout, not a floating scaled page');
});

test('AVSession lyric metadata resolves the current LRC line at playback position', () => {
  const { resolveCurrentLyric } = loadEts('session/MediaSessionBridge.ets', {
    '@ohos.multimedia.avsession': {}
  });
  const lyric = '[offset:-500]\n[00:00.00]Intro\n[00:01.25][00:01.50]Chorus\n[00:02.00]Outro';
  assert.equal(resolveCurrentLyric(lyric, undefined, 100), 'Intro');
  assert.equal(resolveCurrentLyric(lyric, undefined, 900), 'Chorus');
  assert.equal(resolveCurrentLyric(lyric, 'live lyric', 0), 'live lyric');
  assert.equal(resolveCurrentLyric(undefined, undefined, 1000), '');
});

test('music discovers late sessions, publishes changes, controls and cleans up', async () => {
  let descriptors = [];
  let title = 'First track';
  let lyric = '[00:00.00]First line\n[00:02.00]Current line';
  let state = 1;
  let notifications = 0;
  let destroyed = 0;
  const commands = [];
  const listeners = new Map();
  const managerListeners = new Map();
  const controller = {
    on(name, ...args) { listeners.set(name, args.at(-1)); },
    off(name) { listeners.delete(name); },
    async getAVMetadata() { return { title, artist: 'Artist', lyric, duration: 120000 }; },
    async getAVPlaybackState() {
      return { state, duration: 120000, position: { elapsedTime: 2500, updateTime: Date.now() - 500 } };
    },
    async getValidCommands() { return ['play', 'pause', 'playNext', 'playPrevious']; },
    async getAVQueueItems() { return []; },
    async sendControlCommand(command) { commands.push(command.command); },
    async destroy() { destroyed++; }
  };
  const api = {
    PlaybackState: { PLAYBACK_STATE_PLAY: 1 },
    async getAllSessionDescriptors() { return descriptors; },
    async createController() { return controller; }
  };
  for (const event of ['SessionCreate', 'SessionDestroy', 'TopSessionChange']) {
    api[`on${event}`] = handler => managerListeners.set(event, handler);
    api[`off${event}`] = () => managerListeners.delete(event);
  }
  const { MediaSessionBridge } = loadEts('session/MediaSessionBridge.ets', { '@ohos.multimedia.avsession': api });
  const bridge = new MediaSessionBridge(() => notifications++);
  assert.equal((await bridge.refresh()).commands.length, 0);
  descriptors = [{ sessionId: 'music', type: 'audio', isTopSession: true, isActive: true,
    elementName: { bundleName: 'example.music', abilityName: 'MainAbility' } }];
  managerListeners.get('SessionCreate')();
  assert.equal(notifications, 1);
  const first = await bridge.refresh();
  assert.equal(first.title, 'First track');
  assert.equal(first.durationMs, 120000);
  assert.ok(first.positionMs >= 2500);
  assert.equal(first.lyric, 'Current line');
  title = 'Next track';
  listeners.get('metadataChange')();
  assert.equal((await bridge.refresh()).title, 'Next track');
  descriptors[0].isActive = false;
  state = 0;
  const paused = await bridge.refresh();
  assert.equal(paused.isPlaying, false);
  assert.equal(paused.positionMs, 2500, 'paused position must not advance from its last update timestamp');
  assert.equal(paused.bundleName, 'example.music');
  await bridge.send('play');
  assert.deepEqual(commands, ['play']);
  await bridge.close();
  assert.equal(destroyed, 1);
  assert.equal(listeners.size, 0);
  assert.equal(managerListeners.size, 0);
});
