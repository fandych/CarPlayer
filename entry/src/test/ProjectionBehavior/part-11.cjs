const { assert, fs, path, vm, test, ts, sourceRoot, audioSenderFixture, loadEts, loadMethods,
  loadProjectionSettingsController, videoSenderFixture } = require('../ProjectionBehaviorSupport.cjs');

test('diagnostic archive batches packet log writes and flushes before export', () => {
  const contents = new Map();
  const descriptors = new Map();
  const writes = [];
  let nextFd = 1;
  let fsyncCount = 0;
  const fileFs = {
    OpenMode: { WRITE_ONLY: 1, CREATE: 2, APPEND: 4 },
    accessSync: () => true,
    mkdirSync() {},
    openSync(filename) {
      const fd = nextFd++;
      descriptors.set(fd, filename);
      if (!contents.has(filename)) contents.set(filename, '');
      return { fd };
    },
    listFileSync(directory) {
      return Array.from(contents.keys())
        .filter(filename => filename.startsWith(directory))
        .map(filename => filename.slice(filename.lastIndexOf('/') + 1));
    },
    writeSync(fd, text) {
      writes.push(text);
      const filename = descriptors.get(fd);
      contents.set(filename, `${contents.get(filename) || ''}${text}`);
      return text.length;
    },
    fsyncSync() { fsyncCount++; },
    closeSync() {},
    unlinkSync(filename) { contents.delete(filename); },
    readTextSync(filename) { return contents.get(filename) || ''; }
  };
  const { DiagnosticLogArchive } = loadEts('session/DiagnosticLogArchive.ets', {
    '@ohos.file.fs': fileFs,
    '@kit.PerformanceAnalysisKit': { hilog: { error() {}, warn() {} } },
    './ConnectionLogBuffer': { MAX_CONNECTION_LOG_LINES: 300 },
    './LogTimestamp': {
      formatLocalClock: () => '[12:00:00.000]',
      formatLocalDateKey: () => '2026-11-01'
    },
    './ProtocolLogger': { redactProtocolText: text => text }
  });
  const archive = new DiagnosticLogArchive();
  const logDirectory = 'C:\\logs/CarPlayerLogs';
  const previousRuns = [
    `${logDirectory}/CarPlayer-2026-10-31.log`,
    `${logDirectory}/CarPlayer-2026-11-01.log`
  ];
  for (const filename of previousRuns) {
    contents.set(filename, 'previous run');
  }
  archive.start('C:\\logs');
  for (const filename of previousRuns) {
    assert.equal(contents.has(filename), false, 'startup must delete every previous run log');
  }
  const currentLog = `${logDirectory}/CarPlayer-current.log`;
  assert.equal(contents.has(currentLog), true);
  archive.append('packet one');
  archive.append('packet two');
  archive.append('RAW RX RFCOMM iAP2 bytes=3\n0000: aa bb cc\n    frame end');
  assert.equal(writes.length, 0);
  archive.flush();
  assert.equal(writes.length, 1);
  assert.equal(fsyncCount, 1);
  archive.appendFromAbility('C:\\logs', 'projection', 'current ability event');
  assert.ok(contents.get(currentLog).includes('current ability event'));
  assert.ok(contents.get(currentLog).includes('packet one'));
  const exported = archive.readAllText();
  assert.ok(exported.indexOf('packet one') < exported.indexOf('packet two'));
  assert.match(exported, /RAW RX RFCOMM iAP2 bytes=3\n    0000: aa bb cc\n    frame end/);
  assert.ok(exported.includes('current ability event'));
  assert.doesNotMatch(exported, /previous run/);
  const recent = archive.readRecentLines().join('\n');
  assert.ok(recent.includes('current app session'));
  assert.ok(recent.includes('current ability event'));
  const recentRawStart = recent.indexOf('RAW RX RFCOMM');
  const recentRawBlock = recent.slice(recentRawStart);
  assert.ok(recentRawBlock.indexOf('RAW RX RFCOMM') < recentRawBlock.indexOf('0000: aa bb cc'));
  assert.ok(recentRawBlock.indexOf('0000: aa bb cc') < recentRawBlock.indexOf('frame end'));
  archive.start('C:\\logs');
  const restarted = archive.readAllText();
  assert.ok(restarted.includes('current app session'));
  assert.doesNotMatch(restarted, /packet one|current ability event/);
  archive.clear();
});

