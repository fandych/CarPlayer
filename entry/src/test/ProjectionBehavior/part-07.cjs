const { assert, fs, path, vm, test, ts, sourceRoot, audioSenderFixture, loadEts, loadMethods,
  loadProjectionSettingsController, videoSenderFixture } = require('../ProjectionBehaviorSupport.cjs');

test('MIB3 virtual iAP2 sends runtime initialization only after strict MFi and answers idle subscriptions', async () => {
  const MESSAGE = {
    MFI_AUTHENTICATION_SUCCEEDED: 0xaa05,
    AUX_STATUS_NOTIFICATION: 0xa100,
    DEVICE_LANGUAGE_UPDATE: 0x4e0a,
    DEVICE_INFORMATION_UPDATE: 0x4e09,
    DEVICE_TIME_UPDATE: 0x4e0b,
    DEVICE_UUID_UPDATE: 0x4e0c,
    MIB3_START_CALL_STATE_UPDATES: 0x4154,
    MIB3_CALL_STATE_UPDATE: 0x4155,
    MIB3_START_COMMUNICATIONS_UPDATES: 0x4157,
    MIB3_COMMUNICATIONS_UPDATE: 0x4158,
    MIB3_START_LIST_UPDATES: 0x4170,
    MIB3_LIST_UPDATE: 0x4171,
    MIB3_START_NOW_PLAYING_UPDATES: 0x5000,
    MIB3_NOW_PLAYING_UPDATE: 0x5001
  };
  const finish = loadMethods('session/Iap2SenderSession.ets', 'Iap2SenderSession',
    ['finishMfiAuthentication'], { MESSAGE });
  const makeTarget = (challengeVerified, sent) => {
    const target = new finish();
    target.started = true;
    target.sessionGeneration = 3;
    target.mfiOnlyVirtualLink = true;
    target.mfiVerifier = { canContinueAfterChallengeVerification: () => true };
    target.log = () => {};
    target.sendControl = async (id, body = new Uint8Array(0)) => { sent.push({ id, body }); };
    target.clearMfiChallenge = () => {};
    target.persistSuccessfulChallengeLength = async () => {};
    target.sendMib3InitializationBurst = async () => { target.initializationSent = true; };
    target.pendingMfiChallenge = new Uint8Array(32);
    return { target, challengeVerified };
  };

  const bypassSent = [];
  const bypass = makeTarget(false, bypassSent);
  await bypass.target.finishMfiAuthentication(bypass.challengeVerified);
  assert.deepEqual(bypassSent.map(item => item.id), [MESSAGE.MFI_AUTHENTICATION_SUCCEEDED]);
  assert.equal(bypass.target.initializationSent, undefined);

  const verifiedSent = [];
  const verified = makeTarget(true, verifiedSent);
  await verified.target.finishMfiAuthentication(verified.challengeVerified);
  assert.deepEqual(verifiedSent.map(item => item.id), [MESSAGE.MFI_AUTHENTICATION_SUCCEEDED]);
  assert.equal(verified.target.initializationSent, true);

  const concatBytes = (...parts) => {
    const result = new Uint8Array(parts.reduce((size, part) => size + part.length, 0));
    let offset = 0;
    for (const part of parts) { result.set(part, offset); offset += part.length; }
    return result;
  };
  const greetings = loadMethods('session/Iap2SenderSession.ets', 'Iap2SenderSession',
    ['sendMib3InitializationBurst'], {
      MESSAGE,
      concatBytes,
      numberParameter: (_id, value, width) => Uint8Array.of(value, width),
      stringParameter: (_id, value) => new TextEncoder().encode(value)
    });
  const target = new greetings();
  target.mib3WirelessSessionUuid = '12345678-1234-4234-9234-1234567890AB';
  target.parameter = (id, value) => Uint8Array.from([
    (value.length + 4) >>> 8, (value.length + 4) & 0xff, id >>> 8, id & 0xff, ...value
  ]);
  const sent = [];
  target.sendControl = async (id, body) => { sent.push({ id, body }); };
  await target.sendMib3InitializationBurst();
  assert.deepEqual(sent.map(item => item.id), [
    MESSAGE.DEVICE_UUID_UPDATE, MESSAGE.AUX_STATUS_NOTIFICATION,
    MESSAGE.DEVICE_LANGUAGE_UPDATE, MESSAGE.DEVICE_TIME_UPDATE, MESSAGE.DEVICE_INFORMATION_UPDATE
  ]);
  assert.equal(new TextDecoder().decode(sent[0].body), target.mib3WirelessSessionUuid);
  assert.deepEqual(Array.from(sent[1].body), [0, 4, 0, 6]);
  assert.equal(new TextDecoder().decode(sent[2].body), 'zh');
  assert.ok(sent[3].body.length > 0);
  assert.equal(new TextDecoder().decode(sent[4].body), 'iPhone');

  const subscriptions = loadMethods('session/Iap2SenderSession.ets', 'Iap2SenderSession',
    ['handleMib3PostAuthenticationMessage'], {
      MESSAGE,
      concatBytes: (...parts) => {
        const result = new Uint8Array(parts.reduce((size, part) => size + part.length, 0));
        let offset = 0;
        for (const part of parts) {
          result.set(part, offset);
          offset += part.length;
        }
        return result;
      },
      MIB3_COMMUNICATIONS_IDLE_BODY: new Uint8Array(94),
      MIB3_NOW_PLAYING_IDLE_BODY: new Uint8Array(79)
    });
  const subscriptionTarget = new subscriptions();
  const responses = [];
  subscriptionTarget.log = () => {};
  subscriptionTarget.parameter = (id, value) => Uint8Array.from([
    (value.length + 4) >>> 8, (value.length + 4) & 0xff, id >>> 8, id & 0xff, ...value
  ]);
  subscriptionTarget.sendControl = async (id, body = new Uint8Array(0)) => { responses.push({ id, body }); };
  for (const [request, response] of [
    [MESSAGE.MIB3_START_CALL_STATE_UPDATES, MESSAGE.MIB3_CALL_STATE_UPDATE],
    [MESSAGE.MIB3_START_COMMUNICATIONS_UPDATES, MESSAGE.MIB3_COMMUNICATIONS_UPDATE],
    [MESSAGE.MIB3_START_LIST_UPDATES, MESSAGE.MIB3_LIST_UPDATE],
    [MESSAGE.MIB3_START_NOW_PLAYING_UPDATES, MESSAGE.MIB3_NOW_PLAYING_UPDATE]
  ]) {
    await subscriptionTarget.handleMib3PostAuthenticationMessage(request);
  }
  assert.deepEqual(responses.map(item => item.id), [
    MESSAGE.MIB3_CALL_STATE_UPDATE, MESSAGE.MIB3_COMMUNICATIONS_UPDATE,
    MESSAGE.MIB3_LIST_UPDATE, MESSAGE.MIB3_NOW_PLAYING_UPDATE
  ]);
  assert.deepEqual(responses.map(item => item.body.length), [5, 94, 22, 79]);
  assert.deepEqual(Array.from(responses[0].body), [0, 5, 0, 2, 0]);
  assert.deepEqual(Array.from(responses[2].body.slice(0, 5)), [0, 5, 0, 0, 0]);

  const receive = loadMethods('session/Iap2SenderSession.ets', 'Iap2SenderSession',
    ['receiveControlMessage'], {
      MESSAGE,
      formatIap2MessageDiagnostic: () => ''
    });
  const gated = new receive();
  gated.mfiOnlyVirtualLink = true;
  gated.authenticated = true;
  gated.mfiVerified = false;
  gated.log = () => {};
  const handled = [];
  gated.handleMib3PostAuthenticationMessage = async id => { handled.push(id); };
  await gated.receiveControlMessage(MESSAGE.MIB3_START_CALL_STATE_UPDATES, new Uint8Array(0));
  assert.deepEqual(handled, []);
  gated.mfiVerified = true;
  await gated.receiveControlMessage(MESSAGE.MIB3_START_CALL_STATE_UPDATES, new Uint8Array(0));
  assert.deepEqual(handled, [MESSAGE.MIB3_START_CALL_STATE_UPDATES]);
});

