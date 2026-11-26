const { assert, fs, path, vm, test, ts, sourceRoot, audioSenderFixture, loadEts, loadMethods,
  loadProjectionSettingsController, videoSenderFixture } = require('../ProjectionBehaviorSupport.cjs');

test('iAP2 ignores an early MFi response and requests the missing certificate without bypassing auth', async () => {
  const MESSAGE = {
    MFI_RESPONSE: 0xaa03,
    MFI_CERTIFICATE_REQUEST: 0xaa00
  };
  const Target = loadMethods('session/Iap2SenderSession.ets', 'Iap2SenderSession',
    ['receiveControlMessage'], {
      MESSAGE,
      decodeIap2Parameters: () => [],
      formatIap2MessageDiagnostic: () => ''
    });
  const target = new Target();
  const sent = [];
  let failures = 0;
  target.started = true;
  target.authenticated = false;
  target.mfiOnlyVirtualLink = false;
  target.mfiAuthenticationFailed = false;
  target.mfiCertificateRequestCount = 0;
  target.pendingMfiChallenge = undefined;
  target.validatedAccessoryCertificate = undefined;
  target.log = () => {};
  target.sendControl = async messageId => { sent.push(messageId); };
  target.startMfiCertificateTimer = () => {};
  target.failMfiAuthentication = () => { failures++; };

  await target.receiveControlMessage(MESSAGE.MFI_RESPONSE, new Uint8Array(0));
  assert.deepEqual(sent, [MESSAGE.MFI_CERTIFICATE_REQUEST]);
  assert.equal(target.mfiCertificateRequestCount, 1);
  assert.equal(target.authenticated, false);
  assert.equal(failures, 0);
});

test('iAP2 restarts on a new SYN after progress and adopts a direct mid-session CSM frame', async () => {
  const { Iap2LinkLayer: Target } = loadEts('session/iap2/Iap2LinkLayer.ets', {
    '../../protocol/Iap2Codec': {
      Iap2ControlDecoder: class {},
      Iap2LinkDecoder: class {},
      formatIap2RawFrameDiagnostic: () => ''
    },
    './Iap2SessionProtocol': {
      formatIap2RawFrameDiagnostic: () => '',
      formatIap2FrameInterpretation: () => ''
    }
  });
  const syncTarget = new Target();
  const syncPayload = Uint8Array.of(1, 2, 0, 5, 0, 10, 0, 0, 3, 0);
  let restarts = 0;
  let identificationRequests = 0;
  const syncFrames = [];
  syncTarget.log = () => {};
  syncTarget.started = true;
  syncTarget.identificationRequested = true;
  syncTarget.peerSyncSequence = 42;
  syncTarget.peerSyncPayload = syncPayload.slice();
  syncTarget.lastReceivedSequence = 43;
  syncTarget.peerSyncResponse = undefined;
  syncTarget.detectionRetryTimer = undefined;
  syncTarget.restartSessionForNewPeerSync = async () => {
    restarts++;
    syncTarget.identificationRequested = false;
    syncTarget.lastReceivedSequence = 0;
    syncTarget.peerSyncSequence = undefined;
    syncTarget.peerSyncPayload = undefined;
    syncTarget.peerSyncResponse = undefined;
  };
  syncTarget.readControlSessionId = () => 1;
  syncTarget.applyPeerLinkParameters = () => {};
  syncTarget.takeSequence = () => 99;
  syncTarget.sendLinkFrame = async frame => { syncFrames.push(frame); };
  syncTarget.onIdentificationRequested = async () => { identificationRequests++; };
  await syncTarget.receiveLinkFrame({
    control: 0x80, sequence: 42, acknowledgement: 0, sessionId: 0, payload: syncPayload
  });
  assert.equal(restarts, 1);
  assert.equal(identificationRequests, 1);
  assert.equal(syncTarget.controlSessionId, 1);
  assert.equal(syncFrames[0].control, 0xc0);

  const delayedTarget = new Target();
  const syncResponse = {
    control: 0xc0, sequence: 99, acknowledgement: 42, sessionId: 0, payload: syncPayload
  };
  let delayedStartRequests = 0;
  const repeatedSyncResponses = [];
  delayedTarget.log = () => {};
  delayedTarget.identificationRequested = true;
  delayedTarget.peerSyncSequence = 42;
  delayedTarget.peerSyncPayload = syncPayload.slice();
  delayedTarget.lastReceivedSequence = 42;
  delayedTarget.peerSyncResponse = syncResponse;
  delayedTarget.identificationTimer = 1;
  delayedTarget.sendLinkFrame = async frame => { repeatedSyncResponses.push(frame); };
  delayedTarget.onIdentificationRequested = async () => { delayedStartRequests++; };
  await delayedTarget.receiveLinkFrame({
    control: 0x80, sequence: 42, acknowledgement: 0, sessionId: 0, payload: syncPayload
  });
  assert.deepEqual(repeatedSyncResponses, [syncResponse]);
  assert.equal(delayedStartRequests, 1);

  const dataTarget = new Target();
  const accepted = [];
  dataTarget.log = () => {};
  dataTarget.started = true;
  dataTarget.identificationRequested = false;
  dataTarget.peerSyncSequence = undefined;
  dataTarget.controlSessionId = 10;
  dataTarget.lastReceivedSequence = 0;
  dataTarget.detectionRetryTimer = undefined;
  dataTarget.unacknowledgedFrames = new Map();
  dataTarget.retransmitCounts = new Map();
  dataTarget.outboundQueue = [];
  dataTarget.outOfOrderFrames = new Map();
  dataTarget.nextSequence = 100;
  dataTarget.clearRetransmitTimer = () => {};
  dataTarget.transmitPending = async () => {};
  dataTarget.sendLinkFrame = async () => {};
  dataTarget.acceptDataFrame = async frame => { accepted.push(frame); };
  const firstFrame = {
    control: 0x40, sequence: 201, acknowledgement: 0, sessionId: 3,
    payload: Uint8Array.of(0x40, 0x40, 0, 6, 0x1d, 0x01)
  };
  await dataTarget.receiveLinkFrame(firstFrame);
  assert.equal(dataTarget.controlSessionId, 3);
  assert.equal(dataTarget.identificationRequested, true);
  assert.equal(dataTarget.lastReceivedSequence, 201);
  assert.deepEqual(accepted, [firstFrame]);
});