test('protocol logs are archived immediately and batched before updating the UI', () => {
  const archived = [];
  let scheduled;
  const Target = loadMethods('pages/Index.ets', 'Index', ['addLog', 'flushPendingUiLogLines'], {
    diagnosticLogArchive: { append: line => archived.push(line) },
    MAX_CONNECTION_LOG_LINES: 300,
    setTimeout(callback) { scheduled = callback; return 7; },
    clearTimeout() {}
  });
  const target = new Target();
  target.logs = [];
  target.pendingUiLogLines = [];
  target.uiLogFlushTimer = -1;
  target.addLog('TX SETUP');
  target.addLog('meaning: starts encrypted session');
  assert.deepEqual(archived, ['TX SETUP', 'meaning: starts encrypted session']);
  assert.deepEqual(target.logs, []);
  assert.equal(typeof scheduled, 'function');
  scheduled();
  assert.deepEqual(Array.from(target.logs), ['meaning: starts encrypted session', 'TX SETUP']);
});

test('audio packet diagnostics are batched and media payloads remain unlogged; video diagnostics cover each frame', async () => {
  const formatEvent = (event, ...fields) => {
    const values = [];
    for (let index = 0; index + 1 < fields.length; index += 2) values.push(`${fields[index]}=${fields[index + 1]}`);
    return `【${event}】 ${values.join('；')}`;
  };
  const concatBytes = (...parts) => {
    const result = new Uint8Array(parts.reduce((length, part) => length + part.length, 0));
    let offset = 0;
    for (const part of parts) { result.set(part, offset); offset += part.length; }
    return result;
  };

  const AudioTarget = loadMethods('audio/AudioRtpSender.ets', 'AudioRtpSender',
    ['sendPacket', 'reportAudioProgress'], {
    buildAudioRtpHeader: () => new Uint8Array(12),
    nonce64: () => new Uint8Array(12),
    advanceAudioRtpTimestamp: (timestamp, packets) => (timestamp + packets * 352) >>> 0,
    getSocketAddressFamily: address => address.includes(':') ? 2 : 1,
    concatBytes,
    toArrayBuffer: bytes => bytes.slice().buffer,
    formatProtocolEvent: formatEvent
  });
  const audio = new AudioTarget();
  const audioLogs = [];
  audio.socket = { async send() {} };
  audio.session = { host: '192.168.3.150', dataPort: 7001 };
  audio.cipher = { async seal(_nonce, pcm) { return new Uint8Array(pcm.length + 16); } };
  audio.running = true;
  audio.sequence = 4;
  audio.timestamp = 100;
  audio.nonceCounter = 0;
  audio.firstPacket = true;
  audio.packetsSent = 0;
  audio.pendingLogPackets = 0;
  audio.pendingLogPcmBytes = 0;
  audio.pendingLogFirstSequence = 0;
  audio.pendingLogLastSequence = 0;
  audio.pendingLogFirstTimestamp = 0;
  audio.pendingLogLastTimestamp = 0;
  audio.droppedPackets = 0;
  audio.reportedDroppedPackets = 0;
  audio.log = line => audioLogs.push(line);
  for (let index = 0; index < 4; index++) await audio.sendPacket(new Uint8Array([0xaa, 0xbb]));
  assert.equal(audioLogs.length, 0);
  audio.reportAudioProgress();
  assert.equal(audioLogs.length, 1);
  assert.ok(audioLogs[0].includes('airplay.audio.rtp.summary'));
  assert.ok(audioLogs[0].includes('packets=4'));
  assert.ok(audioLogs[0].includes('firstSequence=4'));
  assert.ok(audioLogs[0].includes('lastSequence=7'));
  assert.ok(audioLogs[0].includes('firstTimestamp=100'));
  assert.ok(audioLogs[0].includes('lastTimestamp=1156'));
  assert.ok(audioLogs.every(line => !line.includes('aa bb')));

  const VideoTarget = loadMethods('airplay/AirPlayVideoStream.ets', 'AirPlayVideoStreamSender', ['sendFrame'], {
    AirPlayVideoEncryptionMode: { CHACHA20_POLY1305: 0, AES_128_CTR: 1 },
    concatBytes,
    packH264Nals: units => concatBytes(...units),
    buildAirPlayVideoFrameHeader: () => new Uint8Array(128),
    buildVideoFrameNonce: () => new Uint8Array(12),
    containsH264Idr: units => units.some(unit => (unit[0] & 0x1f) === 5),
    patchH264SpsLevel: unit => unit,
    CHACHA_TAG_SIZE: 16,
    formatProtocolEvent: formatEvent
  });
  const video = new VideoTarget();
  const videoLogs = [];
  video.encryption = 0;
  video.cipher = { async seal(_nonce, data) { return new Uint8Array(data.length + 16); } };
  video.sendBytes = async () => {};
  video.log = line => videoLogs.push(line);
  video.framesSent = 0;
  video.frameCounter = 0n;
  video.width = 1280;
  video.height = 720;
  for (let index = 0; index < 4; index++) await video.sendFrame([new Uint8Array([0x65, 0x80])]);
  assert.equal(videoLogs.length, 8);
  assert.deepEqual(videoLogs.filter(line => line.includes('airplay.video.frame.tx'))
    .map(line => Number(line.match(/frame=(\d+)/)?.[1])), [1, 2, 3, 4]);
  assert.ok(videoLogs[0].includes('keyFrame=true'));
  assert.ok(videoLogs[1].includes('载荷未写入日志'));
});

