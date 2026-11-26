const { assert, fs, path, vm, test, ts, sourceRoot, audioSenderFixture, loadEts, loadMethods,
  loadProjectionSettingsController, videoSenderFixture } = require('../ProjectionBehaviorSupport.cjs');

test('iAP2 retries 0x5702 after device greetings before falling back to 0x4300', async () => {
  const timers = [];
  let timerId = 0;
  const Target = loadMethods('session/Iap2SenderSession.ets', 'Iap2SenderSession',
    ['startWifiConfigurationTimer'], {
      MESSAGE: { WIFI_REQUEST: 0x5702 },
      setTimeout: (callback, delayMs) => {
        timers.push({ callback, delayMs });
        return ++timerId;
      },
      clearTimeout: () => {}
    });
  const target = new Target();
  const actions = [];
  target.started = true;
  target.authenticated = true;
  target.deviceAnnouncementSent = false;
  target.wifiConfigurationRescueGeneration = 0;
  target.wifiConfigurationDeadline = Date.now() + 60000;
  target.log = () => {};
  target.errorDetails = error => error.message;
  target.sendDeviceStateGreetings = async force => { actions.push(`greetings:${force}`); };
  target.sendControl = async messageId => { actions.push(messageId); };
  target.sendDeviceAnnouncement = async () => { actions.push('announce'); };
  target.startWifiConfigurationTimer('0x5703', true);
  assert.equal(timers[0].delayMs, 1500);

  const runNextTimer = async () => {
    timers.shift().callback();
    for (let turn = 0; turn < 5; turn++) await Promise.resolve();
  };
  await runNextTimer();
  assert.deepEqual(actions, ['greetings:true']);
  assert.equal(timers[0].delayMs, 1300);
  await runNextTimer();
  assert.deepEqual(actions, ['greetings:true', 0x5702]);
  assert.ok(timers[0].delayMs > 50000 && timers[0].delayMs <= 60000);
  await runNextTimer();
  assert.deepEqual(actions, ['greetings:true', 0x5702, 'announce']);
});

test('Buick B233 identity selects strict MFi and encodes two availability groups', async () => {
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
    const result = [];
    for (let offset = 0; offset < bytes.length;) {
      const length = (bytes[offset] << 8) | bytes[offset + 1];
      assert.ok(length >= 4 && offset + length <= bytes.length);
      result.push({ id: (bytes[offset + 2] << 8) | bytes[offset + 3], value: bytes.slice(offset + 4, offset + length) });
      offset += length;
    }
    return result;
  };
  const encodeUtf8 = text => new TextEncoder().encode(text);
  const decodeString = bytes => new TextDecoder().decode(bytes).replace(/\0.*$/s, '');
  const codec = {
    concatBytes,
    decodeIap2Parameters: decodeParameters,
    decodeIap2String: decodeString,
    encodeUtf8,
    encodeIap2Control: () => new Uint8Array(0),
    encodeIap2LinkFrame: () => new Uint8Array(0),
    formatIap2LinkPayloadDiagnostic: () => '',
    formatIap2MessageDiagnostic: () => '',
    formatIap2RawFrameDiagnostic: () => '',
    groupedParameter: (id, children) => encodeParameter(id, concatBytes(...children)),
    Iap2ControlDecoder: class {},
    Iap2LinkDecoder: class {},
    numberParameter: (id, number, width) => {
      const value = new Uint8Array(width);
      for (let index = width - 1; index >= 0; index--) {
        value[index] = number & 0xff;
        number = Math.floor(number / 256);
      }
      return encodeParameter(id, value);
    },
    stringParameter: (id, text) => encodeParameter(id, concatBytes(encodeUtf8(text), new Uint8Array([0])))
  };
  const session = loadEts('session/iap2/Iap2SessionProtocol.ets', {
    '../../protocol/Iap2Codec': codec,
    '@ohos.i18n': { System: { getSystemLanguage: () => 'zh-CN' } },
    '../ProtocolLogger': { formatProtocolEvent: () => '' }
  });
  const identity = 'Buick B233 SAIC General Motors';
  assert.equal(session.isBuickB233Identity(identity), true);
  assert.equal(session.isBuickB233Identity('BUICK_7841 E2LB SAIC General Motors'), true);
  assert.equal(session.isBuickB233Identity('Buick E2LB Other Manufacturer'), false);
  assert.equal(session.isBuickB233Identity('Buick SAIC General Motors'), false);
  assert.equal(session.isBuickB233Identity('B233 SAIC General Motors'), false);
  const NewProtocolTarget = loadMethods('session/Iap2SenderSession.ets', 'Iap2SenderSession',
    ['requestWifiConfiguration'], {
      MESSAGE: { CARPLAY_AVAILABILITY: 0x4300, CARPLAY_START_SESSION: 0x4301,
        WIFI_REQUEST: 0x5702, WIFI_CONFIGURATION: 0x5703 },
      shouldProbeLegacyWifi: session.shouldProbeLegacyWifi
    });
  const newProtocolTarget = new NewProtocolTarget();
  newProtocolTarget.accessorySendMessages = Array(10).fill(0x4301);
  newProtocolTarget.accessoryReceiveMessages = Array(10).fill(0x4300);
  newProtocolTarget.log = () => {};
  let newProtocolAnnouncements = 0;
  newProtocolTarget.sendDeviceAnnouncement = async () => { newProtocolAnnouncements++; };
  newProtocolTarget.sendControl = async () => { throw new Error('complete new-protocol lists must skip 0x5702'); };
  await newProtocolTarget.requestWifiConfiguration();
  assert.equal(newProtocolAnnouncements, 1);

  const deviceIdentifier = '0123456789ABCDEF01234567';
  const bluetoothAddress = 'AA:BB:CC:DD:EE:FF';
  const groups = decodeParameters(session.encodeBuickB233AvailabilityBody(deviceIdentifier, bluetoothAddress));
  assert.deepEqual(groups.map(group => group.id), [0, 1]);
  assert.equal(decodeString(decodeParameters(groups[0].value)[1].value), deviceIdentifier);
  assert.equal(decodeString(decodeParameters(groups[1].value)[1].value), bluetoothAddress);
  assert.throws(() => session.encodeBuickB233AvailabilityBody(deviceIdentifier, '02:00:00:00:00:00'));
  assert.throws(() => session.encodeBuickB233AvailabilityBody(deviceIdentifier, '00:00:00:00:00:00'));

  const normalize = value => value.toLowerCase().replace(/\s+/g, ' ').trim();
  const Target = loadMethods('session/Iap2SenderSession.ets', 'Iap2SenderSession',
    ['chooseChallengeLength', 'prioritizeStoredChallengeLength'], {
      isBuickB233Identity: session.isBuickB233Identity,
      normalizeAccessoryIdentity: normalize,
      readAccessoryIdentity: bytes => new TextDecoder().decode(bytes),
      prioritizeStoredChallengeLength: async () => {}
    });
  const target = new Target();
  target.log = () => {};
  await target.chooseChallengeLength(new TextEncoder().encode(identity));
  assert.deepEqual(Array.from(target.challengeLengths), [32]);
  await target.chooseChallengeLength(new TextEncoder().encode('BUICK_7841 E2LB SAIC General Motors'));
  assert.deepEqual(Array.from(target.challengeLengths), [32]);
  await target.chooseChallengeLength(new TextEncoder().encode('Audi MIB3'));
  assert.deepEqual(Array.from(target.challengeLengths), [20, 32, 16]);

  let digestInput;
  const IdentifierTarget = loadMethods('session/Iap2SenderSession.ets', 'Iap2SenderSession',
    ['buickCarPlayDeviceIdentifier'], {
      cryptoFramework: { createMd: algorithm => {
        assert.equal(algorithm, 'SHA256');
        return {
          update: async ({ data }) => { digestInput = new TextDecoder().decode(data); },
          digest: async () => ({ data: Uint8Array.from({ length: 32 }, (_, index) => index) })
        };
      } },
      encodeUtf8
    });
  const identifierTarget = new IdentifierTarget();
  identifierTarget.deviceAddress = bluetoothAddress.toLowerCase();
  assert.equal(await identifierTarget.buickCarPlayDeviceIdentifier(), '000102030405060708090A0B');
  assert.equal(digestInput, 'CarDeck-CarPlay:AA:BB:CC:DD:EE:FF');
});