test('iAP2 receiver profile matches CardDeck Wi-Fi and MIB3 capability rules', () => {
  const { shouldProbeLegacyWifi, isClassicMib3Profile } = loadEts('session/iap2/Iap2SessionProtocol.ets', {
    '../../protocol/Iap2Codec': {},
    '@ohos.i18n': {},
    '../ProtocolLogger': {}
  });
  assert.equal(shouldProbeLegacyWifi([0x4301], [0x4300]), true);
  assert.equal(shouldProbeLegacyWifi([], []), true);
  assert.equal(shouldProbeLegacyWifi(Array(5).fill(0x4301), Array(5).fill(0x4300)), false);
  assert.equal(shouldProbeLegacyWifi(Array(10).fill(0x4301), undefined), false);
  assert.equal(shouldProbeLegacyWifi(Array(10).fill(0x4301), [0x5702, ...Array(9).fill(0x4300)]), true);
  assert.equal(isClassicMib3Profile('Delphi Audi', [0x4301], [0x4300, 0x4e00]), true);
  assert.equal(isClassicMib3Profile('Delphi Audi', Array(5).fill(0x4301), Array(5).fill(0x4300)), false);
  assert.equal(isClassicMib3Profile('Delphi Audi', [0x4301], undefined), false);
  assert.equal(isClassicMib3Profile('Delphi Buick', [0x4301], [0x4300]), false);
});

test('Bluetooth adapter mode advertises Wireless iAP and holds post-handoff redials', async () => {
  const acceptCallbacks = [];
  const closedClients = [];
  let serviceName = '';
  const bluetoothSocket = {
    SppType: { SPP_RFCOMM: 1 },
    sppListen(name, _options, callback) {
      serviceName = name;
      callback(undefined, 17);
    },
    sppAccept(_serverId, callback) { acceptCallbacks.push(callback); },
    on() {},
    off() {},
    sppCloseClientSocket(clientId) { closedClients.push(clientId); },
    sppCloseServerSocket() {},
    async sppWriteAsync() {}
  };
  const { BluetoothIap2Server, isCarPlayAdapterName } = loadEts('transport/BluetoothIap2Server.ets', {
    '@ohos.bluetooth.socket': bluetoothSocket,
    '../protocol/Iap2Codec': { toArrayBuffer: () => new ArrayBuffer(0) },
    './BluetoothIap2Helpers': loadEts('transport/BluetoothIap2Helpers.ets')
  });
  assert.equal(isCarPlayAdapterName('Carlinkit CPC200'), true);
  assert.equal(isCarPlayAdapterName('Audi MMI'), false);

  const server = new BluetoothIap2Server();
  let connections = 0;
  await server.start(() => { connections++; }, () => {}, () => {}, true);
  assert.equal(serviceName, 'Wireless iAP');
  acceptCallbacks.shift()(undefined, 1);
  assert.equal(connections, 1);
  server.setAdapterHandoffCompleted(true);
  acceptCallbacks.shift()(undefined, 2);
  assert.equal(connections, 1);
  assert.deepEqual(closedClients, []);
  server.setAdapterHandoffCompleted(false);
  assert.deepEqual(closedClients, [2]);
  acceptCallbacks.shift()(undefined, 3);
  assert.equal(connections, 2);
  assert.ok(closedClients.includes(1));
  server.stop();
  assert.ok(closedClients.includes(3));
});

test('Bluetooth accept retries back off and deduplicate unchanged adapter errors', () => {
  const callbacks = [];
  const timers = [];
  const failures = [];
  let timerId = 0;
  const Target = loadMethods('transport/BluetoothIap2Server.ets', 'BluetoothIap2Server',
    ['acceptNext', 'scheduleAcceptRetry', 'reportAcceptFailure'], {
      bluetoothSocket: {
        sppAccept(_serverId, callback) { callbacks.push(callback); }
      },
      setTimeout: (callback, delayMs) => {
        timers.push({ callback, delayMs });
        return ++timerId;
      }
    });
  const server = new Target();
    server.acceptRetry = new (loadEts('transport/BluetoothIap2AcceptRetry.ets').BluetoothIap2AcceptRetry)(
    (callback, delayMs) => {
      timers.push({ callback, delayMs });
      return ++timerId;
    },
    () => {}
    );
  server.serverId = 17;
  server.onFailure = message => failures.push(message);

  server.acceptNext();
  callbacks.shift()({ code: 2900099, message: 'Bluetooth disabled' });
  assert.equal(failures.length, 1);
  const firstRetry = timers.shift();
  assert.equal(firstRetry.delayMs, 500);
  firstRetry.callback();
  callbacks.shift()({ code: 2900099, message: 'Bluetooth disabled' });
  assert.equal(failures.length, 1);
  const secondRetry = timers.shift();
  assert.equal(secondRetry.delayMs, 1000);
  secondRetry.callback();
  callbacks.shift()({ code: 2900099, message: 'Bluetooth disabled' });
  assert.equal(failures.length, 1);
  assert.equal(timers.shift().delayMs, 2000);
});
