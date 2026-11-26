const { assert, fs, path, vm, test, ts, sourceRoot, audioSenderFixture, loadEts, loadMethods,
  loadProjectionSettingsController, videoSenderFixture } = require('../ProjectionBehaviorSupport.cjs');

test('et=NONE video uses stateful AES-CTR without an AEAD tag', async () => {
  const fixture = videoSenderFixture();
  const iv = new Uint8Array(16).fill(3);
  const key = new Uint8Array(16).fill(7);
  const legacySender = new fixture.VideoSender(key, 1280, 720,
    async data => { fixture.sent.push(data); }, () => {}, () => {},
    fixture.VideoEncryptionMode.AES_128_CTR, iv);
  await legacySender.initialize();
  await legacySender.handleEncoderEvent(fixture.event('codecConfig', fixture.sps));
  await legacySender.handleEncoderEvent(fixture.event('codecConfig', fixture.pps));
  await legacySender.handleEncoderEvent(fixture.event('frame', fixture.frame, 0x02));
  const framePacket = fixture.sent[fixture.sent.length - 1];
  assert.equal(new DataView(framePacket.buffer, framePacket.byteOffset, 4).getUint32(0, true), 6);
  assert.equal(framePacket.length, 128 + 6);
  assert.deepEqual(fixture.legacyCryptoCalls[0].params, {
    algName: 'IvParamsSpec',
    iv: { data: iv }
  });
  assert.equal(fixture.legacyCryptoCalls.filter(call => call.update).length, 1);
  await legacySender.finish();
  assert.equal(fixture.legacyCryptoCalls.filter(call => Object.hasOwn(call, 'doFinal')).length, 1);
});

test('video configuration stays plaintext, retains the SPS compatibility path and gates configs on key frames', async () => {
  const fixture = videoSenderFixture();
  const { sender, sent, encrypted, event, frame, sps, configure } = fixture;
  await configure();
  assert.equal(sent.length, 1);
  assert.equal(sent[0][4], 1);
  assert.equal(sent[0][6], 0);
  assert.equal(sent[0][131], 0x28);
  assert.equal(encrypted.length, 0);
  await sender.handleEncoderEvent(event('frame', frame));
  assert.equal(sent.length, 1);
  await sender.handleEncoderEvent(event('frame', frame, 2));
  assert.equal(encrypted.length, 1);
  assert.equal(encrypted[0].nonce[4], 0);
  assert.deepEqual(encrypted[0].aad, sent[1].slice(0, 128));
  const changed = sps.slice();
  changed[3] = 0x28;
  await sender.handleEncoderEvent(event('codecConfig', changed));
  assert.equal(sent.length, 3);
  assert.equal(sent[2][4], 1);
  assert.equal(fixture.keyFrameRequests(), 1);
  await sender.handleEncoderEvent(event('frame', frame));
  assert.equal(encrypted.length, 1);
  await sender.handleEncoderEvent(event('frame', frame, 2));
  assert.equal(encrypted[1].nonce[4], 1);
  await sender.handleEncoderEvent(event('codecConfig', changed));
  assert.equal(sent.length, 4);
});

test('an actual IDR without a sync flag starts video and recovers after queue drops', async () => {
  const fixture = videoSenderFixture();
  await fixture.configure();
  const idr = new Uint8Array([0x65, 0x80]);
  await fixture.sender.handleEncoderEvent(fixture.event('frame', idr));
  assert.equal(fixture.encrypted.length, 1);
  fixture.sender.eventQueue.beginFrameRecovery('test recovery');
  await fixture.sender.handleEncoderEvent(fixture.event('frame', fixture.frame));
  assert.equal(fixture.encrypted.length, 1);
  await fixture.sender.handleEncoderEvent(fixture.event('frame', idr));
  assert.equal(fixture.encrypted.length, 2);
  assert.equal(fixture.sender.eventQueue.awaitingKeyFrame, false);
  assert.equal(fixture.encrypted[1].nonce[4], 1);
});

