const { assert, fs, path, vm, test, ts, sourceRoot, audioSenderFixture, loadEts, loadMethods,
  loadProjectionSettingsController, videoSenderFixture } = require('../ProjectionBehaviorSupport.cjs');

test('AirPlay RTSP connect preserves the IPv6 link-local interface scope', async () => {
  let connectOptions;
  const socket = {
    on() {},
    async connect(options) { connectOptions = options; }
  };
  const Target = loadMethods('airplay/AirPlayRtspConnection.ets', 'AirPlayRtspConnection', ['connect'], {
    netSocket: { constructTCPSocketInstance: () => socket },
    getSocketAddressFamily: address => address.includes(':') ? 2 : 1,
    formatNetworkError: error => error.message
  });
  const target = new Target();
  target.socket = undefined;
  target.disconnectNotified = false;
  target.onMessage = () => {};
  target.onError = () => {};
  target.onDisconnected = () => {};
  target.onBound = () => {};
  target.onConnectFailure = () => {};
  target.wifiNetworkLease = {
    scopeLinkLocalAddress: address => `${address.split('%')[0]}%wlan0`,
    async bindSocket() { return true; }
  };
  target.onError = () => {};
  target.onDisconnected = () => {};

  await target.connect('fe80::1899:7bff:fe39:e165%wlan0', 7000);
  assert.equal(connectOptions.address.address, 'fe80::1899:7bff:fe39:e165%wlan0');
  assert.equal(connectOptions.address.family, 2);
  assert.equal(connectOptions.address.port, 7000);
});

test('AirPlay RTSP response parser waits for complete bodies and validates CSeq', () => {
  const { parseAirPlayRtspResponse } = loadEts('airplay/AirPlayRtspResponseParser.ets', {
    '../protocol/Iap2Codec': { decodeUtf8: bytes => Buffer.from(bytes).toString('utf8') }
  });
  const wire = Buffer.from(
    'RTSP/1.0 200 OK\r\nCSeq: 7\r\nContent-Length: 4\r\n\r\ndata'
  );
  assert.equal(parseAirPlayRtspResponse(new Uint8Array(wire.slice(0, -1)), 7), undefined);
  const parsed = parseAirPlayRtspResponse(new Uint8Array(wire), 7);
  assert.equal(parsed.response.statusCode, 200);
  assert.equal(parsed.response.headers.get('cseq'), '7');
  assert.equal(Buffer.from(parsed.response.body).toString('utf8'), 'data');
  assert.equal(parsed.consumedBytes, wire.length);
  assert.throws(() => parseAirPlayRtspResponse(new Uint8Array(wire), 8), /CSeq mismatch/);
});

test('AirPlay event channel preserves the IPv6 link-local interface scope', async () => {
  let connectOptions;
  const socket = {
    on() {},
    async connect(options) { connectOptions = options; }
  };
  const Target = loadMethods('airplay/AirPlayEventChannel.ets', 'AirPlayEventChannel',
    ['connect'], {
      netSocket: { constructTCPSocketInstance: () => socket },
      getSocketAddressFamily: address => address.includes(':') ? 2 : 1,
      formatProtocolEvent: () => ''
    });
  const target = new Target();
  target.log = () => {};
  target.wifiNetworkLease = {
    scopeLinkLocalAddress: address => `${address}%wlan0`,
    async bindSocket() { return true; }
  };

  await target.connect('fe80::1899:7bff:fe39:e165', 7000);
  assert.equal(connectOptions.address.address, 'fe80::1899:7bff:fe39:e165%wlan0');
  assert.equal(connectOptions.address.family, 2);
  assert.equal(connectOptions.address.port, 7000);
});

test('AirPlay video TCP preserves the IPv6 link-local interface scope', async () => {
  let connectOptions;
  const socket = {
    on() {},
    off() {},
    async connect(options) { connectOptions = options; },
    async close() {}
  };
  const Target = loadMethods('airplay/media/AirPlayMediaSessionTransportBase.ets',
    'AirPlayMediaSessionTransportBase', ['openVideoDataPort'], {
      netSocket: { constructTCPSocketInstance: () => socket },
      getSocketAddressFamily: address => address.includes(':') ? 2 : 1
    });
  const target = new Target();
  target.receiverHost = 'fe80::1899:7bff:fe39:e165';
  target.log = () => {};
  target.reportVideoSocketFailure = () => {};
  target.wifiNetworkLease = {
    scopeLinkLocalAddress: address => `${address}%wlan0`,
    async bindSocket() { return true; }
  };

  await target.openVideoDataPort(7001);
  assert.equal(connectOptions.address.address, 'fe80::1899:7bff:fe39:e165%wlan0');
  assert.equal(connectOptions.address.family, 2);
  assert.equal(connectOptions.address.port, 7001);
});

