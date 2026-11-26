const { assert, fs, path, vm, test, ts, sourceRoot, audioSenderFixture, loadEts, loadMethods,
  loadProjectionSettingsController, videoSenderFixture } = require('../ProjectionBehaviorSupport.cjs');

test('iAP2 Buick EA groups ignore the short language field and parse 16-bit protocol IDs', () => {
  const concatBytes = (...parts) => Uint8Array.from(parts.flatMap(part => [...part]));
  const parameter = (id, value) => {
    const length = value.length + 4;
    return concatBytes(
      Uint8Array.of(length >> 8, length & 0xff, id >> 8, id & 0xff),
      value
    );
  };
  const stringValue = text => new TextEncoder().encode(`${text}\0`);
  const group = (id, protocolId, name) => parameter(id, concatBytes(
    parameter(0, Uint8Array.of(0, protocolId)),
    parameter(1, stringValue(name))
  ));
  const decodeIap2Parameters = bytes => {
    const result = [];
    for (let offset = 0; offset < bytes.length;) {
      const length = (bytes[offset] << 8) | bytes[offset + 1];
      assert.ok(length >= 4 && offset + length <= bytes.length);
      const id = (bytes[offset + 2] << 8) | bytes[offset + 3];
      result.push({ id, value: bytes.slice(offset + 4, offset + length) });
      offset += length;
    }
    return result;
  };
  const { readEaProtocols } = loadEts('session/iap2/Iap2SessionProtocol.ets', {
    '@ohos.i18n': { System: { getSystemLanguage: () => 'en' } },
    '../../protocol/Iap2Codec': {
      concatBytes,
      decodeIap2Parameters,
      decodeIap2String: bytes => new TextDecoder().decode(bytes).split('\0')[0],
      formatIap2LinkPayloadDiagnostic: () => '',
      groupedParameter: parameter,
      numberParameter: parameter,
      stringParameter: (id, value) => parameter(id, stringValue(value))
    },
    '../ProtocolLogger': { formatProtocolEvent: () => '' }
  });
  const body = concatBytes(
    parameter(0x0c, new TextEncoder().encode('zh')),
    group(0x11, 2, 'CinemoBTComponent'),
    group(0x18, 3, 'CinemoWIFIComponent'),
    group(0x12, 1, 'CinemoHIDRemote')
  );

  assert.deepEqual(readEaProtocols(body), [
    { protocolId: 2, name: 'CinemoBTComponent' },
    { protocolId: 3, name: 'CinemoWIFIComponent' },
    { protocolId: 1, name: 'CinemoHIDRemote' }
  ]);
});

test('wireless gateway fallback uses only the selected WLAN route and never invents a pairing key', () => {
  const { makeAirPlayServiceFromEndpoint } = loadEts('session/airplay/AirPlayEndpointFactory.ets', {},
    'makeAirPlayServiceFromEndpoint');
  const Target = loadMethods('session/SessionController.ets', 'SessionController',
    ['refreshDiscoveredAirPlay', 'makeAirPlayGatewayFallback'], { makeAirPlayServiceFromEndpoint });
  const target = new Target();
  target.events = { onLog() {} };
  target.wifiNetworkLease = { defaultGatewayAddress: '192.168.49.1' };
  target.iap2AirPlayEndpoint = { addresses: [], port: 0, deviceIdentifier: 'AA:BB:CC:DD:EE:FF',
    publicKey: '', unrecognizedIdentity: 'untrusted-identity', sourceVersion: '450.14' };
  target.mdnsAirPlayService = undefined;
  target.airPlayIdentityConflict = false;
  target.refreshDiscoveredAirPlay();
  assert.equal(target.discoveredAirPlay.host, '192.168.49.1');
  assert.equal(target.discoveredAirPlay.port, 7000);
  assert.equal(target.discoveredAirPlay.txt.deviceid, 'AA:BB:CC:DD:EE:FF');
  assert.equal(Object.hasOwn(target.discoveredAirPlay.txt, 'pk'), false);

  target.wifiNetworkLease.defaultGatewayAddress = undefined;
  target.iap2AirPlayEndpoint = undefined;
  target.refreshDiscoveredAirPlay();
  assert.equal(target.discoveredAirPlay, undefined);
});

