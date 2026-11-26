const { assert, fs, path, vm, test, ts, sourceRoot, audioSenderFixture, loadEts, loadMethods,
  loadProjectionSettingsController, videoSenderFixture } = require('../ProjectionBehaviorSupport.cjs');

test('AirPlay 403 retries back off longer than ordinary connection failures', () => {
  class StubAirPlayRtspStatusError extends Error {
    constructor(statusCode) {
      super(`HTTP ${statusCode}`);
      this.statusCode = statusCode;
    }
  }
  const delays = [];
  const Target = loadMethods('session/SessionController.ets', 'SessionController',
    ['airPlayRetryDelayMs', 'scheduleAirPlayReconnect'], {
      AIRPLAY_FORBIDDEN_RETRY_DELAY_MS: 5000,
      AIRPLAY_RECONNECT_DELAY_MS: 2000,
      AIRPLAY_PAIRING_WINDOW_MS: 120000,
      AirPlayRtspStatusError: StubAirPlayRtspStatusError,
      Error,
      setTimeout: (_callback, delayMs) => { delays.push(delayMs); return delays.length; }
    });
  const target = new Target();
  target.running = true;
  target.hasAirPlayStartSignal = () => true;
  target.discoveredAirPlay = {};
  target.airPlayReconnectTimer = -1;
  target.airPlayPairingDeadline = Date.now() + 60000;
  target.airPlayReconnectAttempts = 0;
  target.events = { onLog() {} };

  target.scheduleAirPlayReconnect('Pair-Verify HTTP 403',
    target.airPlayRetryDelayMs(new StubAirPlayRtspStatusError(403)));
  target.airPlayReconnectTimer = -1;
  target.scheduleAirPlayReconnect('TCP connection failed', target.airPlayRetryDelayMs(new Error('connection')));
  assert.deepEqual(delays, [5000, 2000]);
});

test('AirPlay waits 4 seconds for ctrl invite and 3 seconds for endpoint resolution', () => {
  const timers = [];
  let timerId = 0;
  const Target = loadMethods('session/SessionController.ets', 'SessionController',
    ['startAirPlayPrerequisiteWait', 'startAirPlayEndpointResolutionWait'], {
      AIRPLAY_CTRL_INVITE_WAIT_MS: 4000,
      AIRPLAY_ENDPOINT_RESOLVE_WAIT_MS: 3000,
      setTimeout: (callback, delayMs) => {
        timers.push({ callback, delayMs });
        return ++timerId;
      },
      clearTimeout: () => {}
    });
  const target = new Target();
  let connections = 0;
  target.running = true;
  target.vehicleWifiConnected = true;
  target.inviteReceived = false;
  target.airPlayInviteWaitElapsed = false;
  target.airPlayInviteWaitTimer = -1;
  target.airPlayEndpointResolveTimer = -1;
  target.mdnsAirPlayService = undefined;
  target.hasSelfContainedAirPlayEndpoint = () => false;
  target.clearAirPlayWaitTimers = () => {};
  target.refreshDiscoveredAirPlay = () => {};
  target.connectAirPlay = async () => { connections++; };
  target.events = { onLog() {} };

  target.startAirPlayPrerequisiteWait();
  assert.equal(timers[0].delayMs, 4000);
  timers.shift().callback();
  assert.equal(target.airPlayInviteWaitElapsed, true);
  assert.equal(timers[0].delayMs, 3000);
  timers.shift().callback();
  assert.equal(target.airPlayEndpointResolveElapsed, true);
  assert.equal(connections, 1);
});

test('CarPlay control service publishes before the Bluetooth listener starts', async () => {
  const Target = loadMethods('session/SessionController.ets', 'SessionController', ['start'], {
    advanceSessionGeneration: () => 1,
    isCurrentSessionGeneration: () => true,
    CarPlayBackgroundTask: class {
      constructor() {}
      async start() { actions.push('background-task'); }
      async stop() {}
    }
  });
  const target = new Target();
  const actions = [];
  target.context = {};
  target.requestPermissions = async () => {};
  target.detectAdapterMode = () => false;
  target.hasValidDeviceAddress = () => true;
  target.startControlAdvertisement = async () => { actions.push('ctrl-advertisement'); };
  target.bluetooth = {
    async start() { actions.push('bluetooth-listener'); },
    stop() {}
  };
  target.setKeepScreenOn = async () => {};
  target.clearAirPlayWaitTimers = () => {};
  target.clearPendingStartSessionTimer = () => {};
  target.clearWifiReconnectTimer = () => {};
  target.scheduleBluetoothOutboundAttempt = () => {};
  target.events = { onStatus() {}, onLog() {} };

  await target.start();
  assert.deepEqual(actions, ['background-task', 'ctrl-advertisement', 'bluetooth-listener']);
});

