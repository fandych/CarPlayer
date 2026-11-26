const { assert, fs, path, vm, test, ts, sourceRoot, audioSenderFixture, loadEts, loadMethods,
  loadProjectionSettingsController, videoSenderFixture } = require('../ProjectionBehaviorSupport.cjs');

test('AirPlay Pair-Setup verifies the receiver key when it was not advertised in advance', async () => {
  const receiverKey = Uint8Array.from({ length: 32 }, (_, index) => index);
  const types = {
    METHOD: 0,
    STATE: 1,
    SALT: 2,
    PUBLIC_KEY: 3,
    PROOF: 4,
    ENCRYPTED_DATA: 5,
    IDENTIFIER: 6,
    SIGNATURE: 7
  };
  const responses = [
    new Map([[types.SALT, Uint8Array.of(1)], [types.PUBLIC_KEY, Uint8Array.of(2)]]),
    new Map([[types.STATE, Uint8Array.of(4)], [types.PROOF, Uint8Array.of(5)]]),
    new Map([[types.STATE, Uint8Array.of(6)], [types.ENCRYPTED_DATA, Uint8Array.of(7)]]),
    new Map([
      [types.IDENTIFIER, new TextEncoder().encode('buick.receiver')],
      [types.PUBLIC_KEY, receiverKey],
      [types.SIGNATURE, Uint8Array.of(8)]
    ])
  ];
  let responseIndex = 0;
  let verifiedKey;
  const { PairSetupClient } = loadEts('airplay/pairing/PairingProtocol.ets', {
    '../../protocol/Iap2Codec': {
      concatBytes: (...parts) => Uint8Array.from(parts.flatMap(part => [...part])),
      decodeUtf8: bytes => new TextDecoder().decode(bytes),
      encodeUtf8: text => new TextEncoder().encode(text)
    },
    '../../crypto/AirPlayStreamCrypto': {
      chachaOpen: async () => Uint8Array.of(1),
      chachaSeal: async () => Uint8Array.of(1)
    },
    '../AirPlayCrypto': {
      hkdfSha512: async () => new Uint8Array(32),
      signEd25519: async () => new Uint8Array(64),
      verifyEd25519: async key => { verifiedKey = key; return true; },
      generateX25519KeyPair: async () => ({}),
      x25519SharedSecret: async () => new Uint8Array(32)
    },
    '../Srp6aClient': {
      Srp6aSession: {
        start: async () => ({
          publicKeyA: Uint8Array.of(3),
          clientProof: async () => Uint8Array.of(4),
          verifyServerProof: async () => true,
          getSessionKey: () => Uint8Array.of(5)
        })
      }
    },
    '../Tlv8': {
      decodeTlv8: () => responses[responseIndex++],
      encodeTlv8: () => Uint8Array.of(0),
      Tlv8Type: types
    }
  });
  const identity = {
    pairingId: 'controller',
    privateKeyDer: Uint8Array.of(1),
    publicKeyRaw: Uint8Array.of(2)
  };
  const client = { request: async () => ({ statusCode: 200, statusLine: 'RTSP/1.0 200 OK', body: new Uint8Array(0) }) };
  const setup = new PairSetupClient(client, identity, () => {});

  const receiver = await setup.run();
  assert.equal(receiver.receiverId, 'buick.receiver');
  assert.deepEqual(receiver.receiverPublicKey, receiverKey);
  assert.deepEqual(verifiedKey, receiverKey);

  responseIndex = 0;
  await assert.rejects(
    () => setup.run(new Uint8Array(32).fill(0xff)),
    /does not match the advertised AirPlay identity/
  );
});

test('AirPlay Pair-Verify binds to the Pair-Setup key and rejects a different receiver ID', async () => {
  const setupReceiverKey = Uint8Array.from({ length: 32 }, (_, index) => index + 1);
  let pairVerifyKey;
  const Target = loadMethods('airplay/AirPlayPairingHandshake.ets', 'AirPlayPairingHandshake', ['prepare', 'run'], {
    decodeAirPlayHex: () => new Uint8Array(0),
    equalAirPlayBytes: (left, right) => left.length === right.length && left.every((value, index) => value === right[index]),
    AirPlayRtspStatusError: Error,
    PairSetupClient: class {
      constructor() {}
      async run(advertisedKey) {
        assert.equal(advertisedKey, undefined);
        return { receiverId: 'setup-receiver', receiverPublicKey: setupReceiverKey };
      }
    },
    PairVerifyClient: class {
      constructor() {}
      async run(receiverKey) {
        pairVerifyKey = receiverKey;
        return {
          receiverId: 'different-receiver',
          sharedSecret: Uint8Array.of(1),
          phoneReadKey: Uint8Array.of(2),
          phoneWriteKey: Uint8Array.of(3)
        };
      }
    }
  });
  const target = new Target();
  target.lifecycleGeneration = 1;
  target.isCurrent = () => true;
  target.closeResources = async () => {};
  target.identityStore = {
    loadOrCreate: async () => ({ pairingId: 'controller' }),
    loadVerifiedReceiver: async () => undefined,
    saveVerifiedReceiver: async () => {}
  };
  target.connect = async () => {};
  target.requireClient = () => ({ activateEncryption() {} });
  target.log = () => {};

  const service = { host: '10.36.232.90', port: 7000, txt: {} };
  await assert.rejects(
    async () => target.run(await target.prepare({}, service), service),
    /pair-setup and pair-verify receiver identities do not match/
  );
  assert.deepEqual(pairVerifyKey, setupReceiverKey);
});