test('MFi challenge memory prioritizes and persists a successful length by hashed receiver identity', async () => {
  const stored = new Map();
  const writes = [];
  let flushed = 0;
  const store = {
    get: async (key, fallback) => stored.get(key) ?? fallback,
    put: async (key, value) => { stored.set(key, value); writes.push([key, value]); },
    flush: async () => { flushed++; }
  };
  const Target = loadMethods('session/Iap2SenderSession.ets', 'Iap2SenderSession',
    ['prioritizeStoredChallengeLength', 'persistSuccessfulChallengeLength'], {
      cryptoFramework: { createMd: () => ({
        update: async () => {},
        digest: async () => ({ data: Uint8Array.from({ length: 32 }, (_, index) => index) })
      }) },
      encodeUtf8: text => new TextEncoder().encode(text),
      preferences: { getPreferences: async (_context, name) => {
        assert.equal(name, 'carplayer_mfi_challenge_memory');
        return store;
      } }
    });
  const target = new Target();
  target.context = {};
  target.accessoryIdentity = 'receiver model manufacturer';
  target.challengeLengths = [20, 32, 16];
  target.challengeLength = 20;
  target.buickB233Receiver = false;
  target.log = () => {};
  target.errorDetails = error => error.message;
  stored.set('receiver_000102030405060708090a0b', 32);
  await target.prioritizeStoredChallengeLength();
  assert.deepEqual(Array.from(target.challengeLengths), [32, 20, 16]);
  assert.equal(target.challengeLength, 32);
  await target.persistSuccessfulChallengeLength(32);
  assert.deepEqual(writes, [['receiver_000102030405060708090a0b', 32]]);
  assert.equal(flushed, 1);
});

test('Buick B233 bypasses the legacy Wi-Fi request even with sparse capabilities', async () => {
  const Target = loadMethods('session/Iap2SenderSession.ets', 'Iap2SenderSession',
    ['requestWifiConfiguration'], { shouldProbeLegacyWifi: () => true });
  const target = new Target();
  target.buickB233Receiver = true;
  target.log = () => {};
  target.errorDetails = error => error.message;
  let announcements = 0;
  let controls = 0;
  target.sendDeviceAnnouncement = async () => { announcements++; };
  target.sendControl = async () => { controls++; };
  await target.requestWifiConfiguration();
  assert.equal(announcements, 1);
  assert.equal(controls, 0);
});
