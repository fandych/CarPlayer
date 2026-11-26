const { assert, fs, path, vm, test, ts, sourceRoot, audioSenderFixture, loadEts, loadMethods,
  loadProjectionSettingsController, videoSenderFixture } = require('../ProjectionBehaviorSupport.cjs');

test('Buick B233 re-identification is one-shot and buffers an early 0x4301', async () => {
  const Target = loadMethods('session/Iap2SenderSession.ets', 'Iap2SenderSession',
    ['receiveControlMessage'], {
      MESSAGE: { IDENTIFICATION_INFORMATION: 0x1d01, IDENTIFICATION_ACCEPTED: 0x1d02,
        MFI_CERTIFICATE_REQUEST: 0xaa00, CARPLAY_START_SESSION: 0x4301 },
      formatIap2MessageDiagnostic: () => '',
      isBuickB233Identity: value => value.includes('buick') && value.includes('b233') &&
        value.includes('saic general motors'),
      normalizeAccessoryIdentity: value => value.toLowerCase().replace(/\s+/g, ' ').trim(),
      readAccessoryIdentity: bytes => new TextDecoder().decode(bytes),
      readEaProtocols: () => []
    });
  const target = new Target();
  target.log = () => {};
  target.chooseChallengeLength = () => {};
  target.logMfiMessageCapabilities = () => {};
  target.clearMfiChallenge = () => {};
  target.clearMfiCertificateTimer = () => {};
  target.clearBuickStartSessionTimer = () => {};
  target.startMfiCertificateTimer = () => {};
  const sent = [];
  target.sendControl = async messageId => { sent.push(messageId); };
  target.accessoryIdentity = 'buick b233 saic general motors';
  target.buickB233Receiver = true;
  target.buickAvailabilitySent = true;
  target.authenticated = true;

  await target.receiveControlMessage(0x1d01, new TextEncoder().encode(target.accessoryIdentity));
  assert.equal(target.authenticated, true);
  assert.deepEqual(sent, []);
  target.buickWaitingForStartSession = true;
  target.buickReidentificationWindowOpen = false;
  await target.receiveControlMessage(0x1d01, new TextEncoder().encode(target.accessoryIdentity));
  assert.equal(target.authenticated, true);
  assert.deepEqual(sent, []);
  target.buickReidentificationWindowOpen = true;
  await target.receiveControlMessage(0x1d01, new TextEncoder().encode('Audi MIB3'));
  assert.equal(target.authenticated, true);
  assert.deepEqual(sent, []);
  await target.receiveControlMessage(0x1d01, new TextEncoder().encode(target.accessoryIdentity));
  assert.equal(target.buickReauthenticationInProgress, true);
  assert.equal(target.buickReidentificationUsed, true);
  assert.deepEqual(sent, [0x1d02, 0xaa00]);
  await target.receiveControlMessage(0x1d01, new TextEncoder().encode(target.accessoryIdentity));
  assert.deepEqual(sent, [0x1d02, 0xaa00]);
  await target.receiveControlMessage(0x4301, new Uint8Array([1, 2, 3]));
  assert.deepEqual(Array.from(target.pendingBuickStartSession), [1, 2, 3]);
});

test('Buick B233 echoes only the first DETECT marker while waiting for 0x4301', async () => {
  const marker = new Uint8Array([0xff, 0x55, 0x02, 0x00, 0xee, 0x10]);
  const Target = loadMethods('session/Iap2SenderSession.ets', 'Iap2SenderSession',
    ['receiveDetectionMarker'], { LINK_MARKER: marker, formatRawBytesDiagnostic: () => '' });
  const target = new Target();
  const sent = [];
  const logs = [];
  target.log = message => logs.push(message);
  target.sendBytes = async bytes => { sent.push(Array.from(bytes)); };
  target.buickB233Receiver = true;
  target.buickWaitingForStartSession = true;
  target.buickMarkerEchoSent = false;
  target.started = true;
  target.identificationRequested = true;

  await target.receiveDetectionMarker();
  await target.receiveDetectionMarker();
  assert.deepEqual(sent, [Array.from(marker)]);
  assert.equal(target.started, true);
  assert.equal(target.identificationRequested, true);
  assert.equal(target.buickMarkerEchoSent, true);
  assert.ok(logs.some(message => message.includes('忽略重复 DETECT marker')));
});

