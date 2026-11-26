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