test('CarPlay background task starts for multi-device connection and releases on stop', async () => {
  const callbacks = {};
  const calls = [];
  const context = {};
  const wantAgentValue = { id: 'foreground-entry' };
  const { CarPlayBackgroundTask } = loadEts('session/CarPlayBackgroundTask.ets', {
    '@ohos.app.ability.common': {},
    '@ohos.resourceschedule.backgroundTaskManager': {
      BackgroundMode: { MULTI_DEVICE_CONNECTION: 6 },
      on(type, callback) { callbacks[type] = callback; calls.push(['on', type]); },
      off(type, callback) {
        assert.equal(callbacks[type], callback);
        delete callbacks[type];
        calls.push(['off', type]);
      },
      async startBackgroundRunning(actualContext, mode, agent) {
        calls.push(['start', actualContext, mode, agent]);
      },
      async stopBackgroundRunning(actualContext) { calls.push(['stop', actualContext]); }
    },
    '@ohos.app.ability.wantAgent': {
      OperationType: { START_ABILITY: 1 },
      WantAgentFlags: { UPDATE_PRESENT_FLAG: 3 },
      async getWantAgent(info) {
        calls.push(['wantAgent', info]);
        return wantAgentValue;
      }
    }
  });
  const task = new CarPlayBackgroundTask(context);
  let cancelReason = '';
  await task.start(reason => { cancelReason = reason; });
  assert.equal(calls.find(call => call[0] === 'start')[2], 6);
  assert.equal(calls.find(call => call[0] === 'start')[3], wantAgentValue);
  assert.equal(calls.find(call => call[0] === 'wantAgent')[1].wants[0].abilityName, 'EntryAbility');
  await task.stop();
  assert.equal(calls.at(-1)[0], 'stop');
  assert.equal(calls.at(-1)[1], context);
  assert.equal(cancelReason, '');
});

test('CarPlay background task cancellation is surfaced to the session owner', async () => {
  let cancel;
  const calls = [];
  const { CarPlayBackgroundTask } = loadEts('session/CarPlayBackgroundTask.ets', {
    '@ohos.app.ability.common': {},
    '@ohos.resourceschedule.backgroundTaskManager': {
      BackgroundMode: { MULTI_DEVICE_CONNECTION: 6 },
      on(_type, callback) { cancel = callback; },
      off() { calls.push('off'); },
      async startBackgroundRunning() { calls.push('start'); },
      async stopBackgroundRunning() { calls.push('stop'); }
    },
    '@ohos.app.ability.wantAgent': {
      OperationType: { START_ABILITY: 1 },
      WantAgentFlags: { UPDATE_PRESENT_FLAG: 3 },
      async getWantAgent() { return {}; }
    }
  });
  const task = new CarPlayBackgroundTask({});
  const reasons = [];
  await task.start(reason => reasons.push(reason));
  cancel({ reason: 7 });
  assert.deepEqual(reasons, ['7']);
  await task.stop();
  assert.deepEqual(calls, ['start', 'off']);
});

test('control advertisement survives the WLAN handoff and ignores invites after stop', async () => {
  let created = 0;
  let published = 0;
  let reannounced = 0;
  let removed = 0;
  let invite;
  const Target = loadMethods('session/SessionController.ets', 'SessionController',
    ['startControlAdvertisement'], {
      CarPlayCtrlAdvertiser: class {
        constructor(_context, _address, onInvite) { created++; invite = onInvite; }
        async start() { if (!this.started) { published++; this.started = true; } }
        async reannounce() { reannounced++; }
        async stop() { removed++; }
      }
    });
  const target = new Target();
  target.running = true;
  target.hasValidDeviceAddress = () => true;
  target.events = { onLog() {}, onStatus() {} };
  target.startAirPlayPrerequisiteWait = () => {};
  target.clearAirPlayInviteWaitTimer = () => {};
  target.startAirPlayEndpointResolutionWait = () => {};
  await target.startControlAdvertisement();
  const advertiser = target.ctrlAdvertiser;
  target.vehicleWifiConnected = true;
  await target.startControlAdvertisement(true);
  assert.equal(target.ctrlAdvertiser, advertiser);
  assert.deepEqual([created, published, reannounced, removed], [1, 1, 1, 0]);
  invite();
  assert.equal(target.inviteReceived, true);
  target.inviteReceived = false;
  target.running = false;
  invite();
  assert.equal(target.inviteReceived, false);
});

test('control advertisement failures clear ownership for retries and retain native error details', async () => {
  const { describeSocketError } = loadEts('network/CarPlayCtrlAdvertiser.ets', {}, 'describeSocketError');
  const error = { code: 2204004, message: 'service already registered' };
  const PublishTarget = loadMethods('network/CarPlayCtrlAdvertiser.ets', 'CarPlayCtrlAdvertiser',
    ['start', 'createServiceInfo'], {
      netSocket: { constructTCPSocketServerInstance: () => ({
        async listen() {}, async getLocalAddress() { return { port: 1234 }; }, on() {}
      }) },
      encodeUtf8: () => new Uint8Array(),
      CARPLAY_CTRL_SOURCE_VERSION: '950.7.1',
      mdns: { async addLocalService() { throw error; } },
      describeSocketError
    });
  const publisher = new PublishTarget();
  publisher.toNumberArray = () => [];
  publisher.stop = async () => {};
  await assert.rejects(publisher.start(), /code=2204004 service already registered/);
  const Target = loadMethods('session/SessionController.ets', 'SessionController',
    ['startControlAdvertisement'], {
      CarPlayCtrlAdvertiser: class {
        async start() { throw new Error('registration failed'); }
      }
    });
  const target = new Target();
  target.running = true;
  target.hasValidDeviceAddress = () => true;
  await assert.rejects(target.startControlAdvertisement(), /registration failed/);
  assert.equal(target.ctrlAdvertiser, undefined);
});
