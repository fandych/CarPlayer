const { assert, fs, path, vm, test, ts, sourceRoot, audioSenderFixture, loadEts, loadMethods,
  loadProjectionSettingsController, videoSenderFixture } = require('../ProjectionBehaviorSupport.cjs');

test('binary plist diagnostics redact credentials and identifiers while explaining ordinary fields', () => {
  const { PlistNode, formatPlistDiagnostic } = loadEts('airplay/BinaryPlist.ets', {
    '@ohos.util': {},
    '../protocol/Iap2Codec': { concatBytes: (...parts) => parts[0], encodeUtf8: text => new TextEncoder().encode(text) }
  });
  const summary = formatPlistDiagnostic(PlistNode.dictionary(new Map([
    ['name', PlistNode.string('Harmony sender')],
    ['timingPort', PlistNode.integer(7000)],
    ['features', PlistNode.array([PlistNode.string('videoPlayback')])],
    ['deviceID', PlistNode.string('AA:BB:CC:DD:EE:FF')],
    ['password', PlistNode.string('do-not-log-this')]
  ])));
  assert.match(summary, /Harmony sender/);
  assert.match(summary, /videoPlayback/);
  assert.match(summary, /"deviceID": \[REDACTED\]/);
  assert.match(summary, /"password": \[REDACTED\]/);
  assert.doesNotMatch(summary, /AA:BB:CC:DD:EE:FF|do-not-log-this/);
});

