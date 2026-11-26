const { assert, fs, path, vm, test, ts, sourceRoot, audioSenderFixture, loadEts, loadMethods,
  loadProjectionSettingsController, videoSenderFixture } = require('../ProjectionBehaviorSupport.cjs');

test('audio authorization is awaited and a cancelled start cannot reactivate capture', async () => {
  let authorize;
  let released = 0;
  let options;
  const startOrder = [];
  const capturer = {
    on() {}, off() {},
    setIndependentAudioSessionStrategy(strategy, behavior) {
      assert.equal(strategy.concurrencyMode, 1);
      assert.equal(behavior, 0);
      startOrder.push('mix-strategy');
    },
    requestPlaybackCaptureStart(callback) { startOrder.push('capture-request'); authorize = callback; },
    async stop() {}, async release() { released++; }
  };
  const api = {
    AudioSamplingRate: { SAMPLE_RATE_44100: 44100, SAMPLE_RATE_48000: 48000 },
    AudioChannel: { CHANNEL_2: 2 }, AudioSampleFormat: { SAMPLE_FORMAT_S16LE: 1 },
    AudioEncodingType: { ENCODING_TYPE_RAW: 0 }, SourceType: { SOURCE_TYPE_PLAYBACK_CAPTURE: 2 },
    AudioPlaybackCaptureMode: { MODE_DEFAULT: 0 },
    AudioConcurrencyMode: { CONCURRENCY_MIX_WITH_OTHERS: 1 },
    AudioSessionBehaviorFlags: { DEFAULT_BEHAVIOR: 0 },
    PlaybackCaptureStartState: { STATE_SUCCESS: 0, STATE_FAILED: 1, STATE_NOT_AUTHORIZED: 2 },
    async createAudioCapturer(value) { options = value; return capturer; }
  };
  const { PlaybackAudioCapture } = loadEts('audio/PlaybackAudioCapture.ets', {
    '@ohos.multimedia.audio': api,
    './CarAudioOutput': {
      CarAudioOutput: class { async start() {} async stop() {} },
      scalePlaybackPcm: data => data
    }
  });
  const capture = new PlaybackAudioCapture(() => {}, () => {});
  let completed = false;
  const started = capture.requestStart().then(() => { completed = true; });
  await Promise.resolve();
  assert.equal(completed, false);
  assert.equal(options.playbackCaptureMode, 0);
  assert.deepEqual(startOrder, ['mix-strategy', 'capture-request']);
  authorize(0);
  await started;
  assert.equal(capture.started, true);
  await capture.stop();
  const pending = capture.requestStart();
  const rejected = assert.rejects(pending, /\u53d6\u6d88/u);
  await Promise.resolve();
  await capture.stop();
  authorize(0);
  await rejected;
  assert.equal(capture.started, false);
  assert.equal(released, 2);
});

test('Bluetooth audio skips capture and RTP while default and disabled settings retain CarPlay audio', async () => {
  for (const setting of [undefined, false, true, 'true']) {
    const calls = [];
    const logs = [];
    const Target = loadMethods('session/SessionController.ets', 'SessionController', ['startAudio'], {
      AppStorage: { get: key => {
        assert.equal(key, 'carplayUseBluetoothAudio');
        return setting;
      } },
      AudioRtpSender: class {
        constructor() { calls.push('sender'); }
        async start() { calls.push('start sender'); }
      },
      PlaybackAudioCapture: class {
        constructor() { calls.push('capture'); }
        async requestStart() { calls.push('start capture'); }
      }
    });
    const target = new Target();
    target.running = true;
    target.airPlayGeneration = 2;
    target.events = { onLog: message => logs.push(message) };
    const media = { audioSession: { sampleRate: 48000 } };
    await target.startAudio(media, 1);
    assert.deepEqual(calls, []);
    assert.deepEqual(logs, []);
    await target.startAudio(media, 2);
    if (setting === true) {
      assert.deepEqual(calls, []);
      assert.equal(target.audioRtpSender, undefined);
      assert.equal(target.playbackAudioCapture, undefined);
      assert.ok(logs.some(message => message.includes('A2DP')));
    } else {
      assert.deepEqual(calls, ['sender', 'start sender', 'capture', 'start capture']);
      assert.ok(logs.some(message => message.includes('CarPlay RTP')));
    }
  }
});

