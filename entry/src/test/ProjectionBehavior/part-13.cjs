const { assert, fs, path, vm, test, ts, sourceRoot, audioSenderFixture, loadEts, loadMethods,
  loadProjectionSettingsController, videoSenderFixture } = require('../ProjectionBehaviorSupport.cjs');

test('active media metadata is logged once per track or playback-state change', () => {
  const { ProjectionMediaCoordinator } = loadEts('pages/ProjectionMediaCoordinator.ets', {
    '@ohos.abilityAccessCtrl': {},
    '@ohos.app.ability.common': {},
    '../session/MediaSessionBridge': {
      EMPTY_PROJECTION_MEDIA: { title: '', artist: '', lyric: '', positionMs: 0, durationMs: 0, isPlaying: false,
        commands: [], queue: [], message: '' }
    },
    './ProjectionAppCatalog': { includeMediaSessionApp: apps => apps }
  });
  const logs = [];
  const controller = new ProjectionMediaCoordinator({
    getContext: () => ({}),
    getSnapshot: () => ({}),
    onSnapshot: () => {},
    getApps: () => [],
    onAppsChanged: () => {},
    onActionMessage: () => {},
    onLog: message => logs.push(message)
  });
  const snapshot = {
    bundleName: 'com.huawei.hmsapp.music',
    abilityName: 'MainAbility',
    title: 'Track One',
    artist: 'Artist',
    isPlaying: true
  };
  controller.logMediaSnapshotIfChanged(snapshot);
  controller.logMediaSnapshotIfChanged(snapshot);
  controller.logMediaSnapshotIfChanged({ ...snapshot, title: 'Track Two' });
  assert.equal(logs.length, 2);
  assert.match(logs[0], /Track One/);
  assert.match(logs[1], /Track Two/);
});

test('play and pause state stays optimistic until AVSession confirms the command', async () => {
  const { ProjectionMediaCoordinator } = loadEts('pages/ProjectionMediaCoordinator.ets', {
    '@ohos.abilityAccessCtrl': {},
    '@ohos.app.ability.common': {},
    '../session/MediaSessionBridge': {
      EMPTY_PROJECTION_MEDIA: { title: '', artist: '', lyric: '', positionMs: 0, durationMs: 0, isPlaying: false,
        commands: [], queue: [], message: '' }
    },
    './ProjectionAppCatalog': { includeMediaSessionApp: apps => apps }
  });
  const commands = [];
  let actualIsPlaying = false;
  let state = {
    title: 'Track', artist: 'Artist', lyric: '', positionMs: 1000, durationMs: 5000,
    isPlaying: false, commands: ['play', 'pause'], queue: [], message: ''
  };
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
    async refresh() {
      return {
        title: 'Track', artist: 'Artist', lyric: '', positionMs: 1000, durationMs: 5000,
        bundleName: 'music.app', isPlaying: actualIsPlaying, commands: ['play', 'pause'],
        queue: [], message: ''
      };
    }
  };

  await target.send('play');
  assert.equal(state.isPlaying, true);
  assert.equal(target.optimisticPlaybackState.isPlaying, true);
  actualIsPlaying = true;
  await target.refresh(target.bridge);
  assert.equal(state.isPlaying, true);
  assert.equal(target.optimisticPlaybackState, undefined);

  await target.send('pause');
  assert.equal(state.isPlaying, false);
  actualIsPlaying = true;
  await target.refresh(target.bridge);
  assert.equal(state.isPlaying, false,
    'an older playing snapshot must not immediately undo the pause state');
  assert.deepEqual(commands, ['play', 'pause']);
});

test('leaving projection pauses the active media session without terminating its app', async () => {
  const commands = [];
  let destroyed = false;
  const avSession = {
    PlaybackState: { PLAYBACK_STATE_PLAY: 2 },
    getAllSessionDescriptors: async () => [{
      isTopSession: true,
      isActive: true,
      type: 'audio',
      sessionId: 'music-session',
      elementName: { bundleName: 'com.huawei.hmsapp.music', abilityName: 'MainAbility' }
    }],
    createController: async () => ({
      getAVPlaybackState: async () => ({ state: 2 }),
      getValidCommands: async () => ['pause'],
      sendControlCommand: async command => { commands.push(command.command); },
      destroy: async () => { destroyed = true; }
    })
  };
  const Target = loadMethods('pages/Index.ets', 'Index', ['pauseActiveMediaOnProjectionStop'], { avSession });
  const target = new Target();
  const logs = [];
  target.logProtocol = (_stage, message) => logs.push(message);
  await target.pauseActiveMediaOnProjectionStop();
  assert.deepEqual(commands, ['pause']);
  assert.equal(destroyed, true);
  assert.ok(logs.some(message => message.includes('离车时已暂停音乐')));
});

test('media controls wait for the in-flight session refresh instead of using a stale snapshot', async () => {
  let descriptorCalls = 0;
  let resolveDescriptors;
  const avSession = {
    getAllSessionDescriptors() {
      descriptorCalls++;
      return new Promise(resolve => { resolveDescriptors = resolve; });
    },
    onSessionCreate() {},
    onSessionDestroy() {},
    onTopSessionChange() {}
  };
  const { MediaSessionBridge } = loadEts('session/MediaSessionBridge.ets', {
    '@ohos.multimedia.avsession': avSession
  });
  const bridge = new MediaSessionBridge();
  const first = bridge.refresh();
  let secondSettled = false;
  const second = bridge.refresh().then(snapshot => {
    secondSettled = true;
    return snapshot;
  });
  assert.equal(descriptorCalls, 1);
  await Promise.resolve();
  assert.equal(secondSettled, false);
  resolveDescriptors([]);
  const snapshots = await Promise.all([first, second]);
  assert.equal(snapshots[0].message, '未检测到活动音乐会话');
  assert.equal(snapshots[1].message, '未检测到活动音乐会话');
});

