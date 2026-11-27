const { assert, fs, path, vm, test, ts, sourceRoot, audioSenderFixture, loadEts, loadMethods,
  loadProjectionSettingsController, videoSenderFixture } = require('../ProjectionBehaviorSupport.cjs');

test('HID drag scrolls the visible Apps and DockMenu lists in virtual-screen coordinates', () => {
  const Target = loadMethods('pages/ProjectionDashboard.ets', 'ProjectionDashboard', [
    'scrollControllerAt', 'handleTouchReport', 'screenToContentPoint', 'canvasPixelToContentPoint'
  ], {
    AppStorage: { get: key => ({ carplayProjectionHomeActive: true, carplayProjectionDisplayId: 7 })[key] },
    Math
  });
  const moves = [];
  const makeScroller = target => ({ scrollBy: (x, y) => moves.push({ target, x, y }) });
  const target = new Target();
  target.appsScroller = makeScroller('apps');
  target.dockMenuScroller = makeScroller('dock-menu');
  target.settingsScroller = makeScroller('settings');
  target.themesScroller = makeScroller('themes');
  target.sidebarMediaScroller = makeScroller('media');
  target.touchBounds = new Map([
    ['grid', { left: 0, top: 0, right: 200, bottom: 300 }],
    ['maps', { left: 200, top: 0, right: 400, bottom: 300 }]
  ]);
  target.getUIContext = () => ({ px2vp: value => value / 2 });
  target.contentScalePercent = 100;
  target.contentOffsetXPercent = 0;
  target.contentOffsetYPercent = 0;
  target.projectionViewportWidth = 400;
  target.projectionViewportHeight = 600;
  target.viewAreaOriginX = 0;
  target.viewAreaOriginY = 0;
  target.dashboardView = 'apps';
  target.handleTouchReport({ displayId: 7, contacts: [{ id: 0, down: true, x: 100, y: 200 }] });
  target.handleTouchReport({ displayId: 7, contacts: [{ id: 0, down: true, x: 100, y: 120 }] });
  target.handleTouchReport({ displayId: 7, contacts: [{ id: 0, down: false, x: 100, y: 120 }] });
  target.dashboardView = 'maps';
  target.handleTouchReport({ displayId: 7, contacts: [{ id: 0, down: true, x: 500, y: 200 }] });
  target.handleTouchReport({ displayId: 7, contacts: [{ id: 0, down: true, x: 500, y: 120 }] });
  assert.deepEqual(moves, [
    { target: 'apps', x: 0, y: 40 },
    { target: 'dock-menu', x: 0, y: 40 }
  ]);
});

test('accessory changeModes requests are granted and reflected in the mode state', () => {
  const source = fs.readFileSync(
    path.join(sourceRoot, 'airplay/media/AirPlayMediaSessionPayloads.ets'), 'utf8');
  const parsed = ts.createSourceFile('AirPlayMediaSession.ts', source, ts.ScriptTarget.Latest, true);
  const declaration = parsed.statements.find(statement =>
    ts.isClassDeclaration(statement) && statement.name?.text === 'AirPlayMediaSessionPayloads');
  const method = declaration.members.find(member => member.name?.text === 'applyChangeModes');
  const javascript = ts.transpileModule(`class Target { ${method.getText(parsed)} }`, {
    compilerOptions: { target: ts.ScriptTarget.ES2020 }
  }).outputText;
  const Modes = vm.runInNewContext(`${javascript}\nTarget`, { BigInt, Number });
  const dict = entries => ({ kind: 'dictionary', get(key) { return entries[key]; } });
  const integer = value => ({ kind: 'integer', integerValue: BigInt(value) });
  const defaults = { screenEntity: 1, screenPermanentEntity: 1, audioEntity: 1, audioPermanentEntity: 1,
    speechEntity: 0, speechMode: -1, phoneCallEntity: 0, turnByTurnEntity: 0 };
  const params = dict({
    resources: { kind: 'array', arrayValue: [dict({ resourceID: integer(1), transferType: integer(1) }),
      dict({ resourceID: integer(2), transferType: integer(3) })] },
    appStates: { kind: 'array', arrayValue: [dict({ appStateID: integer(3), state: { kind: 'boolean', boolValue: true } })] }
  });
  const next = Modes.applyChangeModes(defaults, params);
  assert.equal(next.screenEntity, 2);
  assert.equal(next.screenPermanentEntity, 2);
  assert.equal(next.audioEntity, 2);
  assert.equal(next.audioPermanentEntity, 1);
  assert.equal(next.turnByTurnEntity, 2);
  assert.equal(defaults.screenEntity, 1);
  const restored = Modes.applyChangeModes(next, dict({ resources: { kind: 'array', arrayValue: [
    dict({ resourceID: integer(2), transferType: integer(4) })] } }));
  assert.equal(restored.audioEntity, 1);
});

