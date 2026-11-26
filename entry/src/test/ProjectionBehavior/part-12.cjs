const { assert, fs, path, vm, test, ts, sourceRoot, audioSenderFixture, loadEts, loadMethods,
  loadProjectionSettingsController, videoSenderFixture } = require('../ProjectionBehaviorSupport.cjs');

test('wireless iAP2 groups parse credentials and retain untrusted UUID identities', () => {
  const concatBytes = (...parts) => {
    const result = new Uint8Array(parts.reduce((length, part) => length + part.length, 0));
    let offset = 0;
    for (const part of parts) {
      result.set(part, offset);
      offset += part.length;
    }
    return result;
  };
  const encodeParameter = (id, value) => {
    const result = new Uint8Array(value.length + 4);
    result[0] = result.length >>> 8;
    result[1] = result.length & 0xff;
    result[2] = id >>> 8;
    result[3] = id & 0xff;
    result.set(value, 4);
    return result;
  };
  const decodeParameters = bytes => {
    const entries = [];
    for (let offset = 0; offset < bytes.length;) {
      const length = (bytes[offset] << 8) | bytes[offset + 1];
      assert.ok(length >= 4 && offset + length <= bytes.length);
      entries.push({
        id: (bytes[offset + 2] << 8) | bytes[offset + 3],
        value: bytes.slice(offset + 4, offset + length)
      });
      offset += length;
    }
    return entries;
  };
  const decodeString = bytes => new TextDecoder().decode(bytes).replace(/\0.*$/s, '');
  const encodeString = (id, text) => encodeParameter(id, new TextEncoder().encode(`${text}\0`));
  const encodeNumber = (id, number, width) => {
    const value = new Uint8Array(width);
    for (let index = width - 1; index >= 0; index--) {
      value[index] = number & 0xff;
      number >>>= 8;
    }
    return encodeParameter(id, value);
  };
  const codec = {
    concatBytes,
    decodeIap2Parameters: decodeParameters,
    decodeIap2String: decodeString,
    encodeUtf8: text => new TextEncoder().encode(text),
    encodeIap2Control: () => new Uint8Array(0),
    encodeIap2LinkFrame: () => new Uint8Array(0),
    formatIap2MessageDiagnostic: () => '',
    formatIap2RawFrameDiagnostic: () => '',
    Iap2ControlDecoder: class {},
    Iap2LinkDecoder: class {},
    numberParameter: encodeNumber,
    stringParameter: encodeString
  };
  const wirelessParser = loadEts('session/iap2/WirelessSessionParser.ets', {
    '../../protocol/Iap2Codec': codec
  });
  const credentials = wirelessParser.parseWirelessSessionCredentials(encodeParameter(1, concatBytes(
    encodeString(0, 'DIRECT-test-group'),
    encodeString(1, 'test-passphrase'),
    encodeNumber(2, 44, 1),
    encodeString(3, '192.168.49.1'),
    encodeNumber(4, 2, 1)
  )));
  assert.deepEqual(credentials, {
    ssid: 'DIRECT-test-group',
    password: 'test-passphrase',
    channel: 44,
    securityType: 2
  });
  const identity = '24e3089a-b9c8-4998-beb2-ae9120b44053';
  const endpoint = wirelessParser.parseWirelessSessionEndpoint(concatBytes(
    encodeParameter(1, encodeString(3, 'fe80::1')),
    encodeNumber(2, 7000, 4),
    encodeString(3, 'AA:BB:CC:DD:EE:FF'),
    encodeString(4, identity),
    encodeString(5, 'test-version')
  ));
  assert.equal(endpoint.port, 7000);
  assert.deepEqual(endpoint.addresses, ['fe80::1']);
  assert.equal(endpoint.publicKey, '');
  assert.equal(endpoint.unrecognizedIdentity, identity);
});

test('raw iAP2 diagnostics mask MFi and wireless secrets with and without the detection marker', () => {
  const frameCodec = loadEts('protocol/Iap2FrameCodec.ets');
  const { formatIap2RawFrameDiagnostic } = loadEts('protocol/Iap2Diagnostics.ets', {
    './Iap2FrameCodec': frameCodec,
    './RawByteFormatter': loadEts('protocol/RawByteFormatter.ets')
  });
  const concatBytes = (...parts) => {
    const result = new Uint8Array(parts.reduce((length, part) => length + part.length, 0));
    let offset = 0;
    for (const part of parts) {
      result.set(part, offset);
      offset += part.length;
    }
    return result;
  };
  const parameter = (id, value) => {
    const result = new Uint8Array(value.length + 4);
    result[0] = result.length >>> 8;
    result[1] = result.length & 0xff;
    result[2] = id >>> 8;
    result[3] = id & 0xff;
    result.set(value, 4);
    return result;
  };
  const frame = (messageId, body) => {
    const payload = concatBytes(
      new Uint8Array([0x40, 0x40, 0, body.length + 6, messageId >>> 8, messageId & 0xff]),
      body
    );
    const raw = new Uint8Array(10 + payload.length);
    raw.set([0xff, 0x5a, 0, raw.length, 0x40, 0, 0, 1, 0], 0);
    raw.set(payload, 9);
    return { control: 0x40, sequence: 0, acknowledgement: 0, sessionId: 1, payload, raw };
  };
  const challenge = new Uint8Array([0x11, 0x22, 0x33, 0x44]);
  const wifiPassword = new TextEncoder().encode('private-wifi-password');
  const authOutput = formatIap2RawFrameDiagnostic('TX',
    frame(0xaa02, parameter(0, challenge)), true);
  const wifiOutput = formatIap2RawFrameDiagnostic('TX',
    frame(0x5703, parameter(2, wifiPassword)));
  const wirelessOutput = formatIap2RawFrameDiagnostic('RX',
    frame(0x4301, parameter(1, parameter(1, wifiPassword))));
  for (const output of [authOutput, wifiOutput, wirelessOutput]) {
    assert.match(output, /\*\*/);
    assert.doesNotMatch(output, /11 22 33 44|70 72 69 76 61 74 65/);
  }
});