test('a codec-data buffer containing SPS, PPS and the first IDR emits config then video', async () => {
  const combined = new Uint8Array([0xff]);
  const idr = new Uint8Array([0x65, 0x80]);
  const fixture = videoSenderFixture(undefined, data =>
    data === combined ? [fixture.sps, fixture.pps, idr] : [data]);
  await fixture.sender.handleEncoderEvent(fixture.event('codecConfig', combined, 1));
  assert.equal(fixture.sent.length, 2);
  assert.equal(fixture.sent[0][4], 1);
  assert.equal(fixture.sent[1][4], 0);
  assert.equal(fixture.encrypted.length, 1);
  assert.equal(fixture.encrypted[0].nonce[4], 0);
});

test('a failed TCP frame poisons queued and future video sends without reusing its nonce', async () => {
  const fixture = videoSenderFixture(async bytes => {
    if (bytes[4] === 0) { throw new Error('simulated TCP failure'); }
  });
  await fixture.configure();
  const first = fixture.sender.handleEncoderEvent(fixture.event('frame', fixture.frame, 2));
  const second = fixture.sender.handleEncoderEvent(fixture.event('frame', fixture.frame));
  const results = await Promise.allSettled([first, second]);
  assert.deepEqual(results.map(result => result.status), ['rejected', 'rejected']);
  await assert.rejects(fixture.sender.handleEncoderEvent(fixture.event('frame', fixture.frame, 2)),
    /new session/);
  assert.equal(fixture.encrypted.length, 1);
  assert.equal(fixture.sender.frameCounter, 1n);
  await fixture.sender.flush();
});

test('video byte budget drops queued reference frames and resumes only with a fresh key frame', async () => {
  let release;
  let signal;
  const gate = new Promise(resolve => { release = resolve; });
  const entered = new Promise(resolve => { signal = resolve; });
  const fixture = videoSenderFixture(async bytes => {
    if (bytes[4] === 0) { signal(); await gate; }
  });
  await fixture.configure();
  const large = new Uint8Array(1200 * 1024);
  large[0] = 0x65;
  const first = fixture.sender.handleEncoderEvent(fixture.event('frame', large, 2));
  await entered;
  await fixture.sender.handleEncoderEvent(fixture.event('frame', large));
  assert.equal(fixture.sender.eventQueue.awaitingKeyFrame, true);
  assert.equal(fixture.encrypted.length, 1);
  release();
  await first;
  await fixture.sender.flush();
  assert.equal(fixture.sender.eventQueue.queuedBytes, 0);
  await fixture.sender.handleEncoderEvent(fixture.event('frame', fixture.frame));
  assert.equal(fixture.encrypted.length, 1);
  await fixture.sender.handleEncoderEvent(fixture.event('frame', fixture.frame, 2));
  assert.equal(fixture.encrypted.length, 2);
  assert.equal(fixture.encrypted[1].nonce[4], 1);
});

test('video queue age drops stale frames before encryption and requests recovery', async () => {
  const realNow = Date.now;
  let now = realNow();
  let release;
  let signal;
  const gate = new Promise(resolve => { release = resolve; });
  const entered = new Promise(resolve => { signal = resolve; });
  const fixture = videoSenderFixture(async bytes => {
    if (bytes[4] === 0) { signal(); await gate; }
  });
  try {
    Date.now = () => now;
    await fixture.configure();
    const first = fixture.sender.handleEncoderEvent(fixture.event('frame', fixture.frame, 2));
    await entered;
    const stale = fixture.sender.handleEncoderEvent(fixture.event('frame', fixture.frame));
    now += 201;
    release();
    await Promise.all([first, stale]);
    assert.equal(fixture.encrypted.length, 1);
    assert.equal(fixture.sender.eventQueue.awaitingKeyFrame, true);
    await fixture.sender.handleEncoderEvent(fixture.event('frame', fixture.frame));
    assert.equal(fixture.encrypted.length, 1);
    await fixture.sender.handleEncoderEvent(fixture.event('frame', fixture.frame, 2));
    assert.equal(fixture.encrypted[1].nonce[4], 1);
  } finally { Date.now = realNow; }
});

test('a large capture callback is not truncated to thirteen audio packets before the send queue can run', async () => {
  const { sender, session, sent } = audioSenderFixture();
  try {
    await sender.start(session);
    sender.pushPcm(new Uint8Array(1408 * 20));
    await sender.sendQueue;
    assert.equal(sent.length, 20);
    assert.equal(sender.droppedPackets, 0);
    assert.equal(sender.timestamp, 352 * 20);
  } finally { await sender.stop(); }
});