test('wireless network lease exposes only the selected network default gateway', async () => {
  let ipv6Only = false;
  const { WifiNetworkLease } = loadEts('network/WifiNetworkLease.ets', {
    '@ohos.net.connection': {
      NetBearType: { BEARER_WIFI: 1 },
      async getNetCapabilities() { return { bearerTypes: [1] }; },
      async getConnectionProperties() {
        return {
          interfaceName: 'wlan0',
          linkAddresses: [
            { address: { address: '10.36.232.67' } },
            { address: { address: 'fe80::2' } }
          ],
          routes: ipv6Only ? [
            { isDefaultRoute: true, hasGateway: true, gateway: { address: 'fe80::1' } }
          ] : [
            { isDefaultRoute: false, hasGateway: true, gateway: { address: '10.36.232.1' } },
            { isDefaultRoute: true, hasGateway: true, gateway: { address: '10.36.232.1' } },
            { isDefaultRoute: true, hasGateway: false, gateway: { address: 'fe80::1' } }
          ]
        };
      }
    }
  });
  const lease = new WifiNetworkLease();
  const addresses = await lease.getMatchingLocalAddresses({ netId: 3 }, '10.36.232.67');
  lease.localAddresses = addresses;
  assert.equal(lease.defaultGatewayAddress, '10.36.232.1');
  const ipv6OnlyLease = new WifiNetworkLease();
  ipv6Only = true;
  ipv6OnlyLease.localAddresses = await ipv6OnlyLease.getMatchingLocalAddresses({ netId: 3 }, '10.36.232.67');
  assert.equal(ipv6OnlyLease.defaultGatewayAddress, 'fe80::1%wlan0');
});

test('AirPlay mDNS discovery ignores a pending resolution after stop and restart', async () => {
  const handlers = [];
  const resolutions = [];
  const discovered = [];
  const discoveryService = () => ({
    on(_type, handler) { handlers.push(handler); },
    off() {},
    startSearchingMDNS() {},
    stopSearchingMDNS() {}
  });
  const { AirPlayMdnsDiscovery } = loadEts('network/AirPlayMdnsDiscovery.ets', {
    '@ohos.net.mdns': {
      createDiscoveryService: discoveryService,
      resolveLocalService: (_context, service) => new Promise(resolve => {
        resolutions.push(() => resolve({
          serviceName: service.serviceName,
          host: { address: '10.36.232.90' },
          port: 7000,
          serviceAttribute: []
        }));
      })
    },
    '@ohos.app.ability.common': {},
    '@ohos.util': {},
    '../session/ProtocolLogger': {
      formatProtocolEvent: (event, ...fields) => `【${event}】 ${fields.join(' ')}`
    }
  });
  const discovery = new AirPlayMdnsDiscovery({}, service => discovered.push(service), () => {});
  const found = { serviceName: 'receiver._airplay._tcp' };

  discovery.start();
  handlers[0](found);
  discovery.stop();
  discovery.start();
  resolutions[0]();
  await new Promise(resolve => setImmediate(resolve));
  assert.deepEqual(discovered, []);

  handlers[1](found);
  resolutions[1]();
  await new Promise(resolve => setImmediate(resolve));
  assert.deepEqual(discovered.map(service => service.host), ['10.36.232.90']);
  discovery.stop();
});

test('AirPlay RTSP probe declares the endpoint address family', async () => {
  const handlers = {};
  let connectOptions;
  const socket = {
    on(type, handler) { handlers[type] = handler; },
    off() {},
    async connect(options) { connectOptions = options; },
    async send() {
      handlers.message({ message: new TextEncoder().encode('RTSP/1.0 200 OK\r\n\r\n') });
    },
    async close() {}
  };
  const { AirPlayRtspProbe } = loadEts('network/AirPlayRtspProbe.ets', {
    '@ohos.net.socket': { constructTCPSocketInstance: () => socket },
    '../protocol/Iap2Codec': {
      decodeUtf8: bytes => new TextDecoder().decode(bytes),
      encodeUtf8: value => new TextEncoder().encode(value),
      toArrayBuffer: bytes => bytes.slice().buffer
    },
    '../protocol/CarPlaySenderCompatibility': { CARPLAY_SENDER_SOURCE_VERSION: '1.0' },
    './WifiNetworkAddress': { getSocketAddressFamily: address => address.includes(':') ? 2 : 1 }
  });
  const probe = new AirPlayRtspProbe();

  assert.equal(await probe.probe({ host: 'fe80::1%wlan0', port: 7000 }), 'RTSP/1.0 200 OK');
  assert.equal(connectOptions.address.family, 2);
});