test('protocol logs are readable plain text and format RAW bytes as offset blocks', () => {
  const rawByteFormatter = loadEts('protocol/RawByteFormatter.ets');
  const { ProtocolLogger, formatProtocolEvent, formatRawBytesDiagnostic } = loadEts(
    'session/ProtocolLogger.ets',
    {
      '@kit.PerformanceAnalysisKit': { hilog: { error() {}, warn() {}, info() {}, debug() {} } },
      '../protocol/RawByteFormatter': rawByteFormatter,
      './LogTimestamp': { formatLocalClock: () => '[12:00:00.000]' }
    }
  );
  const event = formatProtocolEvent('iap2.transport.rx',
    'transport', 'RFCOMM',
    'chunkBytes', 6,
    'challenge', 'private-challenge',
    'challengeBytes', 32
  );
  assert.match(event, /iAP2 接收 RFCOMM 数据/);
  assert.match(event, /数据块长度=6/);
  assert.match(event, /挑战长度=32/);
  assert.match(event, /challenge=\[已脱敏\]/);
  assert.doesNotMatch(event, /^\s*\{/);
  assert.doesNotMatch(event, /private-challenge/);

  const bytes = Uint8Array.from({ length: 20 }, (_, index) => index);
  const mask = new Uint8Array(bytes.length);
  mask[1] = 1;
  const raw = formatRawBytesDiagnostic('RX', 'RFCOMM iAP2', bytes, 20, mask);
  assert.match(raw, /RAW RX RFCOMM iAP2 bytes=20/);
  assert.match(raw, /0000: 00 \*\* 02/);
  assert.match(raw, /0010: 10 11 12/);

  const entries = [];
  const logger = new ProtocolLogger(line => entries.push(line));
  logger.setContext({ sessionId: 'run-1', attempt: 2 });
  logger.write('mdns', 'RAW RX mDNS/DNS bytes=2\n0000: 01 02');
  assert.match(entries[0], /会话 run-1 \/ 尝试 2/);
  assert.match(entries[0], /\n    0000: 01 02/);
  assert.doesNotMatch(entries[0], /^\s*\{/);
});

test('connection logs correlate RFCOMM attempts and promote timeout events to warnings', () => {
  const writes = [];
  class ProtocolLogger {
    setContext(context) { this.context = context; }
    write(stage, message, level) { writes.push({ context: this.context, stage, message, level }); }
  }
  const Target = loadMethods('pages/Index.ets', 'Index',
    ['logProtocol', 'createLogSessionId', 'resolveProtocolLogLevel'], {
      ProtocolLogger,
      formatLocalTimestamp: () => '2026-11-05T12:00:00+08:00'
    });
  const target = new Target();
  target.protocolLogger = new ProtocolLogger();
  target.logSessionId = '20261105120000';
  target.connectionAttempt = 0;

  target.logProtocol('iap2', '已接受 RFCOMM 连接');
  target.logProtocol('mdns', '等待 AirPlay 服务超时');

  assert.equal(writes[0].context.attempt, 1);
  assert.equal(writes[0].context.sessionId, '20261105120000');
  assert.equal(writes[1].context.attempt, 1);
  assert.equal(writes[1].level, 'WARN');
});

test('mDNS RAW monitor binds the vehicle network and releases multicast membership', async () => {
  const rawByteFormatter = loadEts('protocol/RawByteFormatter.ets');
  const { formatProtocolEvent, formatRawBytesDiagnostic } = loadEts('session/ProtocolLogger.ets', {
    '@kit.PerformanceAnalysisKit': { hilog: { error() {}, warn() {}, info() {}, debug() {} } },
    '../protocol/RawByteFormatter': rawByteFormatter,
    './LogTimestamp': { formatLocalClock: () => '[12:00:00.000]' }
  });
  const socketEvents = [];
  const handlers = {};
  const socket = {
    setReuseAddress(enabled) { socketEvents.push(`reuse:${enabled}`); },
    on(name, handler) { handlers[name] = handler; },
    off(name) { socketEvents.push(`off:${name}`); },
    async bind(address) { socketEvents.push(`bind:${address.port}`); },
    async addMembership(address) { socketEvents.push(`join:${address.address}`); },
    async dropMembership(address) { socketEvents.push(`drop:${address.address}`); },
    async close() { socketEvents.push('close'); }
  };
  const logs = [];
  const { AirPlayMdnsRawMonitor, summarizeMdnsDnsPacket } = loadEts('network/AirPlayMdnsRawMonitor.ets', {
    '@ohos.net.socket': { constructMulticastSocketInstance: () => socket },
    '../session/ProtocolLogger': { formatProtocolEvent, formatRawBytesDiagnostic },
    './WifiNetworkLease': { formatNetworkError: error => `${error.code}: ${error.message}` }
  });
  const dnsResponse = summarizeMdnsDnsPacket(Uint8Array.from([
    0, 1, 0x84, 0, 0, 1, 0, 2, 0, 0, 0, 0
  ]));
  assert.match(dnsResponse, /response/);
  assert.match(dnsResponse, /questions=1 answers=2/);
  assert.match(summarizeMdnsDnsPacket(new Uint8Array(8)), /malformed DNS header/);
  const lease = {
    async bindSocket(boundSocket, purpose, family, port) {
      socketEvents.push(`network:${purpose}:IPv${family}`);
      await boundSocket.bind({ address: '10.12.82.67', family, port });
    }
  };
  const monitor = new AirPlayMdnsRawMonitor(lease, message => logs.push(message));
  await monitor.start();

  assert.ok(socketEvents.includes('reuse:true'));
  assert.ok(socketEvents.includes('bind:5353'));
  assert.ok(socketEvents.includes('join:224.0.0.251'));
  assert.ok(socketEvents.some(event => event.includes('network:mDNS RAW UDP:IPv1')));
  handlers.message({
    message: Uint8Array.of(0x12, 0x34, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0).buffer,
    remoteInfo: { address: '10.12.82.1', port: 5353 }
  });
  assert.ok(logs.some(message => message.includes('RAW RX mDNS/DNS')));
  assert.ok(logs.some(message => message.includes('0000: 12 34 00 00')));
  assert.ok(logs.some(message => message.includes('questions=0 answers=0')));

  await monitor.stop();
  assert.ok(socketEvents.includes('drop:224.0.0.251'));
  assert.ok(socketEvents.includes('off:message'));
  assert.ok(socketEvents.includes('off:error'));
  assert.ok(socketEvents.includes('close'));
});

test('mDNS RAW monitor reports the failing startup stage and Harmony error details', async () => {
  const socketEvents = [];
  const socket = {
    setReuseAddress() {},
    on() {},
    off() {},
    async bind() {},
    async addMembership() { throw { code: 401, message: 'Parameter error' }; },
    async close() { socketEvents.push('closed'); }
  };
  const { AirPlayMdnsRawMonitor } = loadEts('network/AirPlayMdnsRawMonitor.ets', {
    '@ohos.net.socket': { constructMulticastSocketInstance: () => socket },
    '../session/ProtocolLogger': {
      formatProtocolEvent: event => event,
      formatRawBytesDiagnostic: () => ''
    },
    './WifiNetworkLease': {
      formatNetworkError: error => `code=${error.code}: ${error.message}`
    }
  });
  const monitor = new AirPlayMdnsRawMonitor({ async bindSocket() {} }, () => {});

  await assert.rejects(() => monitor.start(), /stage=multicast-membership.*code=401: Parameter error/);
  assert.deepEqual(socketEvents, ['closed']);
});

test('AirPlay mDNS discovery reports a bounded no-service timeout and keeps searching', () => {
  const previousSetTimeout = global.setTimeout;
  const previousClearTimeout = global.clearTimeout;
  let scheduled;
  global.setTimeout = (callback, delay) => { scheduled = { callback, delay }; return 41; };
  global.clearTimeout = () => {};
  const logs = [];
  const discoveryService = {
    on() {},
    off() {},
    startSearchingMDNS() {},
    stopSearchingMDNS() {}
  };
  try {
    const { AirPlayMdnsDiscovery } = loadEts('network/AirPlayMdnsDiscovery.ets', {
      '@ohos.net.mdns': { createDiscoveryService: () => discoveryService },
      '@ohos.app.ability.common': {},
      '@ohos.util': {},
      '../session/ProtocolLogger': {
        formatProtocolEvent: (event, ...fields) => `【${event}】 ${fields.join(' ')}`
      }
    });
    const discovery = new AirPlayMdnsDiscovery({}, () => {}, message => logs.push(message));
    discovery.start();
    assert.equal(scheduled.delay, 5000);
    scheduled.callback();
    assert.ok(logs.some(message => message.includes('mdns.discovery.timeout')));
    assert.ok(logs.some(message => message.includes('serviceCount 0')));
    assert.ok(discovery.discovery);
    discovery.stop();
    assert.ok(logs.some(message => message.includes('mdns.discovery.stopped')));
  } finally {
    global.setTimeout = previousSetTimeout;
    global.clearTimeout = previousClearTimeout;
  }
});

test('AirPlay mDNS discovery re-resolves a repeated service name when its endpoint changes', async () => {
  const handlers = {};
  const discovered = [];
  const discoveryService = {
    on(type, handler) { handlers[type] = handler; },
    off() {},
    startSearchingMDNS() {},
    stopSearchingMDNS() {}
  };
  let host = '10.36.232.90';
  const { AirPlayMdnsDiscovery } = loadEts('network/AirPlayMdnsDiscovery.ets', {
    '@ohos.net.mdns': {
      createDiscoveryService: () => discoveryService,
      resolveLocalService: async (_context, service) => ({
        serviceName: service.serviceName,
        host: { address: host },
        port: 7000,
        serviceAttribute: [{ key: 'deviceid', value: new TextEncoder().encode('AA:BB:CC:DD:EE:FF') }]
      })
    },
    '@ohos.app.ability.common': {},
    '@ohos.util': {
      TextDecoder: { create: () => ({ decodeToString: bytes => new TextDecoder().decode(bytes) }) }
    },
    '../session/ProtocolLogger': {
      formatProtocolEvent: (event, ...fields) => `【${event}】 ${fields.join(' ')}`
    }
  });
  const discovery = new AirPlayMdnsDiscovery({}, service => discovered.push(service), () => {});
  discovery.start();
  const found = { serviceName: 'receiver._airplay._tcp' };
  handlers.serviceFound(found);
  await new Promise(resolve => setImmediate(resolve));
  handlers.serviceFound(found);
  await new Promise(resolve => setImmediate(resolve));
  assert.deepEqual(discovered.map(service => service.host), ['10.36.232.90']);
  host = '10.36.232.92';
  handlers.serviceFound(found);
  await new Promise(resolve => setImmediate(resolve));
  assert.deepEqual(discovered.map(service => service.host), ['10.36.232.90', '10.36.232.92']);
  discovery.stop();
});
