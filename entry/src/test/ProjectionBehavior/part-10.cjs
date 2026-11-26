const { assert, fs, path, vm, test, ts, sourceRoot, audioSenderFixture, loadEts, loadMethods,
  loadProjectionSettingsController, videoSenderFixture } = require('../ProjectionBehaviorSupport.cjs');

test('AirPlay ctrl reannouncement respects the active generation and pairing deadline', async () => {
  const previousSetTimeout = global.setTimeout;
  const previousClearTimeout = global.clearTimeout;
  const previousDateNow = Date.now;
  let now = 1000;
  let scheduled;
  const cleared = [];
  let reannounceCount = 0;
  global.setTimeout = (callback, delay) => {
    scheduled = { callback, delay };
    return 17;
  };
  global.clearTimeout = timer => cleared.push(timer);
  Date.now = () => now;
  try {
    const Target = loadMethods('session/SessionController.ets', 'SessionController', [
      'scheduleAirPlayControlReannounce', 'reannounceAirPlayControl', 'clearAirPlayCtrlReannounceTimer'
    ], {
      AIRPLAY_CTRL_REANNOUNCE_INTERVAL_MS: 10000,
      Date: { now: () => now },
      setTimeout: global.setTimeout,
      clearTimeout: global.clearTimeout
    });
    const target = new Target();
    target.running = true;
    target.vehicleWifiConnected = true;
    target.airPlayGeneration = 2;
    target.airPlayPairingDeadline = 5500;
    target.airPlayCtrlReannounceTimer = 12;
    target.ctrlAdvertiser = { async reannounce() { reannounceCount++; } };
    target.events = { onLog() {} };

    target.clearAirPlayCtrlReannounceTimer();
    target.scheduleAirPlayControlReannounce(2);
    assert.deepEqual(cleared, [12]);
    assert.equal(scheduled.delay, 4500);
    target.airPlayGeneration = 3;
    await scheduled.callback();
    assert.equal(reannounceCount, 0);
    assert.equal(target.airPlayCtrlReannounceTimer, -1);

    target.airPlayGeneration = 3;
    target.airPlayPairingDeadline = now;
    target.scheduleAirPlayControlReannounce(3);
    assert.equal(target.airPlayCtrlReannounceTimer, -1);
  } finally {
    global.setTimeout = previousSetTimeout;
    global.clearTimeout = previousClearTimeout;
    Date.now = previousDateNow;
  }
});

test('Bluetooth outbound RFCOMM connects to the wireless accessory service and attaches its client', async () => {
  const events = [];
  const timer = 23;
  const Target = loadMethods('transport/BluetoothIap2Server.ets', 'BluetoothIap2Server', [
    'connectToDevice', 'attachClient', 'closeActiveClient', 'closeSocket', 'errorMessage'
  ], {
    bluetoothSocket: {
      SppType: { SPP_RFCOMM: 1 },
      sppConnect(deviceId, options, callback) {
        events.push(['connect', deviceId, options]);
        callback(undefined, 9);
      },
      on(event, clientId, handler) { events.push(['on', event, clientId, typeof handler]); },
      off(event, clientId) { events.push(['off', event, clientId]); },
      sppCloseClientSocket(clientId) { events.push(['close', clientId]); },
      isConnected: () => true
    },
    setInterval: () => timer,
    clearInterval: id => events.push(['clearInterval', id])
  });
  const target = new Target();
  target.acceptRetry = new (loadEts('transport/BluetoothIap2AcceptRetry.ets').BluetoothIap2AcceptRetry)();
  target.serverId = 4;
  target.clientId = -1;
  target.connectPending = false;
  target.connectionGeneration = 0;
  target.connectionMonitorTimer = -1;
  target.onClientData = () => {};
  target.onClientConnected = () => events.push(['connected']);
  target.onClientDisconnected = () => events.push(['disconnected']);
  target.onFailure = message => events.push(['failure', message]);

  assert.equal(await target.connectToDevice('AA:BB:CC:DD:EE:FF'), true);
  assert.equal(target.clientId, 9);
  assert.equal(events[0][0], 'connect');
  assert.equal(events[0][1], 'AA:BB:CC:DD:EE:FF');
  assert.equal(events[0][2].uuid, '00000000-deca-fade-deca-deafdecacaff');
  assert.equal(events[0][2].secure, true);
  assert.equal(events[0][2].type, 1);
  assert.ok(events.some(event => event[0] === 'connected'));
  target.closeActiveClient(false);
  assert.ok(events.some(event => event[0] === 'close' && event[1] === 9));
});