test('AirPlay RTSP tries IPv4 endpoint candidates before IPv6 candidates', async () => {
  const attempts = [];
  class StubAirPlayRtspClient {
    constructor() {}
    async connect(host, port) { attempts.push({ host, port }); }
    async close() {}
  }
  const { orderAirPlayAddresses, stripIpv6ScopeId } = loadEts('network/WifiNetworkLease.ets', {
    '@ohos.net.connection': {}
  });
  const Target = loadMethods('airplay/AirPlayPairingClient.ets', 'AirPlayPairingClient', ['connect'], {
    AirPlayRtspClient: StubAirPlayRtspClient,
    orderAirPlayAddresses,
    stripIpv6ScopeId,
    formatProtocolEvent: (event, ...fields) => `${event}:${fields.join(',')}`
  });
  const target = new Target();
  target.log = () => {};
  target.onDisconnected = () => {};
  target.wifiNetworkLease = { scopeLinkLocalAddress: address => address };
  await target.connect({
    host: 'fe80::1899:7bff:fe39:e165',
    addresses: ['2001:db8::2', '192.168.49.8'],
    port: 7000
  });
  assert.deepEqual(attempts, [{ host: '192.168.49.8', port: 7000 }]);
});

test('wireless WLAN selection cancels pending acquisition and ignores late availability', async () => {
  const handlers = {};
  let registered = false;
  let unregistered = 0;
  const { WifiNetworkLease } = loadEts('network/WifiNetworkLease.ets', {
    '@ohos.net.connection': {
      NetBearType: { BEARER_WIFI: 1 },
      async getAllNets() { return []; },
      async getNetCapabilities() { return { bearerTypes: [1] }; },
      async getConnectionProperties() { return { linkAddresses: [{ address: { address: '10.36.232.67' } }] }; },
      createNetConnection() { return {
        on(name, handler) { handlers[name] = handler; },
        register(callback) { registered = true; callback(); },
        unregister(callback) { unregistered++; callback(); }
      }; }
    }
  });
  const lease = new WifiNetworkLease();
  const acquiring = lease.acquire('BUICK_7841', () => {}, () => {}, '10.36.232.67');
  const rejected = assert.rejects(acquiring, /取消/);
  for (let turn = 0; turn < 20; turn++) await Promise.resolve();
  assert.equal(registered, true);
  await lease.release();
  await rejected;
  handlers.netAvailable({ netId: 3 });
  for (let turn = 0; turn < 10; turn++) await Promise.resolve();
  await assert.rejects(lease.bindSocket({}), /默认路由/);
  assert.equal(unregistered, 1);
});