test('wireless WLAN selection discards a candidate lost during asynchronous validation', async () => {
  const handlers = {};
  const pending = [];
  const logs = [];
  const { WifiNetworkLease } = loadEts('network/WifiNetworkLease.ets', {
    '@ohos.net.connection': {
      NetBearType: { BEARER_WIFI: 1 },
      async getAllNets() { return []; },
      async getNetCapabilities() { return { bearerTypes: [1] }; },
      getConnectionProperties() { return new Promise(resolve => pending.push(resolve)); },
      createNetConnection() { return {
        on(name, handler) { handlers[name] = handler; },
        register(callback) { callback(); },
        unregister(callback) { callback(); }
      }; }
    }
  });
  const lease = new WifiNetworkLease();
  const acquiring = lease.acquire('vehicle', () => {}, message => logs.push(message), '10.36.232.67');
  for (let i = 0; i < 20 && !handlers.netAvailable; i++) await Promise.resolve();
  const handle = { netId: 3 };
  handlers.netAvailable(handle);
  for (let i = 0; i < 20 && !pending.length; i++) await Promise.resolve();
  handlers.netLost(handle);
  const properties = { interfaceName: 'wlan0', linkAddresses: [
    { address: { address: '10.36.232.67' }, prefixLength: 24 }
  ] };
  pending[0](properties);
  for (let i = 0; i < 20; i++) await Promise.resolve();
  assert.equal(lease.netHandle, undefined);
  assert.equal(logs.some(message => message.includes('已匹配车机 WLAN')), false);

  handlers.netAvailable(handle);
  for (let i = 0; i < 20 && pending.length < 2; i++) await Promise.resolve();
  pending[1](properties);
  assert.equal((await acquiring).netId, 3);
  await lease.release();
});

test('projection builder reads current state and retains interactive callbacks', () => {
  const filename = path.join(sourceRoot, 'pages/ProjectionDashboardView.ets');
  const source = fs.readFileSync(filename, 'utf8').replace('@Builder', '');
  const script = ts.transpileModule(source, {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
  }).outputText;
  const exports = {};
  const renders = [];
  const requireMock = name => {
    if (name === '../video/ProjectionSettings') return { projectionTheme: () => ({ background: '#000' }) };
    if (name === './ProjectionDashboardShell') return { ProjectionDashboardShell: options => renders.push(options) };
    throw new Error(`Unexpected import ${name}`);
  };
  vm.runInThisContext(`(function(exports, require) { ${script}\n})`, { filename })(exports, requireMock);
  const state = { theme: 'aurora', dashboardView: 'home', splitMapRatio: 3, dockPosition: 'left' };
  const app = { appsGridTemplate: () => '', dockItems: () => [] };
  const presentation = new Proxy({}, { get: () => () => '' });
  let selected = '';
  const options = { state, app, presentation, bindings: { onThemeChange: value => { selected = value; } } };
  exports.renderProjectionDashboard(options);
  state.dashboardView = 'split';
  state.splitMapRatio = 5;
  exports.renderProjectionDashboard(options);
  assert.equal(renders[0].dashboardView, 'home');
  assert.equal(renders[1].dashboardView, 'split');
  assert.equal(renders[1].splitMapRatio, 5);
  renders[1].onThemeChange('ocean');
  assert.equal(selected, 'ocean');
});

test('AirPlay mode payload builders can use default modes', () => {
  const modes = loadEts('airplay/media/AirPlayMediaSessionTypes.ets');
  const node = {
    integer: value => value,
    dictionary: value => value,
    array: value => value,
    string: value => value
  };
  const { AirPlayMediaSessionPayloads } = loadEts('airplay/media/AirPlayMediaSessionPayloads.ets', {
    '../../audio/AudioRtpSender': {},
    '../../protocol/CarPlaySenderCompatibility': {},
    '../BinaryPlist': { PlistNode: node, BinaryPlist: { encode: value => value } },
    './AirPlayMediaSessionTypes': modes,
    './AirPlayMediaHelpers': {}
  });
  const payload = AirPlayMediaSessionPayloads.buildModesChangedPayload();
  assert.equal(payload.get('type'), 'modesChanged');
  assert.equal(payload.get('params').get('resources')[0].get('entity'), 1);
});