test('AirPlay feature bit selects pairing only when advertised', () => {
  const { supportsAirPlayPairingAndEncryption } = loadEts('airplay/AirPlayPairingClient.ets', {
    '@ohos.app.ability.common': {},
    '../network/AirPlayMdnsDiscovery': {},
    '../protocol/Iap2Codec': {},
    '../crypto/AirPlayStreamCrypto': {},
    './AirPlayCrypto': {},
    './AirPlayIdentityStore': {},
    './AirPlayPairingHandshake': {},
    './AirPlayPairingHelpers': loadEts('airplay/AirPlayPairingHelpers.ets'),
    './AirPlayMediaSession': {},
    './AirPlayVideoStream': {},
    './AirPlayRtspClient': {},
    './Srp6aClient': {},
    './Tlv8': {},
    '../network/WifiNetworkLease': {},
    './pairing/PairingProtocol': {},
    '../session/ProtocolLogger': { formatProtocolEvent: () => '' }
  });
  assert.equal(supportsAirPlayPairingAndEncryption('0x00000000,0x00000040'), true);
  assert.equal(supportsAirPlayPairingAndEncryption('0x00000040,0x00000000'), false);
  assert.equal(supportsAirPlayPairingAndEncryption('0x00000000,0x00000000'), false);
  assert.equal(supportsAirPlayPairingAndEncryption('invalid'), undefined);
  assert.equal(supportsAirPlayPairingAndEncryption(undefined), undefined);
});