test('wireless discovery and ctrl advertisement start only after network selection', async () => {
  const Target = loadMethods('session/SessionController.ets', 'SessionController', ['joinVehicleWifi']);
  const target = new Target();
  const actions = [];
  target.running = true;
  target.wifiJoinGeneration = 0;
  target.wifiReconnectTimer = -1;
  target.wifiReconnectAttempts = 0;
  target.clearWifiReconnectTimer = () => {};
  target.scheduleWifiReconnect = () => {};
  target.deviceAddress = '40:06:34:E5:ED:EA';
  target.adapterMode = false;
  target.bluetooth = { setAdapterHandoffCompleted() {} };
  target.credentials = { ssid: 'BUICK_7841', password: 'test-password', securityType: 3, channel: 149 };
  target.iap2 = { isAuthenticationComplete: true, async onWifiConnected() { actions.push('iap2'); } };
  target.events = { onLog() {}, onStatus() {} };
  target.requestPermissions = async () => {};
  target.wifi = { async connect() { return { ssid: 'BUICK_7841', ipAddress: '10.36.232.67' }; } };
  target.startControlAdvertisement = async (reannounce) => {
    actions.push(reannounce ? 'reannounce' : 'advertise');
  };
  target.startAirPlayDiscovery = () => { actions.push('discovery'); };
  target.startAirPlayPrerequisiteWait = () => {};
  let finishNetwork;
  target.wifiNetworkLease = { acquire() {
    actions.push('network');
    return new Promise(resolve => { finishNetwork = resolve; });
  } };
  target.refreshDiscoveredAirPlay = () => { actions.push('refresh'); };
  target.connectAirPlay = async () => { actions.push('pair'); };
  const joining = target.joinVehicleWifi();
  for (let turn = 0; turn < 20 && !finishNetwork; turn++) await Promise.resolve();
  assert.deepEqual(actions, ['iap2', 'network']);
  assert.notEqual(target.vehicleWifiConnected, true);
  finishNetwork({ netId: 3 });
  await joining;
  assert.equal(target.vehicleWifiConnected, true);
  assert.deepEqual(actions, ['iap2', 'network', 'refresh', 'discovery', 'reannounce', 'pair']);
  assert.equal(actions.at(-1), 'pair');
  const diagnostics = [];
  target.vehicleWifiConnected = false;
  target.events.onLog = message => diagnostics.push(message);
  target.startControlAdvertisement = async () => { throw new Error('mDNS registration failed'); };
  target.wifiNetworkLease.acquire = async () => ({ netId: 3 });
  await target.joinVehicleWifi();
  assert.equal(target.vehicleWifiConnected, true);
  assert.equal(actions.filter(action => action === 'pair').length, 2);
  assert.ok(diagnostics.some(message => /WARN:.*控制广播不可用.*mDNS registration failed/.test(message)));
  target.vehicleWifiConnected = false;
  target.wifiNetworkLease.acquire = async () => { throw new Error('no matching WLAN'); };
  await assert.rejects(target.joinVehicleWifi(), /无法确认 WLAN 选路/);
  assert.equal(target.vehicleWifiConnected, false);
  assert.equal(actions.filter(action => action === 'pair').length, 2);
});

test('selected WLAN loss cleans up AirPlay and schedules a bounded Wi-Fi rejoin', async () => {
  const timers = [];
  let timerId = 0;
  const Target = loadMethods('session/SessionController.ets', 'SessionController',
    ['handleVehicleWifiLost', 'scheduleWifiReconnect'], {
      setTimeout: (callback, delayMs) => {
        timers.push({ callback, delayMs });
        return ++timerId;
      },
      clearTimeout: () => {}
    });
  const target = new Target();
  const actions = [];
  let rejoins = 0;
  target.running = true;
  target.credentials = { ssid: 'CAR_HOTSPOT', password: 'hidden' };
  target.wifiReconnectTimer = -1;
  target.wifiReconnectAttempts = 0;
  target.wifiLostCleanupInProgress = false;
  target.clearWifiReconnectTimer = () => {};
  target.clearPendingStartSessionTimer = () => {};
  target.airPlayGeneration = 0;
  target.airPlayConnectAttempted = true;
  target.airPlayConnectInProgress = true;
  target.vehicleWifiConnected = true;
  target.bluetooth = { setAdapterHandoffCompleted() {} };
  target.inviteReceived = true;
  target.events = { onStatus() {}, onLog() {} };
  target.clearAirPlayTimers = () => {};
  target.stopProjection = async () => { actions.push('projection'); };
  target.wifiNetworkLease = { release: async () => { actions.push('lease'); } };
  target.activePairing = {
    stopMediaSession: async () => { actions.push('media'); },
    close: async () => { actions.push('pairing'); }
  };
  target.discovery = { stop: () => { actions.push('discovery'); } };
  target.ctrlAdvertiser = { stop: async () => { actions.push('advertiser'); } };
  target.joinVehicleWifi = async () => { rejoins++; };

  await target.handleVehicleWifiLost('selected network lost');
  assert.equal(target.vehicleWifiConnected, false);
  assert.equal(target.inviteReceived, false);
  assert.deepEqual(actions, ['media', 'projection', 'pairing', 'discovery', 'advertiser', 'lease']);
  assert.equal(timers[0].delayMs, 1000);
  timers.shift().callback();
  for (let turn = 0; turn < 5; turn++) await Promise.resolve();
  assert.equal(rejoins, 1);
});
