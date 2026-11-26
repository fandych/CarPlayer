const { assert, fs, path, vm, test, ts, sourceRoot, audioSenderFixture, loadEts, loadMethods,
  loadProjectionSettingsController, videoSenderFixture } = require('../ProjectionBehaviorSupport.cjs');

test('all supported app icons resolve static resources and failed images have a visible fallback', () => {
  const { PROJECTION_APP_CANDIDATES, PROJECTION_VEHICLE_APPS } = loadEts('pages/ProjectionAppCatalog.ets');
  const previousResource = global.$r;
  global.$r = name => ({ name });
  try {
    const { projectionAppIconResource } = loadEts(
      'pages/ProjectionAppsPage.ets', {}, 'projectionAppIconResource'
    );
    for (const app of [...PROJECTION_APP_CANDIDATES, ...PROJECTION_VEHICLE_APPS]) {
      assert.deepEqual(projectionAppIconResource(app.appId), { name: app.icon });
    }
    assert.equal(projectionAppIconResource('unknown-player'), undefined);
  } finally {
    global.$r = previousResource;
  }
  const source = fs.readFileSync(path.join(sourceRoot, 'pages/ProjectionAppsPage.ets'), 'utf8');
  assert.doesNotMatch(source, /\$r\(this\.app\./);
  assert.match(source, /failedAppId !== this\.app\.appId/);
  assert.match(source, /\.onError\([\s\S]*this\.failedAppId = this\.app\.appId/);
  assert.match(source, /sys\.symbol\.speaker_wave_2/);
});

test('map surfaces stay landscape inside portrait receivers without stretching music or touch bounds', () => {
  const { projectionSurfaceSize } = loadEts('pages/ProjectionSurface.ets');
  const { projectionContentDisplayConfig } = loadEts('video/CarPlayVirtualDisplay.ets', {
    '@ohos.display': {},
    './ProjectionSettings': loadEts('video/ProjectionSettings.ets')
  });
  for (const [width, height] of [[418, 1872], [366, 1820], [800, 800], [1200, 700]]) {
    const size = projectionSurfaceSize(width, height, true);
    assert.ok(size.width > size.height);
    assert.ok(size.width <= width && size.height <= height);
    const pixels = { width: Math.round(size.width), height: Math.round(size.height) };
    const render = projectionContentDisplayConfig(pixels.width, pixels.height, 2);
    assert.ok(render.width > render.height);
    assert.ok(Math.abs(render.width / render.height - pixels.width / pixels.height) < 0.02);
    assert.deepEqual(projectionSurfaceSize(width, height, false), { width, height });
  }
  assert.throws(() => projectionSurfaceSize(0, 10, true), /Invalid projection surface/);
  const content = fs.readFileSync(path.join(sourceRoot, 'pages/ProjectionDashboardContent.ets'), 'utf8');
  const surface = fs.readFileSync(path.join(sourceRoot, 'pages/ProjectionContentSurface.ets'), 'utf8');
  assert.match(content, /surfaceName: 'projectionSplitMapSurface',\s*landscape: true/);
  assert.match(content, /surfaceName: 'projectionAppSurface',\s*landscape: this\.isActiveMap\(\)/);
  assert.match(surface, /this\.viewportWidth > 0 && this\.viewportHeight > 0/);
  assert.match(surface, /onSurfaceChange\(this\.surfaceId, newArea, true\)/);
});

test('log export menu sits above the page sheet and success waits for file close', async () => {
  const source = fs.readFileSync(path.join(sourceRoot, 'pages/IndexRootView.ets'), 'utf8');
  assert.ok(source.indexOf('this.PageSheet()') < source.indexOf('IndexMenuOverlay({'));
  const sheetStart = source.indexOf('  private PageSheet()');
  const sheetEnd = source.indexOf('\n  private pageTitle()', sheetStart);
  const sheet = source.slice(sheetStart, sheetEnd);
  assert.match(sheet, /this\.page === 'logs'[\s\S]*accessibilityText\('日志操作'\)/);
  assert.match(sheet, /this\.onMenuToggle\(\)/);
  const events = [];
  let selectedUris = ['file://logs.log'];
  let writeError;
  const Target = loadMethods('pages/Index.ets', 'Index', ['exportLogs'], {
    Error,
    picker: { DocumentViewPicker: class {
      constructor(context) { assert.equal(context, 'ability-context'); }
      async save() { events.push('picker'); return selectedUris; }
    } },
    formatLocalTimestamp: () => '2026-11-04T19:00:00.000+08:00',
    fileFs: {
      OpenMode: { WRITE_ONLY: 1, CREATE: 2, TRUNC: 4 },
      async open(uri) { events.push(['open', uri]); return { fd: 3 }; },
      async write(fd, text) {
        if (writeError) throw writeError;
        events.push(['write', fd, text]);
      },
      async close(file) { events.push(['close', file.fd]); }
    },
    diagnosticLogArchive: { readAllText: () => '完整日志' },
    promptAction: { async showToast() { events.push('success'); } }
  });
  const target = new Target();
  target.getAppContext = () => 'ability-context';
  target.showError = error => events.push(['error', error.message]);
  target.logs = [];
  await target.exportLogs();
  assert.deepEqual(events, [
    'picker', ['open', 'file://logs.log'], ['write', 3, '完整日志\n'], ['close', 3], 'success'
  ]);
  events.length = 0;
  selectedUris = [];
  await target.exportLogs();
  assert.deepEqual(events, ['picker']);
  events.length = 0;
  selectedUris = ['file://logs.log'];
  writeError = new Error('write denied');
  await target.exportLogs();
  assert.deepEqual(events, ['picker', ['open', 'file://logs.log'], ['error', 'write denied'], ['close', 3]]);
});

test('restricted permissions are declared but never treated as approved or third-party input capability', () => {
  const module = fs.readFileSync(path.join(sourceRoot, '../module.json5'), 'utf8');
  const settings = fs.readFileSync(path.join(sourceRoot, 'pages/SettingsPage.ets'), 'utf8');
  for (const permission of [
    'ohos.permission.ACCESS_VIRTUAL_SCREEN',
    'ohos.permission.MANAGE_MEDIA_RESOURCES_FOR_PUBLIC',
    'ohos.permission.CUSTOM_SCREEN_CAPTURE'
  ]) {
    assert.ok(module.includes(permission), `missing manifest declaration: ${permission}`);
    assert.ok(settings.includes(permission), `missing permission status check: ${permission}`);
  }
  assert.doesNotMatch(module, /ohos\.permission\.CONTROL_DEVICE/);
  assert.doesNotMatch(module, /ohos\.permission\.GET_BUNDLE_INFO/);
  assert.doesNotMatch(settings, /ohos\.permission\.GET_BUNDLE_INFO/);
  assert.match(settings, /未授予\/未审批/);
});

test('custom vehicle icons are bundled library SVGs with native-compatible dimensions and a license', () => {
  const media = path.join(sourceRoot, '../resources/base/media');
  for (const name of ['house', 'layout_grid', 'split', 'day_night', 'settings', 'car_front', 'palette',
    'navigation', 'cloud_sun', 'music']) {
    const source = fs.readFileSync(path.join(media, `ic_${name}.svg`), 'utf8');
    assert.match(source, /viewBox="0 0 24 24"/);
    assert.match(source, /width="64"/);
    assert.match(source, /height="64"/);
    assert.match(source, /stroke="#F5F5F7"/);
    assert.doesNotMatch(source, /<script|https?:[^\s]+\.(?:png|jpg)/i);
  }
  const license = fs.readFileSync(path.join(sourceRoot, '../resources/rawfile/lucide_license.txt'), 'utf8');
  assert.match(license, /ISC License/);
});

test('vehicle home app requests the receiver UI rather than opening a phone application', () => {
  const Target = loadMethods('pages/ProjectionDashboard.ets', 'ProjectionDashboard', ['selectApp']);
  const target = new Target();
  let requests = 0;
  target.onReceiverHomeClick = () => { requests++; };
  target.showDashboardView = () => { throw new Error('receiver home is not a local view'); };
  target.onAppClick = () => { throw new Error('receiver home must not launch a phone app'); };
  target.selectApp({ category: 'vehicle', view: 'receiver' });
  assert.equal(requests, 1);
});

test('event parser retains partial frames, splits batches, supports OPTIONS and rejects ambiguous framing', () => {
  const { parseAirPlayEventRequests: parse } = loadEts('airplay/AirPlayEventProtocol.ets', {
    '@ohos.net.socket': {}, './ControlCipher': {}, '../network/WifiNetworkLease': {},
    './AirPlayCrypto': {},
    './BinaryPlist': { BinaryPlist: {}, formatPlistDiagnostic: () => '' },
    '../session/ProtocolLogger': { formatProtocolEvent: () => '', formatRawBytesDiagnostic: () => '' },
    '../protocol/Iap2Codec': { decodeUtf8: bytes => new TextDecoder().decode(bytes) }
  });
  const encode = text => new TextEncoder().encode(text);
  const first = 'POST /command RTSP/1.0\r\nCSeq: 1\r\nContent-Length: 4\r\n\r\ndata';
  const partial = encode(first.slice(0, -2));
  assert.equal(parse(partial).requests.length, 0);
  assert.deepEqual(parse(partial).remaining, partial);
  const batch = parse(encode(first + 'OPTIONS * RTSP/1.0\r\nCSeq: 2\r\n\r\n'));
  assert.equal(batch.requests.length, 2);
  assert.equal(new TextDecoder().decode(batch.requests[0].body), 'data');
  assert.equal(batch.requests[1].target, '*');
  assert.equal(batch.remaining.length, 0);
  for (const headers of [
    'CSeq: 1x', 'CSeq: 1\r\nContent-Length: 2x',
    'CSeq: 1\r\nContent-Length: 0\r\nContent-Length: 0',
    'CSeq: 1\r\nCSeq: 2', 'CSeq: 1\r\nContent-Length: 1048577',
    'CSeq: 1\r\nTransfer-Encoding: chunked', 'CSeq: 9007199254740992'
  ]) {
    assert.throws(() => parse(encode(`POST /command RTSP/1.0\r\n${headers}\r\n\r\n`)));
  }
  assert.throws(() => parse(encode(`POST /command RTSP/1.0\r\nCSeq: 1\r\nX-Pad: ${'x'.repeat(65536)}\r\n\r\n`)));
});