test('AirPlay SRP-6a modular exponentiation runs in TaskPool with byte-array inputs', async () => {
  const tasks = [];
  const taskpool = {
    Priority: { MEDIUM: 1 },
    Task: class {
      constructor(operation, ...args) { this.operation = operation; this.args = args; }
      setTransferList(list) { this.transfers = list; }
    },
    async execute(task, priority) {
      tasks.push({ task, priority });
      return task.operation(...task.args);
    }
  };
  const { Srp6aSession, SRP_GENERATOR, SRP3072_MODULUS, modPow, srpBigIntToBytes,
    srpBytesToBigInt } = loadEts('airplay/Srp6aClient.ets', {
    '@ohos.security.cryptoFramework': {
      createRandom: () => ({ async generateRandom(length) {
        return { data: new Uint8Array(length).fill(2) };
      } })
    },
    '@ohos.taskpool': taskpool,
    '../protocol/Iap2Codec': {
      concatBytes: (...parts) => {
        const output = new Uint8Array(parts.reduce((length, part) => length + part.length, 0));
        let offset = 0;
        for (const part of parts) {
          output.set(part, offset);
          offset += part.length;
        }
        return output;
      }
    },
    './AirPlayCrypto': {
      async sha512() { return new Uint8Array(64).fill(1); }
    }
  });
  const randomBytes = new Uint8Array(32).fill(2);
  const serverPublic = new Uint8Array(384);
  serverPublic[383] = 7;
  const session = await Srp6aSession.start(new Uint8Array([1]), serverPublic);
  const expectedPublic = srpBigIntToBytes(modPow(SRP_GENERATOR, srpBytesToBigInt(randomBytes), SRP3072_MODULUS));
  const expectedPaddedPublic = new Uint8Array(384);
  expectedPaddedPublic.set(expectedPublic, expectedPaddedPublic.length - expectedPublic.length);
  assert.deepEqual(session.publicKeyA, expectedPaddedPublic);
  assert.equal((await session.clientProof()).length, 64);
  assert.equal(tasks.length, 3);
  for (const entry of tasks) {
    assert.equal(entry.priority, 1);
    assert.deepEqual(entry.task.transfers, []);
    assert.ok(entry.task.args.every(argument => argument instanceof Uint8Array));
  }
});