test('night mode received before UI setup is replayed, type checked and restricted to command requests', () => {
  const { PlistNode } = loadEts('airplay/BinaryPlist.ets', {
    '@ohos.util': {}, '../protocol/Iap2Codec': {}
  });
  let command;
  const Target = loadMethods('airplay/media/AirPlayMediaSessionEventTransport.ets',
    'AirPlayMediaSessionEventTransport',
    ['handleEventRequest', 'setNightModeHandler'], {
    BinaryPlist: { decode: () => command }, extractCarPlayTouchReport: () => undefined,
    isForceKeyFrameCommand: () => false
  });
  const target = new Target();
  const logs = [];
  target.log = line => logs.push(line);
  const request = { method: 'POST', target: '/command', cseq: 1, body: new Uint8Array([1]) };
  const nightCommand = value => PlistNode.dictionary(new Map([
    ['type', PlistNode.string('setNightMode')],
    ['params', PlistNode.dictionary(new Map([['nightMode', value]]))]
  ]));
  command = nightCommand(PlistNode.boolean(true));
  target.handleEventRequest(request);
  const changes = [];
  target.setNightModeHandler(value => changes.push(value));
  assert.deepEqual(changes, [true]);
  command = nightCommand(PlistNode.string('false'));
  target.handleEventRequest(request);
  assert.deepEqual(changes, [true]);
  assert.ok(logs.some(line => line.includes('requires params.nightMode Boolean')));
  command = nightCommand(PlistNode.boolean(false));
  target.handleEventRequest({ ...request, method: 'GET' });
  assert.deepEqual(changes, [true]);
  target.handleEventRequest(request);
  assert.deepEqual(changes, [true, false]);
  target.setNightModeHandler(undefined);
});

test('vehicle overlays work while unverified third-party launch requests stay disabled', () => {
  const stored = new Map();
  const Target = loadMethods('pages/ProjectionDashboard.ets', 'ProjectionDashboard', [
    'selectApp', 'showDashboardView', 'setNavigationPreview'
  ], {
    AppStorage: {
      setOrCreate: (name, value) => stored.set(name, value),
      get: key => stored.get(key)
    }
  });
  const target = new Target();
  const { ProjectionTouchRouter } = loadEts('pages/ProjectionTouchRouter.ets');
  target.touchRouter = new ProjectionTouchRouter();
  target.touchRouter.touchBounds = new Map();
  target.onHomeClick = () => { throw new Error('must not release an existing app for a vehicle page'); };
  target.showDashboardView('apps');
  assert.equal(stored.get('carplayDashboardView'), 'apps');
  target.selectApp({ category: 'vehicle', view: 'themes' });
  assert.equal(target.dashboardView, 'themes');
  assert.equal(stored.get('carplayDashboardView'), 'themes');
  let opened;
  target.onAppClick = app => { opened = app.uri; };
  target.selectApp({
    appId: 'huawei-music',
    uri: 'carplay-client://v1/apps/huawei-music/launch',
    launchState: 'UNVERIFIED',
    unavailableReason: '入口尚未验证',
    category: 'music'
  });
  assert.equal(opened, undefined);
  assert.equal(target.appDiscoveryMessage, '入口尚未验证');
  assert.equal(stored.get('carplayDashboardView'), 'themes');
});

test('active media sessions are not treated as verified app launch targets', () => {
  const { includeMediaSessionApp } = loadEts('pages/ProjectionAppCatalog.ets');
  const apps = includeMediaSessionApp([], 'com.huawei.hmsapp.music', 'MainAbility');
  assert.equal(apps[0].label, '\u5f53\u524d\u64ad\u653e\u5668');
  assert.equal(apps[0].bundleName, 'com.huawei.hmsapp.music');
  assert.equal(apps[0].abilityName, 'MainAbility');
  assert.equal(apps[0].launchState, 'UNVERIFIED');
  assert.equal(apps[0].launchTarget, undefined);
  assert.equal(includeMediaSessionApp(apps, 'com.huawei.hmsapp.music', 'MainAbility').length, 1);
});

test('an active media session does not imply a verified app launch target', () => {
  const { includeMediaSessionApp } = loadEts('pages/ProjectionAppCatalog.ets');
  const maps = [{ appId: 'amap', uri: 'carplay-client://v1/apps/amap/launch', category: 'map' }];
  const apps = includeMediaSessionApp(maps, 'com.huawei.hmsapp.music', 'MainAbility');
  assert.equal(apps.length, 2);
  assert.equal(apps[1].category, 'music');
  assert.equal(apps[1].bundleName, 'com.huawei.hmsapp.music');
  assert.equal(apps[1].abilityName, 'MainAbility');
  assert.equal(apps[1].launchState, 'UNVERIFIED');
  assert.equal(apps[1].launchTarget, undefined);
  assert.equal(includeMediaSessionApp(apps, 'com.huawei.hmsapp.music', 'MainAbility').length, 2);
  assert.equal(includeMediaSessionApp(apps), apps);
  assert.equal(maps.length, 1);
});