test('wireless startup rejects malformed and unauthenticated start requests', async () => {
  let valid = false;
  const Target = loadMethods('session/Iap2SenderSession.ets', 'Iap2SenderSession',
    ['receiveControlMessage', 'deferAuthenticatedMessage'], {
      MESSAGE: { CARPLAY_START_SESSION: 0x4301 },
      formatIap2MessageDiagnostic: () => '',
      decodeIap2Parameters: () => { if (!valid) throw new Error('invalid length'); return []; },
      parseWirelessSessionCredentials: () => undefined,
      parseWirelessSessionEndpoint: () => undefined
    });
  const target = new Target();
  target.log = () => {};
  target.authenticated = true;
  target.pendingAuthenticatedMessages = [];
  target.errorDetails = error => error.message;
  target.clearWifiConfigurationTimer = () => {};
  target.clearStartSessionWaitTimer = () => {};
  target.hasValidDeviceAddress = () => true;
  target.sendTransportIdentifier = async () => {};
  let invitations = 0;
  target.onEndpoint = () => { invitations++; };
  await target.receiveControlMessage(0x4301, new Uint8Array([0]));
  assert.equal(invitations, 0);
  valid = true;
  target.authenticated = false;
  await target.receiveControlMessage(0x4301, new Uint8Array(0));
  assert.equal(invitations, 0);
  assert.equal(target.pendingAuthenticatedMessages.length, 1);
  target.authenticated = true;
  await target.receiveControlMessage(0x4301, new Uint8Array(0));
  assert.equal(invitations, 1);
});

test('wireless WLAN selection reuses the matching local network without requiring internet', async () => {
  const handlers = {};
  const cellular = { netId: 1 };
  const otherWifi = { netId: 2 };
  let bound = 0;
  const socketEvents = [];
  const vehicleWifi = { netId: 3, async bindSocket() { socketEvents.push('network-bind'); bound++; } };
  let unregistered = 0;
  const { WifiNetworkLease } = loadEts('network/WifiNetworkLease.ets', {
    '@ohos.net.connection': {
      NetBearType: { BEARER_WIFI: 1 },
      async getAllNets() { return [cellular, otherWifi, vehicleWifi]; },
      async getNetCapabilities(handle) { return { bearerTypes: [handle.netId === 1 ? 0 : 1] }; },
      async getConnectionProperties(handle) {
        return { interfaceName: 'wlan0', linkAddresses: [
          { address: { address: handle.netId === 3 ? '10.36.232.67' : '192.168.1.2' }, prefixLength: 24 },
          ...(handle.netId === 3 ? [{ address: { address: 'fe80::3' }, prefixLength: 64 }] : [])
        ] };
      },
      createNetConnection(specifier, timeout) {
        assert.equal(specifier.bearerPrivateIdentifier, undefined);
        assert.equal(timeout, 15000);
        return { on(name, handler) { handlers[name] = handler; },
          register(callback) { callback(); }, unregister(callback) { unregistered++; callback(); } };
      }
    }
  });
  const lease = new WifiNetworkLease();
  let lost = false;
  assert.equal((await lease.acquire('BUICK_7841', () => { lost = true; }, () => {}, '10.36.232.67')).netId, 3);
  assert.equal(lease.isAirPlayAddressOnSelectedNetwork('10.36.232.98'), true);
  assert.equal(lease.isAirPlayAddressOnSelectedNetwork('10.36.233.98'), false);
  assert.equal(lease.isAirPlayAddressOnSelectedNetwork('fe80::1899:7bff:fe39:e165%wlan0'), true);
  const selectedIpv6Address = lease.localAddresses.ipv6;
  const selectedIpv6PrefixLength = lease.localAddresses.ipv6PrefixLength;
  lease.localAddresses.ipv6 = '2001:db8:1::1';
  lease.localAddresses.ipv6PrefixLength = 64;
  assert.equal(lease.isAirPlayAddressOnSelectedNetwork('2001:db8:1::ab'), true);
  assert.equal(lease.isAirPlayAddressOnSelectedNetwork('2001:db8:2::ab'), false);
  lease.localAddresses.ipv6 = selectedIpv6Address;
  lease.localAddresses.ipv6PrefixLength = selectedIpv6PrefixLength;
  await lease.bindSocket({ async bind(address) {
    socketEvents.push('socket-bind');
    assert.deepEqual(address, { address: '10.36.232.67', family: 1, port: 0 });
  } }, 'test IPv4 TCP');
  await lease.bindSocket({ async bind(address) {
    assert.deepEqual(address, { address: 'fe80::3%wlan0', family: 2, port: 0 });
  } }, 'test IPv6 TCP', 2);
  await lease.bindSocket({ async bind(address) {
    assert.deepEqual(address, { address: '10.36.232.67', family: 1, port: 5353 });
  } }, 'test mDNS multicast', 1, 5353);
  assert.deepEqual(socketEvents, [
    'socket-bind', 'network-bind', 'network-bind', 'network-bind'
  ]);
  assert.equal(bound, 3);
  handlers.netLost(vehicleWifi);
  assert.equal(lost, true);
  await assert.rejects(lease.bindSocket({}), /默认路由/);
  await lease.release();
  assert.equal(unregistered, 1);
});

