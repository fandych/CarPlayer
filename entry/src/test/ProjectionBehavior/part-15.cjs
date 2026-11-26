const { assert, fs, path, vm, test, ts, sourceRoot, audioSenderFixture, loadEts, loadMethods,
  loadProjectionSettingsController, videoSenderFixture } = require('../ProjectionBehaviorSupport.cjs');

test('CarPlay ctrl reannouncement preserves its port and uses a dedicated source version', async () => {
  const actions = [];
  const Target = loadMethods('network/CarPlayCtrlAdvertiser.ets', 'CarPlayCtrlAdvertiser',
    ['reannounce', 'createServiceInfo'], {
      CARPLAY_CTRL_SOURCE_VERSION: '950.7.1',
      encodeUtf8: text => new TextEncoder().encode(text),
      formatProtocolEvent: event => event,
      mdns: {
        async removeLocalService(_context, service) { actions.push({ type: 'remove', service }); },
        async addLocalService(_context, service) {
          actions.push({ type: 'add', service });
          return service;
        }
      },
      describeSocketError: error => error instanceof Error ? error.message : String(error)
    });
  const advertiser = new Target();
  advertiser.context = {};
  advertiser.deviceAddress = '40:06:34:E5:ED:EA';
  advertiser.server = {};
  advertiser.servicePort = 42051;
  advertiser.service = { port: 42051 };
  advertiser.toNumberArray = bytes => Array.from(bytes);
  advertiser.onLog = message => actions.push({ type: 'log', message });

  await advertiser.reannounce();

  assert.equal(actions[0].type, 'remove');
  assert.equal(actions[1].type, 'add');
  assert.equal(actions[1].service.port, 42051);
  const attributes = Object.fromEntries(actions[1].service.serviceAttribute.map(attribute => [
    attribute.key,
    new TextDecoder().decode(new Uint8Array(attribute.value))
  ]));
  assert.equal(attributes.id, '40:06:34:E5:ED:EA');
  assert.equal(attributes.srcvers, '950.7.1');
  assert.equal(advertiser.server !== undefined, true);
});

test('wireless startup keeps address candidates without treating UUID identities as public keys', () => {
  const source = fs.readFileSync(path.join(sourceRoot, 'session/iap2/WirelessSessionParser.ets'), 'utf8');
  const parsed = ts.createSourceFile('WirelessSessionParser.ts', source, ts.ScriptTarget.Latest, true);
  const declaration = parsed.statements.find(statement =>
    ts.isFunctionDeclaration(statement) && statement.name?.text === 'parseWirelessSessionEndpoint');
  const javascript = ts.transpileModule(declaration.getText(parsed), {
    compilerOptions: { target: ts.ScriptTarget.ES2020, module: ts.ModuleKind.CommonJS }
  }).outputText;
  const body = new Uint8Array([1]);
  const group = new Uint8Array([2]);
  const encode = value => new TextEncoder().encode(value + '\0');
  const fields = [
    { id: 1, value: group }, { id: 2, value: new Uint8Array([0, 0, 0x1b, 0x58]) },
    { id: 3, value: encode('EC:D9:09:40:7A:49') },
    { id: 4, value: encode('24e3089a-b9c8-4998-beb2-ae9120b44053') },
    { id: 5, value: encode('450.14') }
  ];
  const exports = {};
  vm.runInNewContext(javascript, {
    exports, Uint8Array,
    decodeIap2Parameters: bytes => bytes === body ? fields : [
      { id: 3, value: encode('fe80::1899:7bff:fe39:e165') },
      { id: 3, value: encode('192.168.49.1') }
    ],
    decodeIap2String: bytes => new TextDecoder().decode(bytes).replace(/\0.*$/s, '')
  });
  const parse = exports.parseWirelessSessionEndpoint;
  const candidate = parse(body);
  assert.equal(candidate.port, 7000);
  assert.deepEqual([...candidate.addresses], ['fe80::1899:7bff:fe39:e165', '192.168.49.1']);
  assert.equal(candidate.publicKey, '');
  assert.equal(candidate.unrecognizedIdentity, '24e3089a-b9c8-4998-beb2-ae9120b44053');
  fields[3].value = encode('a'.repeat(64));
  assert.equal(parse(body).publicKey, 'a'.repeat(64));
  assert.equal(parse(body).unrecognizedIdentity, undefined);
  fields[1].value = new Uint8Array([0x1b, 0x58]);
  assert.equal(parse(body), undefined);
  fields[1].value = new Uint8Array(4);
  assert.equal(parse(body), undefined);
});