test('a failed old audio start cannot stop the replacement session', { timeout: 5000 }, async () => {
  let rejectOldStart;
  let signalStart;
  const startRequested = new Promise(resolve => { signalStart = resolve; });
  let oldSender;
  let oldCapture;
  class Sender {
    constructor() { oldSender = this; this.stopped = false; }
    async start() {}
    async stop() { this.stopped = true; }
  }
  class Capture {
    constructor() { oldCapture = this; this.stopped = false; }
    requestStart() {
      return new Promise((_resolve, reject) => { rejectOldStart = reject; signalStart(); });
    }
    async stop() { this.stopped = true; }
  }
  const Target = loadMethods('session/SessionController.ets', 'SessionController', ['startAudio'], {
    AudioRtpSender: Sender, PlaybackAudioCapture: Capture,
    AppStorage: { get: () => false }
  });
  const target = new Target();
  target.running = true;
  target.airPlayGeneration = 1;
  target.events = { onLog() {} };
  const pending = target.startAudio({ audioSession: {} }, 1);
  await startRequested;
  const replacement = { stopped: false, async stop() { this.stopped = true; } };
  target.airPlayGeneration = 2;
  target.audioRtpSender = replacement;
  target.playbackAudioCapture = replacement;
  rejectOldStart(new Error('old authorization cancelled'));
  await pending;
  assert.equal(oldSender.stopped, true);
  assert.equal(oldCapture.stopped, true);
  assert.equal(replacement.stopped, false);
  assert.equal(target.audioRtpSender, replacement);
  assert.equal(target.playbackAudioCapture, replacement);
});

test('PCM packetization preserves split samples and RTP time across capture callbacks', async () => {
  const { sender, session, sent, encrypted } = audioSenderFixture();
  await sender.start(session);
  try {
    const pcm = Uint8Array.from({ length: 1408 * 3 + 9 }, (_value, offset) => offset & 255);
    sender.pushPcm(pcm.subarray(0, 703));
    sender.pushPcm(pcm.subarray(703));
    await sender.sendQueue;
    assert.equal(sent.length, 3);
    assert.equal(sender.pendingPcm.length, 9);
    for (let packet = 0; packet < 3; packet++) {
      const header = new DataView(sent[packet].data);
      assert.equal(header.getUint16(2), packet);
      assert.equal(header.getUint32(4), packet * 352);
      assert.equal(encrypted[packet].aad.length, 8);
      assert.equal(encrypted[packet].data[0], pcm[packet * 1408 + 1]);
      assert.equal(encrypted[packet].data[1], pcm[packet * 1408]);
      assert.equal(encrypted[packet].nonce[4], packet);
    }
    assert.deepEqual(sender.pendingPcm, pcm.slice(1408 * 3));
  } finally {
    await sender.stop();
  }
});

test('media encryption uses the original direct path without transferring buffers or scheduling tasks', async () => {
  const calls = [];
  const sealed = new Uint8Array([9, 8, 7]);
  const { MediaPacketCipher } = loadEts('crypto/MediaPacketCipher.ets', {
    '@ohos.taskpool': {},
    '@noble/ciphers/chacha.js': {},
    './AirPlayStreamCrypto': { async chachaSeal(...args) { calls.push(args); return sealed; } }
  });
  const key = new Uint8Array(32);
  const plaintext = new Uint8Array(1408);
  const cipher = new MediaPacketCipher(key);
  assert.equal(await cipher.seal(new Uint8Array(12), plaintext, new Uint8Array(8)), sealed);
  assert.equal(calls.length, 1);
  assert.equal(calls[0][2], plaintext);
  assert.notEqual(calls[0][0].buffer, key.buffer);
  assert.equal(key.byteLength, 32);
  assert.equal(plaintext.byteLength, 1408);
});

test('background media encryption stays on TaskPool and surfaces worker failures', async () => {
  const calls = [];
  let executions = 0;
  let failed = false;
  const tasks = [];
  const worker = {
    Priority: { MEDIUM: 1 },
    Task: class {
      constructor(operation, ...args) { this.operation = operation; this.args = args; }
      setTransferList(buffers) { this.transfers = buffers; }
    },
    async execute(task) {
      executions++;
      tasks.push(task);
      if (failed) { throw new Error('simulated worker failure'); }
      return task.operation(...task.args);
    }
  };
  const { MediaPacketCipher } = loadEts('crypto/MediaPacketCipher.ets', {
    '@ohos.taskpool': worker,
    '@noble/ciphers/chacha.js': { chacha20poly1305: () => ({ encrypt: bytes => new Uint8Array(bytes.length + 16) }) },
    './AirPlayStreamCrypto': { async chachaSeal(...args) {
      calls.push(args); return new Uint8Array(args[2].length + 16);
    } }
  });
  const key = new Uint8Array(32);
  const nonce = new Uint8Array(12);
  const data = new Uint8Array(4096);
  const aad = new Uint8Array(128);
  const cipher = new MediaPacketCipher(key, true);
  assert.equal((await cipher.seal(nonce, data, aad)).length, 4112);
  assert.deepEqual(tasks[0].transfers, []);
  failed = true;
  await assert.rejects(() => cipher.seal(nonce, data, aad), /background media encryption failed/);
  assert.equal(executions, 2);
  assert.equal(calls.length, 0);
  assert.equal(key.byteLength, 32);
  assert.equal(data.byteLength, 4096);
  assert.equal(aad.byteLength, 128);
});

test('Audio RTP keeps small per-packet ChaCha encryption off TaskPool', () => {
  const source = fs.readFileSync(path.join(sourceRoot, 'audio/AudioRtpSender.ets'), 'utf8');
  assert.match(source, /new MediaPacketCipher\(session\.streamKey,\s*false,\s*this\.log\)/);
});