test('AirPlay Pair-Setup 403 without an advertised key preserves the status for backoff', async () => {
  class StubAirPlayRtspStatusError extends Error {
    constructor() {
      super('HTTP 403 Forbidden');
      this.statusCode = 403;
    }
  }
  const forbidden = new StubAirPlayRtspStatusError();
  const Target = loadMethods('airplay/AirPlayPairingHandshake.ets', 'AirPlayPairingHandshake', ['prepare', 'run'], {
    decodeAirPlayHex: () => new Uint8Array(0),
    equalAirPlayBytes: (left, right) => left.length === right.length && left.every((value, index) => value === right[index]),
    Error,
    AirPlayRtspStatusError: StubAirPlayRtspStatusError,
    PairSetupClient: class {
      constructor() {}
      async run() { throw forbidden; }
    }
  });
  const target = new Target();
  target.lifecycleGeneration = 1;
  target.isCurrent = () => true;
  target.identityStore = {
    loadOrCreate: async () => ({ pairingId: 'controller' }),
    loadVerifiedReceiver: async () => undefined,
    saveVerifiedReceiver: async () => {}
  };
  target.connect = async () => {};
  target.requireClient = () => ({});
  target.log = () => {};

  const service = { host: '10.36.232.90', port: 7000, txt: {} };
  await assert.rejects(
    async () => target.run(await target.prepare({}, service), service),
    error => error === forbidden && error.statusCode === 403
  );
});

test('AirPlay Pair-Setup 403 fast path uses only a previously verified device identity', async () => {
  class StubAirPlayRtspStatusError extends Error {
    constructor() {
      super('HTTP 403 Forbidden');
      this.statusCode = 403;
    }
  }
  const forbidden = new StubAirPlayRtspStatusError();
  const trustedKey = new Uint8Array(32).fill(7);
  const connects = [];
  const verifiedKeys = [];
  const savedIdentities = [];
  const Target = loadMethods('airplay/AirPlayPairingHandshake.ets', 'AirPlayPairingHandshake', ['prepare', 'run'], {
    decodeAirPlayHex: () => new Uint8Array(0),
    equalAirPlayBytes: (left, right) => left.length === right.length && left.every((value, index) => value === right[index]),
    Error,
    AirPlayRtspStatusError: StubAirPlayRtspStatusError,
    PairSetupClient: class {
      constructor() {}
      async run(expectedKey) {
        assert.deepEqual(expectedKey, trustedKey);
        throw forbidden;
      }
    },
    PairVerifyClient: class {
      constructor() {}
      async run(receiverKey) {
        verifiedKeys.push(receiverKey);
        return {
          receiverId: 'trusted-receiver',
          sharedSecret: Uint8Array.of(1),
          phoneReadKey: Uint8Array.of(2),
          phoneWriteKey: Uint8Array.of(3)
        };
      }
    }
  });
  const target = new Target();
  target.lifecycleGeneration = 1;
  target.isCurrent = () => true;
  target.identityStore = {
    loadOrCreate: async () => ({ pairingId: 'controller' }),
    loadVerifiedReceiver: async (_context, deviceId) => {
      assert.equal(deviceId, 'AA:BB:CC:DD:EE:FF');
      return { receiverId: 'trusted-receiver', publicKeyRaw: trustedKey };
    },
    saveVerifiedReceiver: async (...identity) => savedIdentities.push(identity)
  };
  target.connect = async () => { connects.push(true); };
  target.closeResources = async () => {};
  target.requireClient = () => ({ activateEncryption() {} });
  target.log = () => {};

  const service = { host: '10.36.232.90', port: 7000, txt: { deviceid: 'AA:BB:CC:DD:EE:FF' } };
  const outcome = await target.run(await target.prepare({}, service), service);
  assert.equal(outcome.receiverId, 'trusted-receiver');
  assert.equal(connects.length, 2);
  assert.deepEqual(verifiedKeys, [trustedKey]);
  assert.equal(savedIdentities.length, 1);
  assert.equal(savedIdentities[0][1], 'AA:BB:CC:DD:EE:FF');
});

test('AirPlay verified receiver identities are persisted per normalized deviceid', async () => {
  const values = new Map();
  const store = {
    async get(key, fallback) { return values.has(key) ? values.get(key) : fallback; },
    async put(key, value) { values.set(key, value); },
    async flush() {}
  };
  const { AirPlayIdentityStore } = loadEts('airplay/AirPlayIdentityStore.ets', {
    '@ohos.app.ability.common': {},
    '@ohos.security.cryptoFramework': {},
    '@ohos.data.preferences': { getPreferences: async () => store },
    './AirPlayCrypto': {}
  });
  const identities = new AirPlayIdentityStore();
  const publicKeyRaw = new Uint8Array(32).fill(11);
  await identities.saveVerifiedReceiver({}, 'AA:BB:CC:DD:EE:FF', 'receiver-1', publicKeyRaw);
  assert.deepEqual(
    await identities.loadVerifiedReceiver({}, 'aa-bb-cc-dd-ee-ff'),
    { receiverId: 'receiver-1', publicKeyRaw }
  );
  assert.equal(await identities.loadVerifiedReceiver({}, '11:22:33:44:55:66'), undefined);
});