test('iAP2 start request does not masquerade as ctrl invitation', async () => {
  const Target = loadMethods('session/SessionController.ets', 'SessionController',
    ['handleIap2AirPlayEndpoint', 'startControlAdvertisement'], {
      CarPlayCtrlAdvertiser: class {
        constructor(_context, _address, onInvite) {
          this.onInvite = onInvite;
        }
        async start() {
          this.onInvite();
        }
      }
    });
  const target = new Target();
  let connections = 0;
  target.running = true;
  target.inviteReceived = false;
  target.vehicleWifiConnected = true;
  target.hasValidDeviceAddress = () => true;
  target.clearPendingStartSessionTimer = () => {};
  target.clearAirPlayInviteWaitTimer = () => {};
  target.startAirPlayPrerequisiteWait = () => {};
  target.startAirPlayEndpointResolutionWait = () => {};
  target.events = { onLog() {}, onStatus() {}, onAirPlayService() {} };
  target.refreshDiscoveredAirPlay = () => {};
  target.discoveredAirPlay = { host: '192.168.49.1', port: 7000 };
  target.connectAirPlay = async () => { connections++; };
  target.handleIap2AirPlayEndpoint(undefined);
  assert.equal(target.airPlayStartSessionReceived, true);
  assert.equal(target.inviteReceived, false);
  assert.equal(connections, 1);
  await target.startControlAdvertisement();
  assert.equal(target.inviteReceived, true);
  assert.equal(connections, 3);
  target.inviteReceived = false;
  target.running = false;
  target.handleIap2AirPlayEndpoint(undefined);
  assert.equal(target.inviteReceived, false);
});

test('new-protocol startup announces availability without probing legacy Wi-Fi', async () => {
  const Target = loadMethods('session/Iap2SenderSession.ets', 'Iap2SenderSession',
    ['requestWifiConfiguration'], {
      MESSAGE: { CARPLAY_AVAILABILITY: 0x4300, CARPLAY_START_SESSION: 0x4301 },
      shouldProbeLegacyWifi: () => false
    });
  const target = new Target();
  target.accessorySendMessages = [0x4301];
  target.accessoryReceiveMessages = [0x4300];
  target.log = () => {};
  let announcements = 0;
  target.sendDeviceAnnouncement = async () => { announcements++; };
  target.startWifiConfigurationTimer = () => { throw new Error('must wait for a start request'); };
  await target.requestWifiConfiguration();
  assert.equal(announcements, 1);
});

test('iAP2 hands 0x5703 credentials to Wi-Fi while announcing CarPlay immediately', async () => {
  const Target = loadMethods('session/Iap2SenderSession.ets', 'Iap2SenderSession',
    ['receiveControlMessage'], {
      MESSAGE: { WIFI_CONFIGURATION: 0x5703 },
      formatIap2MessageDiagnostic: () => '',
      encodeUtf8: value => new TextEncoder().encode(value)
    });
  const target = new Target();
  const actions = [];
  target.started = true;
  target.authenticated = true;
  target.log = () => {};
  target.wifiConfigurationTimer = undefined;
  target.wifiConfigurationRescueGeneration = 0;
  target.clearOptionalHandshakeWaits = () => {};
  target.parseWifi = () => ({ ssid: 'CAR_HOTSPOT', password: 'hidden', securityType: 2, channel: 0 });
  target.onWifi = () => { actions.push('join-wifi'); };
  target.sendDeviceAnnouncement = async () => { actions.push('announce-0x4300'); };
  target.startStartSessionWaitTimer = () => { actions.push('wait-0x4301'); };

  await target.receiveControlMessage(0x5703, new Uint8Array([1]));
  assert.deepEqual(actions, ['join-wifi', 'announce-0x4300', 'wait-0x4301']);
});