test('Buick B233 T21 reports a redacted 0x4300 fingerprint and keeps a silent link alive', async () => {
  const timers = [];
  const Target = loadMethods('session/Iap2SenderSession.ets', 'Iap2SenderSession',
    ['startBuickStartSessionWaitTimer', 'clearBuickStartSessionTimer'], {
      setTimeout: (callback, delayMs) => { timers.push({ callback, delayMs }); return timers.length; },
      clearTimeout: () => {}
    });
  const target = new Target();
  const logs = [];
  target.log = message => logs.push(message);
  target.controlAckSnapshot = () => 'link=up outstanding=7 queued=0 window=1 rxSeq=6';
  target.started = true;
  target.sessionGeneration = 4;
  target.buickWaitingForStartSession = true;
  target.buickReidentificationWindowOpen = true;
  target.buickAvailabilitySentAt = Date.now() - 30000;
  target.buickAvailabilityFrameDigest = 'a1b2c3d4e5f60708';
  target.buickMarkerEchoSent = true;

  target.startBuickStartSessionWaitTimer(4);
  assert.equal(timers[0].delayMs, 30000);
  timers[0].callback();
  assert.ok(logs.some(message => message.includes('T21') && message.includes('outstanding=7')));
  assert.ok(logs.some(message => message.includes('frameSHA256prefix=a1b2c3d4e5f60708')));
  assert.equal(target.started, true);
  assert.equal(target.buickWaitingForStartSession, true);
  assert.equal(target.buickReidentificationWindowOpen, false);
});

test('Buick B233 T21 digest failures do not block availability sending', async () => {
  const Target = loadMethods('session/Iap2SenderSession.ets', 'Iap2SenderSession',
    ['controlFrameDigest'], {
      cryptoFramework: { createMd: () => { throw new Error('digest unavailable'); } },
      encodeIap2Control: () => new Uint8Array([0x40, 0x40])
    });
  const target = new Target();
  const logs = [];
  target.log = message => logs.push(message);
  target.errorDetails = error => error.message;
  assert.equal(await target.controlFrameDigest(0x4300, new Uint8Array([1])), 'unavailable');
  assert.ok(logs.some(message => message.includes('不影响发送')));
});

test('Buick B233 announcements use separate initial and recovery message orders', async () => {
  const Target = loadMethods('session/Iap2SenderSession.ets', 'Iap2SenderSession',
    ['sendDeviceAnnouncement', 'sendDeviceStateGreetings'], {
      MESSAGE: { WIRELESS_UPDATE: 0x4e0d, DEVICE_LANGUAGE_UPDATE: 0x4e0a,
        DEVICE_INFORMATION_UPDATE: 0x4e09, DEVICE_TIME_UPDATE: 0x4e0b,
        DEVICE_UUID_UPDATE: 0x4e0c, CARPLAY_AVAILABILITY: 0x4300 },
      concatBytes: (...parts) => Uint8Array.from(parts.flatMap(part => Array.from(part))),
      currentDeviceLanguage: () => 'zh-CN',
      encodeBuickB233AvailabilityBody: () => new Uint8Array([0x43, 0x00]),
      numberParameter: () => new Uint8Array([1]),
      stringParameter: () => new Uint8Array([2]),
      setTimeout: callback => { callback(); return 1; }
    });
  const target = new Target();
  target.started = true;
  target.authenticated = true;
  target.sessionGeneration = 1;
  target.deviceName = 'iPhone';
  target.deviceUuid = 'test-device';
  target.deviceAddress = 'AA:BB:CC:DD:EE:FF';
  target.parameter = (_id, value) => value;
  const logs = [];
  target.log = message => logs.push(message);
  target.waitForControlQueueDrain = async () => true;
  target.controlFrameDigest = async () => '0123456789abcdef';
  target.controlAckSnapshot = () => 'outstanding=none queued=0';
  target.startBuickStartSessionWaitTimer = () => {};
  target.startStartSessionWaitTimer = () => {};
  target.clearBuickStartSessionTimer = () => {};
  target.buickCarPlayDeviceIdentifier = async () => 'A'.repeat(24);
  const sent = [];
  target.sendControl = async messageId => { sent.push(messageId); };
  target.buickB233Receiver = true;

  await target.sendDeviceAnnouncement();
  assert.deepEqual(sent, [0x4e0a, 0x4e09, 0x4e0b, 0x4e0c, 0x4300]);
  assert.equal(target.buickWaitingForStartSession, true);
  assert.equal(target.buickReidentificationWindowOpen, true);
  assert.ok(logs.some(message => message.includes('frameSHA256prefix=0123456789abcdef')));
  sent.length = 0;
  target.deviceAnnouncementSent = false;
  target.deviceStateGreetingsSent = false;
  target.buickReidentificationUsed = true;
  await target.sendDeviceAnnouncement();
  assert.deepEqual(sent, [0x4e0c, 0x4e0a, 0x4e0b, 0x4e09, 0x4300]);
  sent.length = 0;
  target.deviceAnnouncementSent = false;
  target.deviceStateGreetingsSent = false;
  target.buickB233Receiver = false;
  target.buickReidentificationUsed = false;
  await target.sendDeviceAnnouncement();
  assert.deepEqual(sent, [0x4e0d, 0x4e0a, 0x4e09, 0x4e0b, 0x4e0c, 0x4300]);
});