test('Bluetooth outbound RFCOMM failures are retry diagnostics, not listener failures', async () => {
  const listenerFailures = [];
  const attemptFailures = [];
  const Target = loadMethods('transport/BluetoothIap2Server.ets', 'BluetoothIap2Server', [
    'connectToDevice', 'reportAcceptFailure'
  ], {
    bluetoothSocket: {
      SppType: { SPP_RFCOMM: 1 },
      sppConnect(_deviceId, _options, callback) {
        callback({ code: 2900099, message: 'Operation failed' });
      }
    }
  });
  const target = new Target();
  target.acceptRetry = new (loadEts('transport/BluetoothIap2AcceptRetry.ets').BluetoothIap2AcceptRetry)();
  target.serverId = 4;
  target.clientId = -1;
  target.connectPending = false;
  target.connectionGeneration = 0;
  target.onFailure = message => listenerFailures.push(message);

  assert.equal(await target.connectToDevice('06:C7:C7:7F:FE:24', message => attemptFailures.push(message)), false);
  assert.deepEqual(listenerFailures, []);
  assert.match(attemptFailures[0], /2900099.*Operation failed/);
});

test('an accepted inbound RFCOMM client invalidates a pending outbound attempt', async () => {
  const events = [];
  const acceptCallbacks = [];
  let outboundCallback;
  const Target = loadMethods('transport/BluetoothIap2Server.ets', 'BluetoothIap2Server', [
    'connectToDevice', 'acceptNext', 'attachClient', 'closeActiveClient', 'closeSocket',
    'reportAcceptFailure', 'scheduleAcceptRetry', 'errorMessage'
  ], {
    bluetoothSocket: {
      SppType: { SPP_RFCOMM: 1 },
      sppConnect(_deviceId, _options, callback) { outboundCallback = callback; },
      sppAccept(_serverId, callback) { acceptCallbacks.push(callback); },
      on(event, clientId) { events.push(['on', event, clientId]); },
      off(event, clientId) { events.push(['off', event, clientId]); },
      sppCloseClientSocket(clientId) { events.push(['close', clientId]); }
    },
    setInterval: () => 31,
    clearInterval: id => events.push(['clearInterval', id])
  });
  const target = new Target();
  target.acceptRetry = new (loadEts('transport/BluetoothIap2AcceptRetry.ets').BluetoothIap2AcceptRetry)();
  target.serverId = 4;
  target.clientId = -1;
  target.connectPending = false;
  target.connectionGeneration = 0;
  target.connectionMonitorTimer = -1;
  target.adapterMode = false;
  target.adapterHandoffCompleted = false;
  target.acceptRetryDelayMs = 500;
  target.heldClientIds = [];
  target.onClientData = () => {};
  target.onClientConnected = () => events.push(['connected']);
  target.onClientDisconnected = () => events.push(['disconnected']);
  target.onFailure = message => events.push(['listenerFailure', message]);

  const outboundResult = target.connectToDevice('06:C7:C7:7F:FE:24');
  target.acceptNext();
  acceptCallbacks[0](undefined, 20);
  assert.equal(target.clientId, 20);
  outboundCallback(undefined, 21);
  assert.equal(await outboundResult, false);
  assert.equal(target.clientId, 20);
  assert.ok(events.some(event => event[0] === 'close' && event[1] === 21));
  assert.equal(events.filter(event => event[0] === 'connected').length, 1);
  assert.ok(!events.some(event => event[0] === 'listenerFailure'));
});