test('audio drops stale PCM before encryption, advances sample time and cannot reuse a session sender', async () => {
  const { sender, session, sent, encrypted } = audioSenderFixture();
  const realNow = Date.now;
  let now = realNow();
  try {
    Date.now = () => now;
    await sender.start(session);
    assert.equal(sender.queuePacketLimit, 32);
    sender.pushPcm(new Uint8Array(1408));
    now += 101;
    await sender.sendQueue;
    assert.equal(encrypted.length, 0);
    sender.pushPcm(new Uint8Array(1408));
    await sender.sendQueue;
    assert.equal(encrypted.length, 1);
    const bytes = new Uint8Array(sent[0].data);
    const view = new DataView(bytes.buffer);
    assert.equal(view.getUint16(2), 1);
    assert.equal(view.getUint32(4), 352);
    assert.equal(encrypted[0].nonce[4], 0);
    await sender.stop();
    await assert.rejects(sender.start(session), /cannot be reused/);
  } finally {
    Date.now = realNow;
    await sender.stop();
  }
});

test('Petal Maps and installed music apps use the URI entries observed on the phone', async () => {
  const { resolveProjectionApps } = loadEts('pages/ProjectionAppCatalog.ets');
  const resolved = await resolveProjectionApps(uri =>
    ['petalmaps://', 'sweetmusic://', 'kwapp://'].includes(uri));
  const petal = resolved.find(app => app.appId === 'petal-maps');
  const tangshui = resolved.find(app => app.appId === 'tangshui-music');
  const kuwo = resolved.find(app => app.appId === 'kuwo-music');
  assert.equal(petal.label, '地图');
  assert.equal(petal.launchTarget.uri, 'petalmaps://');
  assert.equal(petal.launchState, 'VERIFIED');
  assert.equal(tangshui.label, '溏心音乐');
  assert.equal(tangshui.launchTarget.uri, 'sweetmusic://');
  assert.equal(tangshui.launchState, 'VERIFIED');
  assert.equal(kuwo.launchTarget.uri, 'kwapp://');
  assert.equal(kuwo.launchState, 'VERIFIED');
});

test('car volume gain preserves signed PCM, silence and source ownership', () => {
  const { scalePlaybackPcm } = loadEts('audio/CarAudioOutput.ets', {}, 'scalePlaybackPcm');
  const pcm = new Uint8Array([0xe8, 0x03, 0x18, 0xfc, 0xff, 0x7f, 0x00, 0x80]);
  const half = scalePlaybackPcm(pcm, 50);
  const view = new DataView(half.buffer);
  assert.equal(view.getInt16(0, true), 500);
  assert.equal(view.getInt16(2, true), -500);
  assert.equal(view.getInt16(4, true), 16384);
  assert.equal(view.getInt16(6, true), -16384);
  assert.deepEqual(scalePlaybackPcm(pcm, 0), new Uint8Array(8));
  assert.equal(scalePlaybackPcm(pcm, 100), pcm);
  assert.equal(new DataView(pcm.buffer).getInt16(0, true), 1000);
});

test('only the final audio route owner releases its listener and no owner writes system mute', async () => {
  const muteCalls = [];
  const subscriptions = [];
  let muted = false;
  const manager = {
    async isMute() { return muted; },
    async mute(type, value) { muted = value; muteCalls.push(value); },
    getVolumeManager() { return { on() { subscriptions.push('on'); }, off() { subscriptions.push('off'); } }; }
  };
  const { CarAudioOutput } = loadEts('audio/CarAudioOutput.ets', {
    '@ohos.multimedia.audio': {
      AudioVolumeType: { MEDIA: 3 }, StreamUsage: { STREAM_USAGE_MEDIA: 1 },
      getAudioManager: () => manager
    }
  });
  const first = new CarAudioOutput();
  const next = new CarAudioOutput();
  await first.start();
  await next.start();
  await first.stop();
  assert.deepEqual(muteCalls, []);
  assert.deepEqual(subscriptions, ['on']);
  await next.stop();
  assert.deepEqual(muteCalls, []);
  assert.deepEqual(subscriptions, ['on', 'off']);
});