test('wireless startup never publishes an unknown identity as a pairing public key', () => {
  const { makeAirPlayServiceFromEndpoint } = loadEts('session/airplay/AirPlayEndpointFactory.ets', {},
    'makeAirPlayServiceFromEndpoint');
  const endpoint = { addresses: ['192.168.49.1'], port: 7000, deviceIdentifier: 'AA:BB:CC:DD:EE:FF',
    publicKey: '', unrecognizedIdentity: '24e3089a-b9c8-4998-beb2-ae9120b44053', sourceVersion: '450.14' };
  assert.equal(Object.hasOwn(makeAirPlayServiceFromEndpoint(endpoint).txt, 'pk'), false);
  endpoint.publicKey = 'a'.repeat(64);
  assert.equal(makeAirPlayServiceFromEndpoint(endpoint).txt.pk, 'a'.repeat(64));
});

test('wireless startup pairs from a complete iAP2 endpoint without an advertised key and rejects conflicts', () => {
  const { makeAirPlayServiceFromEndpoint } = loadEts('session/airplay/AirPlayEndpointFactory.ets', {},
    'makeAirPlayServiceFromEndpoint');
  const { normalizeDeviceIdentifier } = loadEts('session/airplay/AirPlayEndpointFactory.ets', {},
    'normalizeDeviceIdentifier');
  const { correlateAirPlayIdentity } = loadEts('network/AirPlayIdentityCorrelation.ets');
  const Target = loadMethods('session/SessionController.ets', 'SessionController',
    ['refreshDiscoveredAirPlay', 'makeAirPlayGatewayFallback'], { makeAirPlayServiceFromEndpoint, normalizeDeviceIdentifier,
      correlateAirPlayIdentity });
  const target = new Target();
  target.wifiNetworkLease = {};
  target.events = { onLog() {} };
  target.iap2AirPlayEndpoint = { addresses: ['fe80::1'], port: 7000,
    deviceIdentifier: 'AA:BB:CC:DD:EE:FF', publicKey: '', sourceVersion: '450.14' };
  target.refreshDiscoveredAirPlay();
  assert.equal(target.discoveredAirPlay.host, 'fe80::1');
  assert.equal(target.discoveredAirPlay.port, 7000);
  assert.equal(Object.hasOwn(target.discoveredAirPlay.txt, 'pk'), false);
  target.mdnsAirPlayService = { host: '192.168.49.1', port: 7000, name: 'receiver',
    txt: { deviceid: 'AA:BB:CC:DD:EE:FF' } };
  target.refreshDiscoveredAirPlay();
  assert.equal(target.discoveredAirPlay.host, '192.168.49.1');
  assert.equal(Object.hasOwn(target.discoveredAirPlay.txt, 'pk'), false);
  target.mdnsAirPlayService.txt.pk = 'a'.repeat(64);
  target.refreshDiscoveredAirPlay();
  assert.equal(target.discoveredAirPlay.txt.pk, 'a'.repeat(64));
  target.mdnsAirPlayService.txt.deviceid = '11:22:33:44:55:66';
  target.refreshDiscoveredAirPlay();
  assert.equal(target.discoveredAirPlay.host, 'fe80::1');
  assert.equal(Object.hasOwn(target.discoveredAirPlay.txt, 'pk'), false);
  target.iap2AirPlayEndpoint.publicKey = 'b'.repeat(64);
  target.mdnsAirPlayService.txt.deviceid = 'AA:BB:CC:DD:EE:FF';
  let rejected = false;
  target.rejectAirPlayIdentityConflict = () => { rejected = true; };
  target.refreshDiscoveredAirPlay();
  assert.equal(rejected, true);
});