test('all HID reports in a TCP read are dispatched before awaiting any response write', async () => {
  const filename = path.join(sourceRoot, 'airplay/AirPlayEventChannel.ets');
  const source = fs.readFileSync(filename, 'utf8');
  const parsed = ts.createSourceFile(filename, source, ts.ScriptTarget.Latest, true);
  const declaration = parsed.statements.find(statement =>
    ts.isClassDeclaration(statement) && statement.name.text === 'AirPlayEventChannel');
  const method = declaration.members.find(member => member.name?.getText(parsed) === 'handleIncoming');
  const result = ts.transpileModule(`class Channel { ${method.getText(parsed)} } exports.Channel = Channel;`, {
    compilerOptions: { target: ts.ScriptTarget.ES2020, module: ts.ModuleKind.CommonJS }
  });
  const requests = [1, 2, 3].map(cseq => ({
    method: 'POST',
    target: '/command',
    cseq,
    body: new Uint8Array(0)
  }));
  const exports = {};
  vm.runInThisContext(`(function(exports, concatBytes, parseAirPlayEventRequests, buildAirPlayEventResponse,
    formatProtocolEvent, formatEventBodySummary) {
    ${result.outputText}
  })`)(exports, (...parts) => Uint8Array.from(parts.flatMap(part => [...part])),
    () => ({ requests, remaining: new Uint8Array(0) }), cseq => new Uint8Array([cseq]),
    (event, ...fields) => `${event} ${fields.join(' ')}`, () => 'empty body');
  const channel = new exports.Channel();
  channel.running = true;
  channel.receiveBuffer = new Uint8Array(0);
  channel.cipher = { async decrypt(data) { return data; } };
  channel.log = () => {};
  channel.receiveDiagnostics = { logQueueDelay: () => {}, logProcessingDelay: () => {} };
  channel.hidReportSummary = { record: () => 1 };
  const handled = [];
  channel.onRequest = request => { handled.push(request.cseq); return true; };
  let release;
  let writes = 0;
  const gate = new Promise(resolve => { release = resolve; });
  channel.sendPlaintext = async bytes => {
    writes++;
    assert.deepEqual(handled, [1, 2, 3]);
    assert.deepEqual([...bytes], [1, 2, 3]);
    await gate;
  };
  const operation = channel.handleIncoming(new Uint8Array([0]), Date.now());
  await Promise.resolve();
  assert.deepEqual(handled, [1, 2, 3]);
  release();
  await operation;
  assert.equal(writes, 1);
});

test('AirPlay mDNS discovery can release the ctrl invite wait early', () => {
  const { isAirPlayStartReady } = loadEts('session/airplay/AirPlayEndpointFactory.ets', {}, 'isAirPlayStartReady');
  assert.equal(isAirPlayStartReady(true, true, false, true), true);
  assert.equal(isAirPlayStartReady(true, false, true), true);
  assert.equal(isAirPlayStartReady(true, false, false, true), true);
  assert.equal(isAirPlayStartReady(true, true, false, false, true), true);
  assert.equal(isAirPlayStartReady(true, false, false, false, true), false);
  assert.equal(isAirPlayStartReady(false, true, true, true), false);
});

test('AirPlay mDNS callback rejects endpoints outside the selected WLAN prefix', async () => {
  const Target = loadMethods('session/SessionController.ets', 'SessionController',
    ['handleDiscoveredAirPlayService']);
  const target = new Target();
  const actions = [];
  target.wifiNetworkLease = { isAirPlayAddressOnSelectedNetwork: address => address.startsWith('10.36.232.') };
  target.events = {
    onAirPlayService: service => actions.push(['service', service.host]),
    onLog: message => actions.push(['log', message])
  };
  target.refreshDiscoveredAirPlay = () => actions.push(['refresh']);
  target.hasSelfContainedAirPlayEndpoint = () => false;
  target.clearAirPlayWaitTimers = () => actions.push(['clear-timers']);
  target.connectAirPlay = async () => { actions.push(['connect']); };
  target.reportError = error => { throw error; };
  target.mdnsAirPlayService = undefined;
  target.inviteReceived = false;
  target.airPlayInviteWaitElapsed = false;

  target.handleDiscoveredAirPlayService({ name: 'other', host: '192.168.1.5', port: 7000, txt: {} });
  assert.equal(target.mdnsAirPlayService, undefined);
  assert.deepEqual(actions, [['log', '忽略不属于车机 WLAN 网段的 AirPlay mDNS 地址：192.168.1.5']]);

  actions.length = 0;
  target.handleDiscoveredAirPlayService({ name: 'vehicle', host: '10.36.232.90', port: 7000, txt: {} });
  await Promise.resolve();
  assert.equal(target.mdnsAirPlayService.host, '10.36.232.90');
  assert.deepEqual(actions.map(action => action[0]), ['refresh', 'service', 'log', 'connect']);
});