test('post-MFi startup sends greetings and opens declared EA sessions before Wi-Fi', async () => {
  const timers = [];
  const Target = loadMethods('session/Iap2SenderSession.ets', 'Iap2SenderSession',
    ['startPostAuthenticationSequence'], {
      MESSAGE: { EA_OPEN_SESSION: 0xea00, EA_SESSION_STATUS: 0xea03 },
      concatBytes: (...parts) => Uint8Array.from(parts.flatMap(part => Array.from(part))),
      numberParameter: (id, value, width) => new Uint8Array([id, value, width]),
      stringParameter: (id, value) => new TextEncoder().encode(`${id}:${value}`),
      setTimeout: (callback, delayMs) => {
        timers.push({ callback, delayMs });
        return timers.length;
      }
    });
  const target = new Target();
  const actions = [];
  target.started = true;
  target.authenticated = true;
  target.sessionGeneration = 4;
  target.accessoryEaProtocols = [{ protocolId: 7, name: 'com.example.ea' }];
  target.accessorySendMessages = [0xea03];
  target.log = () => {};
  target.sendDeviceStateGreetings = async () => { actions.push('greetings'); };
  target.sendControl = async messageId => { actions.push(messageId); };

  await target.startPostAuthenticationSequence(4);
  assert.deepEqual(actions, ['greetings', 0xea00]);
  assert.equal(timers[0].delayMs, 500);
});

test('iAP2 StartHID is acknowledged before Wi-Fi configuration begins', async () => {
  const Target = loadMethods('session/Iap2SenderSession.ets', 'Iap2SenderSession',
    ['receiveControlMessage'], {
      MESSAGE: { START_HID: 0x6800, DEVICE_HID_REPORT: 0x6801 },
      formatIap2MessageDiagnostic: () => '',
      clearTimeout: () => {},
      concatBytes: (...parts) => Uint8Array.from(parts.flatMap(part => Array.from(part))),
      numberParameter: (id, value, width) => new Uint8Array([id, value, width])
    });
  const target = new Target();
  const actions = [];
  target.log = () => {};
  target.authenticated = true;
  target.hidStartWaitTimer = 1;
  target.parameter = (id, value) => new Uint8Array([id, ...value]);
  target.sendControl = async messageId => { actions.push(messageId); };
  target.requestWifiConfiguration = async () => { actions.push('wifi'); };

  await target.receiveControlMessage(0x6800, new Uint8Array(0));
  assert.deepEqual(actions, [0x6801, 'wifi']);
  actions.length = 0;
  target.hidStartWaitTimer = undefined;
  target.wifiConfigurationReceived = true;
  await target.receiveControlMessage(0x6800, new Uint8Array(0));
  assert.deepEqual(actions, [0x6801]);
});

test('iAP2 defers early Wi-Fi and CarPlay session messages until MFi completes', async () => {
  const MESSAGE = {
    WIFI_CONFIGURATION: 0x5703,
    CARPLAY_START_SESSION: 0x4301
  };
  const Target = loadMethods('session/Iap2SenderSession.ets', 'Iap2SenderSession',
    ['receiveControlMessage', 'deferAuthenticatedMessage', 'replayAuthenticatedMessages'], {
      MESSAGE,
      formatIap2MessageDiagnostic: () => ''
    });
  const target = new Target();
  const handled = [];
  const logs = [];
  target.started = true;
  target.authenticated = false;
  target.mfiOnlyVirtualLink = false;
  target.pendingAuthenticatedMessages = [];
  target.log = message => logs.push(message);

  await target.receiveControlMessage(MESSAGE.CARPLAY_START_SESSION, Uint8Array.of(1));
  await target.receiveControlMessage(MESSAGE.WIFI_CONFIGURATION, Uint8Array.of(2));
  await target.receiveControlMessage(MESSAGE.CARPLAY_START_SESSION, Uint8Array.of(3));
  assert.deepEqual(target.pendingAuthenticatedMessages.map(message => message.messageId), [
    MESSAGE.WIFI_CONFIGURATION, MESSAGE.CARPLAY_START_SESSION
  ]);
  assert.deepEqual(Array.from(target.pendingAuthenticatedMessages[1].body), [3]);

  target.authenticated = true;
  target.receiveControlMessage = async (messageId, body) => { handled.push([messageId, Array.from(body)]); };
  await target.replayAuthenticatedMessages();
  assert.deepEqual(handled, [[MESSAGE.WIFI_CONFIGURATION, [2]], [MESSAGE.CARPLAY_START_SESSION, [3]]]);
  assert.equal(target.pendingAuthenticatedMessages.length, 0);
  assert.ok(logs.some(message => message.includes('将在认证后处理')));
});