test('wireless network lease scopes link-local addresses to the selected interface', () => {
  const { WifiNetworkLease, orderAirPlayAddresses, stripIpv6ScopeId } = loadEts('network/WifiNetworkLease.ets', {
    '@ohos.net.connection': {}
  });
  const lease = new WifiNetworkLease();
  lease.localAddresses = { interfaceName: 'wlan0' };
  assert.equal(lease.scopeLinkLocalAddress('fe80::1899:7bff:fe39:e165'),
    'fe80::1899:7bff:fe39:e165%wlan0');
  assert.equal(lease.scopeLinkLocalAddress('fe80::1%wlan0'), 'fe80::1%wlan0');
  assert.equal(lease.scopeLinkLocalAddress('fe80::1%p2p0'), 'fe80::1%wlan0');
  assert.equal(lease.scopeLinkLocalAddress('192.168.49.1'), '192.168.49.1');
  assert.equal(stripIpv6ScopeId('fe80::1899:7bff:fe39:e165%wlan0'), 'fe80::1899:7bff:fe39:e165');
  assert.equal(stripIpv6ScopeId('192.168.49.1'), '192.168.49.1');
  assert.deepEqual(orderAirPlayAddresses([
    'fe80::1%wlan0', '2001:db8::1', '192.168.49.2', 'fe80::1', 'receiver.local', '192.168.49.2'
  ]), ['192.168.49.2', '2001:db8::1', 'fe80::1%wlan0', 'receiver.local']);
  lease.localAddresses = {};
  assert.throws(() => lease.scopeLinkLocalAddress('fe80::1'), /interfaceName is unavailable/);
});

test('IPv6 wildcard socket remains bound to the selected network without a listed local IPv6 address', async () => {
  const { WifiNetworkLease } = loadEts('network/WifiNetworkLease.ets', {
    '@ohos.net.connection': {}
  });
  const lease = new WifiNetworkLease();
  const actions = [];
  lease.netHandle = {
    netId: 25,
    async bindSocket() { actions.push('network-bind'); }
  };
  lease.localAddresses = { ipv4: '10.12.82.67', interfaceName: 'wlan0' };
  await lease.bindSocket({
    async bind(address) {
      actions.push({ type: 'local-bind', address });
    }
  }, 'test IPv6 TCP', 2);
  assert.deepEqual(actions, [
    { type: 'local-bind', address: { address: '::', family: 2, port: 0 } },
    'network-bind'
  ]);
});

test('AirPlay RTSP connection leaves IPv6 link-local routing to the selected network', async () => {
  const attempts = [];
  class StubAirPlayRtspClient {
    constructor() {}
    async connect(host, port) { attempts.push({ host, port }); }
    async close() {}
  }
  const { WifiNetworkLease, orderAirPlayAddresses, stripIpv6ScopeId } = loadEts('network/WifiNetworkLease.ets', {
    '@ohos.net.connection': {}
  });
  const Target = loadMethods('airplay/AirPlayPairingClient.ets', 'AirPlayPairingClient', ['connect'], {
    AirPlayRtspClient: StubAirPlayRtspClient,
    orderAirPlayAddresses,
    stripIpv6ScopeId,
    formatProtocolEvent: (event, ...fields) => `${event}:${fields.join(',')}`
  });
  const lease = new WifiNetworkLease();
  lease.localAddresses = { interfaceName: 'wlan0' };
  const target = new Target();
  target.log = () => {};
  target.onDisconnected = () => {};
  target.wifiNetworkLease = lease;
  await target.connect({
    host: 'fe80::1899:7bff:fe39:e165',
    addresses: [],
    port: 7000
  });
  assert.deepEqual(attempts, [{ host: 'fe80::1899:7bff:fe39:e165', port: 7000 }]);
  assert.equal(target.connectedHost, 'fe80::1899:7bff:fe39:e165');
});