test('AirPlay audio RTP and sync UDP destinations declare IPv4 and IPv6 families', async () => {
  const destinations = [];
  const concatBytes = (...parts) => {
    const result = new Uint8Array(parts.reduce((length, part) => length + part.length, 0));
    let offset = 0;
    for (const part of parts) { result.set(part, offset); offset += part.length; }
    return result;
  };
  const Target = loadMethods('audio/AudioRtpSender.ets', 'AudioRtpSender', ['sendPacket', 'sendSync'], {
    buildAudioRtpHeader: () => new Uint8Array(12),
    buildAudioRtpSyncPacket: () => new Uint8Array(32),
    nonce64: () => new Uint8Array(12),
    advanceAudioRtpTimestamp: (timestamp, packets) => (timestamp + packets * 352) >>> 0,
    getSocketAddressFamily: address => address.includes(':') ? 2 : 1,
    concatBytes,
    toArrayBuffer: bytes => bytes.slice().buffer,
    formatProtocolEvent: () => ''
  });

  for (const [host, family] of [['192.168.3.150', 1], ['fe80::1%wlan0', 2]]) {
    const sender = new Target();
    sender.socket = {
      async send(options) { destinations.push(options.address); }
    };
    sender.session = { host, dataPort: 7001, controlPort: 7002 };
    sender.cipher = { async seal(_nonce, pcm) { return new Uint8Array(pcm.length + 16); } };
    sender.running = true;
    sender.sequence = 0;
    sender.timestamp = 0;
    sender.nonceCounter = 0;
    sender.firstPacket = true;
    sender.syncSequence = 0;
    sender.firstSync = true;
    sender.syncPending = false;
    sender.log = () => {};

    await sender.sendPacket(new Uint8Array([0, 0]));
    await sender.sendSync();
    assert.deepEqual(destinations.splice(0).map(address =>
      [address.address, address.family, address.port]), [
      [host, family, 7001],
      [host, family, 7002]
    ]);
  }
});
