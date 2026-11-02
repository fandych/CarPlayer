const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { test } = require('node:test');

const sdk = process.env.DEVECO_SDK_HOME || 'C:/Program Files/Huawei/DevEco Studio/sdk';
const ts = require(path.join(sdk, 'default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
const sourceRoot = path.resolve(__dirname, '../main/ets');

test('capture, encoder, Dock, safe-area and day/night settings stay within supported defaults', () => {
  const {
    resolveProjectionRates, projectionTheme, resolveNightMode, normalizeSafeInset, projectionSafeInsetKey,
    projectionDisplayModes, resolveProjectionDisplayMode, projectionResolutionKey,
    projectionContentCalibrationKey, normalizeProjectionContentScale, normalizeProjectionContentOffset,
    isSupportedProjectionSize
  } = loadEts('video/ProjectionSettings.ets');
  assert.deepEqual(resolveProjectionRates(30, 60, 60), { capture: 30, encode: 30 });
  assert.deepEqual(resolveProjectionRates(60, 24, 60), { capture: 60, encode: 24 });
  assert.deepEqual(resolveProjectionRates(60, 60, 30), { capture: 30, encode: 30 });
  assert.deepEqual(resolveProjectionRates(NaN, -1, 999), { capture: 30, encode: 30 });
  assert.equal(projectionTheme('unknown').id, 'forest');
  assert.equal(projectionTheme('graphite').background, '#161616');
  assert.equal(resolveNightMode('AUTO', true), true);
  assert.equal(resolveNightMode('AUTO', false), false);
  assert.equal(resolveNightMode('DAY', true), false);
  assert.equal(resolveNightMode('NIGHT', false), true);
  assert.equal(normalizeSafeInset(-1), 0);
  assert.equal(normalizeSafeInset(12.4), 12);
  assert.equal(normalizeSafeInset(40), 30);
  assert.equal(normalizeSafeInset(NaN), 0);
  assert.equal(projectionSafeInsetKey('Display-1', 'top'), 'carplayDisplayProfile_display-1_inset_top');
  assert.notEqual(projectionSafeInsetKey('Display-1', 'top'), projectionSafeInsetKey('Display-2', 'top'));
  assert.equal(projectionResolutionKey('Display-1'), 'carplayDisplayProfile_display-1_resolution');
  assert.equal(projectionContentCalibrationKey('Display-1', 'scale'),
    'carplayDisplayProfile_display-1_content_scale');
  assert.notEqual(projectionContentCalibrationKey('Display-1', 'offsetX'),
    projectionContentCalibrationKey('Display-2', 'offsetX'));
  assert.equal(normalizeProjectionContentScale(60), 70);
  assert.equal(normalizeProjectionContentScale(101), 100);
  assert.equal(normalizeProjectionContentScale(NaN), 100);
  assert.equal(normalizeProjectionContentOffset(-20), -15);
  assert.equal(normalizeProjectionContentOffset(18), 15);
  assert.equal(normalizeProjectionContentOffset(NaN), 0);
  assert.equal(isSupportedProjectionSize(2560, 1080), true);
  assert.equal(isSupportedProjectionSize(1920, 1920), true);

  const supportsTestSizes = (width, height) =>
    (width === 1280 && height === 720) || (width === 800 && height === 450);
  const modes = projectionDisplayModes('Display-1', 1280, 720, [
    { displayUuid: 'display-1', nativeWidth: 1280, nativeHeight: 720, id: 'verified-800', width: 800, height: 450,
      encoder: 'video/avc' },
    { displayUuid: 'display-2', nativeWidth: 1280, nativeHeight: 720, id: 'other-display',
      width: 800, height: 450, encoder: 'video/avc' },
    { displayUuid: 'display-1', nativeWidth: 1280, nativeHeight: 720, id: 'wrong-aspect',
      width: 800, height: 480, encoder: 'video/avc' },
    { displayUuid: 'display-1', nativeWidth: 1280, nativeHeight: 720, id: 'too-large',
      width: 2560, height: 1440, encoder: 'video/avc' }
  ], supportsTestSizes);
  assert.deepEqual(modes.map(mode => mode.id), ['receiver-native', 'verified-800']);
  assert.equal(resolveProjectionDisplayMode(modes, 'verified-800').mode.width, 800);
  assert.equal(resolveProjectionDisplayMode(modes, 'unknown').mode.id, 'receiver-native');
  assert.equal(resolveProjectionDisplayMode(modes, 'unknown').usedNativeFallback, true);
  assert.deepEqual(projectionDisplayModes('Display-1', 2500, 1400, [], () => false), []);
  const fallbackModes = projectionDisplayModes('Square-Display', 1920, 1920, [],
    (width, height) => width <= 1920 && height <= 1200);
  assert.equal(fallbackModes[0].id, 'encoder-fallback-1152x1152');
  assert.equal(fallbackModes[0].isNative, false);
  assert.equal(resolveProjectionDisplayMode(fallbackModes, 'receiver-native').mode.width, 1152);
  assert.throws(() => resolveProjectionDisplayMode([], 'receiver-native'), /原生分辨率/);
});

test('projection settings provide spacious controls and a direct icon-led day/night selector', () => {
  const source = fs.readFileSync(path.join(sourceRoot, 'pages/ProjectionDashboard.ets'), 'utf8');
  assert.match(source, /app\.media\.ic_day_night/);
  assert.match(source, /\.height\(76\)\.padding\(12\)\.borderRadius\(8\)/);
  assert.match(source, /\.height\(42\)\.padding\(\{ left: 9, right: 9 \}\)/);
  const Target = loadMethods('pages/ProjectionDashboard.ets', 'ProjectionDashboard', ['selectDayNightMode']);
  const target = new Target();
  target.selectDayNightMode('NIGHT');
  assert.equal(target.dayNightMode, 'NIGHT');
  target.selectDayNightMode('AUTO');
  assert.equal(target.dayNightMode, 'AUTO');
});

test('irregular-display calibration preserves aspect ratio and maps touch coordinates back', () => {
  const { normalizeProjectionContentScale, normalizeProjectionContentOffset } =
    loadEts('video/ProjectionSettings.ets');
  const Target = loadMethods('pages/ProjectionDashboard.ets', 'ProjectionDashboard', ['screenToContentPoint']);
  const target = new Target();
  target.contentScalePercent = normalizeProjectionContentScale(80);
  target.contentOffsetXPercent = normalizeProjectionContentOffset(10);
  target.contentOffsetYPercent = normalizeProjectionContentOffset(-5);
  target.projectionViewportWidth = 1000;
  target.projectionViewportHeight = 800;
  const mapped = target.screenToContentPoint(440, 200);
  assert.deepEqual([mapped.x, mapped.y], [300, 200]);
  const dashboardSource = fs.readFileSync(path.join(sourceRoot, 'pages/ProjectionDashboard.ets'), 'utf8');
  assert.match(dashboardSource,
    /\.scale\(\{ x: this\.contentScalePercent \/ 100, y: this\.contentScalePercent \/ 100 \}\)/);
});

test('content calibration persists independently for each display profile', () => {
  const writes = [];
  const Target = loadMethods('pages/ProjectionDashboard.ets', 'ProjectionDashboard', ['adjustContentCalibration'], {
    saveProjectionContentCalibration(displayUuid, control, value) {
      writes.push([displayUuid, control, value]);
      return control === 'scale' ? Math.min(100, Math.max(70, value)) : Math.min(15, Math.max(-15, value));
    }
  });
  const target = new Target();
  target.vehicleDisplayUuid = 'display-a';
  target.contentScalePercent = 100;
  target.contentOffsetXPercent = 0;
  target.contentOffsetYPercent = 0;
  target.adjustContentCalibration('scale', -1);
  target.adjustContentCalibration('offsetX', 1);
  target.vehicleDisplayUuid = 'display-b';
  target.adjustContentCalibration('offsetY', -1);
  assert.deepEqual(writes, [
    ['display-a', 'scale', 99],
    ['display-a', 'offsetX', 1],
    ['display-b', 'offsetY', -1]
  ]);
  assert.equal(target.contentOffsetYPercent, -1);
});

test('AirPlay display profile uses /info dimensions and refuses invented or silently scaled sizes', () => {
  const settings = loadEts('video/ProjectionSettings.ets');
  const filename = path.join(sourceRoot, 'airplay/AirPlayMediaSession.ets');
  const source = fs.readFileSync(filename, 'utf8');
  const parsed = ts.createSourceFile(filename, source, ts.ScriptTarget.Latest, true);
  const declaration = parsed.statements.find(statement =>
    ts.isFunctionDeclaration(statement) && statement.name?.text === 'readDisplayInfo');
  const activeAreaDeclaration = parsed.statements.find(statement =>
    ts.isFunctionDeclaration(statement) && statement.name?.text === 'readActiveViewArea');
  assert.ok(declaration);
  assert.ok(activeAreaDeclaration);
  const javascript = ts.transpileModule(
    `${activeAreaDeclaration.getText(parsed)}\n${declaration.getText(parsed)}\nreadDisplayInfo`, {
    compilerOptions: { target: ts.ScriptTarget.ES2020 }
  }).outputText;
  const makeReader = (preferredMode, modes = settings.projectionDisplayModes,
    supportsSize = settings.isSupportedProjectionSize) => vm.runInNewContext(javascript, {
    projectionDisplayModes: modes,
    VERIFIED_PROJECTION_DISPLAY_MODES: settings.VERIFIED_PROJECTION_DISPLAY_MODES,
    isH264EncoderSizeSupported: supportsSize,
    readProjectionResolutionPreference: () => preferredMode,
    saveProjectionResolutionPreference: () => {},
    resolveProjectionDisplayMode: settings.resolveProjectionDisplayMode,
    BigInt, Number, Array, Math
  });
  const dictionary = entries => ({
    kind: 'dictionary',
    get(key) { return entries.get(key); }
  });
  const infoFor = (displayFields) => dictionary(new Map([['displays', {
    kind: 'array',
    arrayValue: [dictionary(new Map(Object.entries(displayFields)))]
  }]]));
  const integer = value => ({ kind: 'integer', integerValue: BigInt(value) });
  const string = value => ({ kind: 'string', stringValue: value });
  const nativeInfo = infoFor({
    uuid: string('display-1'),
    type: integer(110),
    widthPixels: integer(1280),
    heightPixels: integer(720),
    maxFPS: integer(60)
  });
  const native = makeReader('receiver-native')(nativeInfo);
  assert.deepEqual(
    { width: native.width, height: native.height, sourceWidth: native.sourceWidth, sourceHeight: native.sourceHeight },
    { width: 1280, height: 720, sourceWidth: 1280, sourceHeight: 720 }
  );
  assert.deepEqual(
    [native.viewArea.originX, native.viewArea.originY, native.viewArea.width, native.viewArea.height],
    [0, 0, 1280, 720]
  );
  const verifiedModes = (uuid, width, height, _verified, supportsSize) =>
    settings.projectionDisplayModes(uuid, width, height, [
      { displayUuid: uuid, nativeWidth: width, nativeHeight: height, id: 'verified-800x450',
        width: 800, height: 450, encoder: 'video/avc' }
    ], supportsSize);
  const selected = makeReader('verified-800x450', verifiedModes)(nativeInfo);
  assert.equal(selected.width, 800);
  assert.equal(selected.height, 450);
  assert.equal(selected.nativeWidth, 1280);
  assert.equal(selected.modeId, 'verified-800x450');
  const wideNative = makeReader('receiver-native')(infoFor({
    uuid: string('display-1'), widthPixels: integer(2560), heightPixels: integer(1080)
  }));
  assert.equal(wideNative.width, 2560);
  assert.equal(wideNative.height, 1080);
  const squareInfo = infoFor({
    uuid: string('display-square'),
    type: integer(110),
    widthPixels: integer(1920),
    heightPixels: integer(1920),
    initialViewArea: integer(0),
    viewAreas: { kind: 'array', arrayValue: [
      dictionary(new Map([
        ['widthPixels', integer(1920)], ['heightPixels', integer(1080)],
        ['originXPixels', integer(0)], ['originYPixels', integer(0)]
      ])),
      dictionary(new Map([
        ['widthPixels', integer(1080)], ['heightPixels', integer(1920)],
        ['originXPixels', integer(0)], ['originYPixels', integer(0)]
      ]))
    ] }
  });
  const squareNative = makeReader('receiver-native')(squareInfo);
  assert.deepEqual(
    [squareNative.viewArea.originX, squareNative.viewArea.originY,
      squareNative.viewArea.width, squareNative.viewArea.height],
    [0, 0, 1920, 1080]
  );
  const squareFallback = makeReader('receiver-native', settings.projectionDisplayModes,
    (width, height) => width <= 1920 && height <= 1200)(squareInfo);
  assert.equal(squareFallback.width, 1152);
  assert.equal(squareFallback.height, 1152);
  assert.deepEqual(
    [squareFallback.viewArea.originX, squareFallback.viewArea.originY,
      squareFallback.viewArea.width, squareFallback.viewArea.height],
    [0, 0, 1152, 648]
  );
  assert.match(squareFallback.resolutionMessage, /自动下采样到 1152×1152/);
  assert.throws(() => makeReader('receiver-native')(infoFor({
    uuid: string('display-1'), heightPixels: integer(720)
  })), /missing valid widthPixels\/heightPixels/);
});

test('AirPlay TLV8 adapter preserves continuation and duplicate-item semantics', () => {
  const encodeNative = (types, values) => {
    const parts = [];
    for (let index = 0; index < types.length; index++) {
      const type = types[index];
      const value = values[index];
      if (index > 0 && type === types[index - 1]) parts.push(new Uint8Array([0xff, 0]));
      if (value.length === 0) parts.push(new Uint8Array([type, 0]));
      for (let offset = 0; offset < value.length; offset += 255) {
        const fragment = value.subarray(offset, Math.min(offset + 255, value.length));
        parts.push(new Uint8Array([type, fragment.length]), fragment);
      }
    }
    const result = new Uint8Array(parts.reduce((total, part) => total + part.length, 0));
    let offset = 0;
    for (const part of parts) { result.set(part, offset); offset += part.length; }
    return result;
  };
  const decodeNative = bytes => {
    const valuesByType = new Map();
    let previousType = -1;
    let previousLength = 0;
    let separatorSeen = false;
    for (let offset = 0; offset < bytes.length;) {
      const length = bytes[offset + 1];
      if (length === undefined || offset + 2 + length > bytes.length) throw new Error('Malformed TLV8');
      const type = bytes[offset];
      if (type === undefined || (type === 0xff && length !== 0)) throw new Error('Malformed TLV8');
      const value = bytes.slice(offset + 2, offset + 2 + length);
      if (type === 0xff) {
        previousType = -1;
        previousLength = 0;
        separatorSeen = true;
        offset += 2 + length;
        continue;
      }
      if (type === previousType && previousLength === 255 && !separatorSeen) {
        const prior = valuesByType.get(type) ?? new Uint8Array(0);
        const combined = new Uint8Array(prior.length + value.length);
        combined.set(prior);
        combined.set(value, prior.length);
        valuesByType.set(type, combined);
      } else {
        valuesByType.set(type, value);
      }
      previousType = type;
      previousLength = length;
      separatorSeen = false;
      offset += 2 + length;
    }
    const ranges = [];
    const values = [];
    for (const [type, value] of valuesByType) {
      ranges.push(type, values.length, value.length);
      for (const byte of value) values.push(byte);
    }
    return { ranges: Uint32Array.from(ranges), values: Uint8Array.from(values) };
  };
  const { encodeTlv8, decodeTlv8 } = loadEts('airplay/Tlv8.ets', {
    '../protocol/Iap2Codec': {
      encodeTlv8Native: encodeNative,
      decodeTlv8Native: decodeNative
    }
  });
  const continuation = Uint8Array.from({ length: 256 }, (_value, index) => index & 0xff);
  const encoded = encodeTlv8([{ type: 3, value: continuation }]);
  assert.equal(encoded[1], 255);
  assert.equal(encoded[257], 3);
  assert.equal(encoded[258], 1);
  assert.deepEqual(Array.from(decodeTlv8(encoded).get(3)), Array.from(continuation));

  const repeated = encodeTlv8([
    { type: 4, value: new Uint8Array([0x11]) },
    { type: 4, value: new Uint8Array([0x22]) }
  ]);
  assert.deepEqual(Array.from(repeated), [4, 1, 0x11, 0xff, 0, 4, 1, 0x22]);
  assert.deepEqual(Array.from(decodeTlv8(repeated).get(4)), [0x22]);
  assert.throws(() => encodeTlv8([{ type: 0xff, value: new Uint8Array(0) }]), /Invalid TLV8 type/);
});

test('session lifecycle adapter delegates opaque generation tokens to native state', () => {
  let generation = 0n;
  const { advanceSessionGeneration, isCurrentSessionGeneration } = loadEts('session/NativeSessionLifecycle.ets', {
    'libsessioncore.so': {
      advanceGeneration() { generation++; return generation.toString(); },
      isCurrentGeneration(token) { return token === generation.toString(); }
    }
  });
  const first = advanceSessionGeneration();
  assert.equal(isCurrentSessionGeneration(first), true);
  const second = advanceSessionGeneration();
  assert.notEqual(first, second);
  assert.equal(isCurrentSessionGeneration(first), false);
  assert.equal(isCurrentSessionGeneration(second), true);
});

test('AirPlay requests /info with a plist body only after initial SETUP', () => {
  const pairingSource = fs.readFileSync(path.join(sourceRoot, 'airplay/AirPlayPairingClient.ets'), 'utf8');
  const sessionSource = fs.readFileSync(path.join(sourceRoot, 'airplay/AirPlayMediaSession.ets'), 'utf8');
  const rtspSource = fs.readFileSync(path.join(sourceRoot, 'airplay/AirPlayRtspClient.ets'), 'utf8');
  assert.doesNotMatch(pairingSource, /['"]\/info['"]/);
  const setupPosition = sessionSource.indexOf("'initial session SETUP'");
  const infoPosition = sessionSource.indexOf("'receiver /info after initial session SETUP'");
  assert.ok(setupPosition >= 0);
  assert.ok(infoPosition > setupPosition);
  assert.match(sessionSource,
    /this\.request\(\s*'GET',\s*'\/info',\s*BinaryPlist\.encode\(PlistNode\.dictionary\(new Map<string, PlistNode>\(\)\)\)/);
  assert.match(sessionSource, /contentType: 'application\/x-apple-binary-plist'/);
  assert.match(rtspSource, /RTSP_REQUEST_TIMEOUT_MS:\s*number\s*=\s*10_000/);
  assert.match(rtspSource, /'bodySummary',\s*formatRtspBodySummary/);
  assert.doesNotMatch(sessionSource, /client\.request\(\s*'OPTIONS'/);
  assert.doesNotMatch(rtspSource, /X-Apple-Device-ID|X-Apple-Client-Name|Connection: keep-alive/);
});

test('socket error formatting preserves platform error codes and messages', () => {
  const { formatNetworkError } = loadEts('network/WifiNetworkLease.ets', {}, 'formatNetworkError');
  assert.equal(formatNetworkError(new Error('connection refused')), 'connection refused');
  assert.equal(formatNetworkError({ code: 2300026, message: 'link-local scope unavailable' }),
    'code=2300026: link-local scope unavailable');
});

test('Bluetooth audio preference defaults off and initialization preserves the saved selection', () => {
  const source = fs.readFileSync(path.join(sourceRoot, 'video/ProjectionSettings.ets'), 'utf8');
  const javascript = ts.transpileModule(source, {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
  }).outputText;
  for (const saved of [undefined, true, false]) {
    const stored = new Map();
    if (saved !== undefined) stored.set('carplayUseBluetoothAudio', saved);
    const calls = [];
    const exports = {};
    vm.runInNewContext(javascript, {
      exports,
      PersistentStorage: { persistProp(key, value) {
        calls.push(key);
        if (!stored.has(key)) stored.set(key, value);
      } }
    });
    exports.initializeProjectionSettings();
    exports.initializeProjectionSettings();
    assert.equal(stored.get('carplayUseBluetoothAudio'), saved ?? false);
    assert.equal(calls.filter(key => key === 'carplayUseBluetoothAudio').length, 1);
    assert.equal(stored.get('carplayDockPosition'), 'left');
    assert.equal(stored.get('carplayDayNightMode'), 'AUTO');
    assert.equal(calls.filter(key => key === 'carplayDockPosition').length, 1);
    assert.equal(calls.filter(key => key === 'carplayDayNightMode').length, 1);
  }
});

test('vehicle Bluetooth audio touch area is active only on the settings page', () => {
  const source = fs.readFileSync(path.join(sourceRoot, 'pages/ProjectionDashboard.ets'), 'utf8');
  const parsed = ts.createSourceFile('ProjectionDashboard.ts',
    source.replace('struct ProjectionDashboard {', 'class ProjectionDashboard {'), ts.ScriptTarget.Latest, true);
  const declaration = parsed.statements.find(statement =>
    ts.isClassDeclaration(statement) && statement.name?.text === 'ProjectionDashboard');
  const methods = declaration.members.filter(member =>
    ['touchHandler', 'canvasPixelToContentPoint', 'screenToContentPoint'].includes(member.name?.text));
  const javascript = ts.transpileModule(`class Target { ${methods.map(member => member.getText(parsed)).join('\n')} }`, {
    compilerOptions: { target: ts.ScriptTarget.ES2020 }
  }).outputText;
  const Target = vm.runInNewContext(`${javascript}\nTarget`, {
    AppStorage: { get: key => key === 'carplayProjectionHomeActive' ? true : 7 }
  });
  const target = new Target();
  let toggles = 0;
  target.getUIContext = () => ({ px2vp: value => value });
  target.viewAreaOriginX = 0;
  target.viewAreaOriginY = 0;
  target.screenToContentPoint = (x, y) => ({ x, y });
  target.contains = () => true;
  target.touchBounds = new Map([['settings', {}]]);
  target.touchAreas = new Map([['bluetoothAudio', { group: 'settings', action: () => { toggles++; } }]]);
  const event = { data: { displayId: 7, startX: 10, startY: 10, endX: 10, endY: 10 } };
  for (const view of ['home', 'apps', 'themes']) {
    target.dashboardView = view;
    target.touchHandler(event);
  }
  assert.equal(toggles, 0);
  target.dashboardView = 'settings';
  target.touchHandler(event);
  assert.equal(toggles, 1);
});

test('third-party launch targets come from the reference and URI probes control availability', async () => {
  const { PROJECTION_APP_CANDIDATES, PROJECTION_VEHICLE_APPS, resolveProjectionApps } =
    loadEts('pages/ProjectionAppCatalog.ets');
  assert.equal(PROJECTION_APP_CANDIDATES.length, 13);
  for (const app of PROJECTION_APP_CANDIDATES) {
    assert.ok(app.icon, app.label);
    assert.match(app.uri, /^carplay-client:\/\/v1\/apps\//);
    assert.equal(app.launchState, 'UNVERIFIED');
  }
  const amap = PROJECTION_APP_CANDIDATES.find(app => app.appId === 'amap');
  assert.equal(amap.launchTarget.kind, 'ability');
  assert.equal(amap.launchTarget.bundleName, 'com.amap.hmapp');
  assert.equal(amap.launchTarget.abilityName, 'EntryAbility');
  assert.equal(amap.launchTarget.probeUri, 'amapuri://');
  assert.equal(PROJECTION_APP_CANDIDATES.find(app => app.appId === 'baidu-map').launchTarget.uri,
    'baidumap://map');
  assert.equal(PROJECTION_APP_CANDIDATES.find(app => app.appId === 'tencent-map').launchTarget.uri,
    'qqmap://');
  const huaweiMusic = PROJECTION_APP_CANDIDATES.find(app => app.appId === 'huawei-music');
  assert.equal(huaweiMusic.bundleName, 'com.huawei.hmsapp.music');
  assert.equal(huaweiMusic.abilityName, 'MainAbility');
  assert.equal(huaweiMusic.launchTarget.uri, 'hwmusic://com.huawei.hmsapp.music');
  assert.equal(PROJECTION_APP_CANDIDATES.find(app => app.appId === 'kugou-music').launchTarget.uri,
    'kugou://m.kugou.com');
  assert.equal(PROJECTION_APP_CANDIDATES.find(app => app.appId === 'eastmoney').launchTarget.probeUri,
    'emoh://eastmoney.com');
  assert.deepEqual(PROJECTION_VEHICLE_APPS.map(app => app.view), ['receiver', 'settings', 'themes', 'split']);
  const probedLinks = [];
  const resolved = await resolveProjectionApps(uri => {
    probedLinks.push(uri);
    return [
      'amapuri://',
      'baidumap://map',
      'qqmap://',
      'hwmusic://com.huawei.hmsapp.music',
      'qqmusic://',
      'orpheus://',
      'kugou://m.kugou.com',
      'snssdk1128://',
      'kwai://',
      'emoh://eastmoney.com',
      'tenvideo2://'
    ].includes(uri);
  });
  assert.deepEqual(resolved.filter(app => app.launchState === 'VERIFIED').map(app => app.appId),
    ['amap', 'baidu-map', 'tencent-map', 'huawei-music', 'qq-music', 'netease-music', 'kugou-music',
      'douyin', 'kuaishou', 'eastmoney', 'tencent-video']);
  assert.ok(probedLinks.includes('amapuri://'));
  assert.ok(probedLinks.includes('baidumap://map'));
  assert.ok(probedLinks.includes('qqmap://'));
  assert.ok(probedLinks.includes('hwmusic://com.huawei.hmsapp.music'));
  assert.ok(probedLinks.includes('qqmusic://'));
  assert.ok(probedLinks.includes('orpheus://'));
  assert.ok(probedLinks.includes('kugou://m.kugou.com'));
  assert.ok(probedLinks.includes('snssdk1128://'));
  assert.ok(probedLinks.includes('kwai://'));
  assert.ok(probedLinks.includes('emoh://eastmoney.com'));
  assert.ok(probedLinks.includes('tenvideo2://'));
  assert.equal(resolved.find(app => app.appId === 'petal-maps').launchTarget, undefined);
  const moduleManifest = fs.readFileSync(path.join(sourceRoot, '../module.json5'), 'utf8');
  for (const scheme of [
    'amapuri', 'baidumap', 'hwmusic', 'qqmap', 'qqmusic', 'orpheus', 'kugou', 'snssdk1128', 'kwai', 'emoh',
    'tenvideo2'
  ]) {
    assert.match(moduleManifest, new RegExp(`"${scheme}"`), `querySchemes must include ${scheme}`);
  }
  assert.doesNotMatch(moduleManifest, /ohos\.permission\.GET_BUNDLE_INFO/);
});

test('project branding and legacy app icons use the provided resources', () => {
  const appConfig = JSON.parse(fs.readFileSync(path.join(sourceRoot, '../../../../AppScope/app.json5'), 'utf8'));
  const appStrings = JSON.parse(fs.readFileSync(
    path.join(sourceRoot, '../../../../AppScope/resources/base/element/string.json'), 'utf8'));
  assert.equal(appConfig.app.bundleName, 'com.fandy.carplayer');
  assert.equal(appConfig.app.icon, '$media:logo_512');
  assert.equal(appStrings.string.find(entry => entry.name === 'app_name')?.value, 'CarPlayer');
  assert.ok(fs.existsSync(path.join(sourceRoot, '../../../../AppScope/resources/base/media/logo_512.png')));

  const { PROJECTION_APP_CANDIDATES } = loadEts('pages/ProjectionAppCatalog.ets');
  const legacyIcons = {
    amap: 'app_amap',
    'baidu-map': 'app_baidu',
    'tencent-map': 'app_tencent_map',
    'huawei-music': 'app_huawei_music',
    'qq-music': 'app_qqmusic',
    'netease-music': 'app_netease',
    'kugou-music': 'app_kugou',
    douyin: 'app_douyin',
    kuaishou: 'app_kuaishou',
    eastmoney: 'app_eastmoney',
    'tencent-video': 'app_tencent_video'
  };
  const media = path.join(sourceRoot, '../resources/base/media');
  for (const [appId, iconName] of Object.entries(legacyIcons)) {
    const app = PROJECTION_APP_CANDIDATES.find(candidate => candidate.appId === appId);
    assert.equal(app.icon, `app.media.${iconName}`);
    assert.ok(fs.existsSync(path.join(media, `${iconName}.png`)), `missing icon for ${appId}`);
  }
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
  const { parseAirPlayEventRequests: parse } = loadEts('airplay/AirPlayEventChannel.ets', {
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

test('AirPlay SETUP payloads round-trip with one negotiated audio stream and declared controller features', () => {
  const concatBytes = (...parts) => {
    const result = new Uint8Array(parts.reduce((length, part) => length + part.length, 0));
    let offset = 0;
    for (const part of parts) {
      result.set(part, offset);
      offset += part.length;
    }
    return result;
  };
  const util = {
    TextDecoder: { create: () => ({ decodeToString: bytes => new TextDecoder().decode(bytes) }) }
  };
  const { BinaryPlist, PlistNode } = loadEts('airplay/BinaryPlist.ets', {
    '@ohos.util': util,
    '../protocol/Iap2Codec': { concatBytes, encodeUtf8: text => new TextEncoder().encode(text) }
  });
  const audioSetup = loadMethods('airplay/AirPlayMediaSession.ets', 'AirPlayMediaSession',
    ['buildAudioSetupPayload'], { BinaryPlist, PlistNode, SAMPLES_PER_PACKET: 352 });
  const audio = BinaryPlist.decode(audioSetup.buildAudioSetupPayload(123n, 1n << 15n, 250));
  const streams = audio.get('streams');
  assert.equal(streams.kind, 'array');
  assert.equal(streams.arrayValue.length, 1);
  assert.equal(Number(streams.arrayValue[0].get('framesPerPacket').integerValue), 352);
  assert.equal(Number(streams.arrayValue[0].get('spf').integerValue), 352);
  const hidModeSetup = loadMethods('airplay/AirPlayMediaSession.ets', 'AirPlayMediaSession',
    ['buildHidSetInputModePayload'], { BinaryPlist, PlistNode });
  const hidMode = BinaryPlist.decode(hidModeSetup.buildHidSetInputModePayload('2A2A2A2A'));
  assert.equal(hidMode.get('type').stringValue, 'hidSetInputMode');
  assert.equal(Number(hidMode.get('params').get('hidInputMode').integerValue), 0);
  assert.equal(hidMode.get('params').get('uuid').stringValue, '2a2a2a2a');
  const mediaSessionSource = fs.readFileSync(path.join(sourceRoot, 'airplay/AirPlayMediaSession.ets'), 'utf8');
  assert.ok(mediaSessionSource.indexOf('eventChannel.sendCommand(AirPlayMediaSession.buildHidSetInputModePayload') <
    mediaSessionSource.indexOf("'video stream SETUP'"));

  const sessionSource = fs.readFileSync(path.join(sourceRoot, 'airplay/AirPlayMediaSession.ets'), 'utf8');
  const featureBlock = /const CONTROLLER_FEATURES:\s*string\[\]\s*=\s*\[([\s\S]*?)\];/.exec(sessionSource);
  assert.ok(featureBlock);
  const controllerFeatures = Array.from(featureBlock[1].matchAll(/'([^']+)'/g), match => match[1]);
  const expectedFeatures = [
    'uiContext', 'viewAreas', 'cornerMasks', 'focusTransfer', 'h.264Level5.1', 'mainBuffered',
    'altScreen', 'enhancedSiri', 'hevc', 'sessionManagement', 'logTransfer', 'iAPChannel',
    'vehicleStateProtocol', 'videoPlayback'
  ];
  assert.deepEqual(controllerFeatures, expectedFeatures);
  const sessionSetup = loadMethods('airplay/AirPlayMediaSession.ets', 'AirPlayMediaSession',
    ['buildSessionSetupPayload'], {
      BinaryPlist,
      PlistNode,
      CONTROLLER_FEATURES: controllerFeatures,
      CARPLAY_SENDER_MAC_ADDRESS: 'aa:bb:cc:dd:ee:ff',
      CARPLAY_SENDER_OS_BUILD_VERSION: 'test-build',
      CARPLAY_SENDER_SOURCE_VERSION: 'test-version',
      createUuid: () => 'test-uuid',
      normalizeDeviceId: value => value
    });
  const session = BinaryPlist.decode(sessionSetup.buildSessionSetupPayload('AA:BB:CC:DD:EE:FF', 7000));
  assert.equal(session.get('features').kind, 'array');
  assert.deepEqual(session.get('features').arrayValue.map(feature => feature.stringValue), expectedFeatures);
  assert.equal(session.get('deviceID').stringValue, 'AA:BB:CC:DD:EE:FF');
  assert.equal(session.get('macAddress').stringValue, 'aa:bb:cc:dd:ee:ff');
  assert.equal(session.get('name').stringValue, 'iPhone');
  assert.equal(session.get('model').stringValue, 'iPhone14,2');
  assert.equal(session.get('osName').stringValue, 'iPhone OS');
  assert.equal(session.get('osVersion').stringValue, '15.0.2');
  assert.equal(session.get('osBuildVersion').stringValue, 'test-build');
  assert.equal(session.get('sessionUUID').stringValue, 'TEST-UUID');
  assert.equal(session.get('sessionCorrelationUUID').stringValue, 'TEST-UUID');
  assert.equal(session.get('timingPort').integerValue, 7000n);
});

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
  assert.equal(writes.length, 0);
  archive.flush();
  assert.equal(writes.length, 1);
  assert.equal(fsyncCount, 1);
  archive.appendFromAbility('C:\\logs', 'projection', 'current ability event');
  assert.ok(contents.get(currentLog).includes('current ability event'));
  assert.ok(contents.get(currentLog).includes('packet one'));
  const exported = archive.readAllText();
  assert.ok(exported.indexOf('packet one') < exported.indexOf('packet two'));
  assert.ok(exported.includes('current ability event'));
  assert.doesNotMatch(exported, /previous run/);
  const recent = archive.readRecentLines().join('\n');
  assert.ok(recent.includes('current app session'));
  assert.ok(recent.includes('current ability event'));
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

test('audio and video packet diagnostics cover every send without logging media payloads', async () => {
  const formatEvent = (event, ...fields) => {
    const values = {};
    for (let index = 0; index + 1 < fields.length; index += 2) values[fields[index]] = fields[index + 1];
    return JSON.stringify({ event, ...values });
  };
  const concatBytes = (...parts) => {
    const result = new Uint8Array(parts.reduce((length, part) => length + part.length, 0));
    let offset = 0;
    for (const part of parts) { result.set(part, offset); offset += part.length; }
    return result;
  };

  const AudioTarget = loadMethods('audio/AudioRtpSender.ets', 'AudioRtpSender', ['sendPacket'], {
    buildAudioRtpHeader: () => new Uint8Array(12),
    nonce64: () => new Uint8Array(12),
    advanceAudioRtpTimestamp: (timestamp, packets) => (timestamp + packets * 352) >>> 0,
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
  audio.log = line => audioLogs.push(line);
  for (let index = 0; index < 4; index++) await audio.sendPacket(new Uint8Array([0xaa, 0xbb]));
  assert.equal(audioLogs.length, 8);
  assert.deepEqual(audioLogs.filter(line => line.includes('airplay.audio.rtp.tx'))
    .map(line => JSON.parse(line).packet), [1, 2, 3, 4]);
  assert.ok(audioLogs.every(line => !line.includes('aa bb')));
  assert.ok(audioLogs[1].includes('载荷未写入日志'));

  const VideoTarget = loadMethods('airplay/AirPlayVideoStream.ets', 'AirPlayVideoStreamSender', ['sendFrame'], {
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
    .map(line => JSON.parse(line).frame), [1, 2, 3, 4]);
  assert.ok(videoLogs[0].includes('"keyFrame":true'));
  assert.ok(videoLogs[1].includes('载荷未写入日志'));
});

test('wireless iAP2 groups parse credentials and retain untrusted UUID identities', () => {
  const concatBytes = (...parts) => {
    const result = new Uint8Array(parts.reduce((length, part) => length + part.length, 0));
    let offset = 0;
    for (const part of parts) {
      result.set(part, offset);
      offset += part.length;
    }
    return result;
  };
  const encodeParameter = (id, value) => {
    const result = new Uint8Array(value.length + 4);
    result[0] = result.length >>> 8;
    result[1] = result.length & 0xff;
    result[2] = id >>> 8;
    result[3] = id & 0xff;
    result.set(value, 4);
    return result;
  };
  const decodeParameters = bytes => {
    const entries = [];
    for (let offset = 0; offset < bytes.length;) {
      const length = (bytes[offset] << 8) | bytes[offset + 1];
      assert.ok(length >= 4 && offset + length <= bytes.length);
      entries.push({
        id: (bytes[offset + 2] << 8) | bytes[offset + 3],
        value: bytes.slice(offset + 4, offset + length)
      });
      offset += length;
    }
    return entries;
  };
  const decodeString = bytes => new TextDecoder().decode(bytes).replace(/\0.*$/s, '');
  const encodeString = (id, text) => encodeParameter(id, new TextEncoder().encode(`${text}\0`));
  const encodeNumber = (id, number, width) => {
    const value = new Uint8Array(width);
    for (let index = width - 1; index >= 0; index--) {
      value[index] = number & 0xff;
      number >>>= 8;
    }
    return encodeParameter(id, value);
  };
  const codec = {
    concatBytes,
    decodeIap2Parameters: decodeParameters,
    decodeIap2String: decodeString,
    encodeUtf8: text => new TextEncoder().encode(text),
    encodeIap2Control: () => new Uint8Array(0),
    encodeIap2LinkFrame: () => new Uint8Array(0),
    formatIap2MessageDiagnostic: () => '',
    formatIap2RawFrameDiagnostic: () => '',
    Iap2ControlDecoder: class {},
    Iap2LinkDecoder: class {},
    numberParameter: encodeNumber,
    stringParameter: encodeString
  };
  const session = loadEts('session/Iap2SenderSession.ets', {
    '../protocol/Iap2Codec': codec,
    '@ohos.security.cryptoFramework': {},
    '@ohos.i18n': { System: { getSystemLanguage: () => 'zh-Hans' } },
    '../iap2/MfiVerifier': { MfiVerifier: class {} },
    './ProtocolLogger': { formatProtocolEvent: () => '', formatRawBytesDiagnostic: () => '' }
  });
  const credentials = session.parseWirelessSessionCredentials(encodeParameter(1, concatBytes(
    encodeString(0, 'DIRECT-test-group'),
    encodeString(1, 'test-passphrase'),
    encodeNumber(2, 44, 1),
    encodeString(3, '192.168.49.1'),
    encodeNumber(4, 2, 1)
  )));
  assert.deepEqual(credentials, {
    ssid: 'DIRECT-test-group',
    password: 'test-passphrase',
    channel: 44,
    securityType: 2
  });
  const identity = '24e3089a-b9c8-4998-beb2-ae9120b44053';
  const endpoint = session.parseWirelessSessionEndpoint(concatBytes(
    encodeParameter(1, encodeString(3, 'fe80::1')),
    encodeNumber(2, 7000, 4),
    encodeString(3, 'AA:BB:CC:DD:EE:FF'),
    encodeString(4, identity),
    encodeString(5, 'test-version')
  ));
  assert.equal(endpoint.port, 7000);
  assert.deepEqual(endpoint.addresses, ['fe80::1']);
  assert.equal(endpoint.publicKey, '');
  assert.equal(endpoint.unrecognizedIdentity, identity);
});

test('raw iAP2 diagnostics mask MFi and wireless secrets with and without the detection marker', () => {
  const util = {
    TextEncoder: { create: () => ({ encodeInto: text => new TextEncoder().encode(text) }) },
    TextDecoder: { create: () => ({ decodeToString: bytes => new TextDecoder().decode(bytes) }) }
  };
  const { formatIap2RawFrameDiagnostic } = loadEts('protocol/Iap2Codec.ets', {
    '@ohos.util': util,
    'libiap2codec.so': {}
  });
  const concatBytes = (...parts) => {
    const result = new Uint8Array(parts.reduce((length, part) => length + part.length, 0));
    let offset = 0;
    for (const part of parts) {
      result.set(part, offset);
      offset += part.length;
    }
    return result;
  };
  const parameter = (id, value) => {
    const result = new Uint8Array(value.length + 4);
    result[0] = result.length >>> 8;
    result[1] = result.length & 0xff;
    result[2] = id >>> 8;
    result[3] = id & 0xff;
    result.set(value, 4);
    return result;
  };
  const frame = (messageId, body) => {
    const payload = concatBytes(
      new Uint8Array([0x40, 0x40, 0, body.length + 6, messageId >>> 8, messageId & 0xff]),
      body
    );
    const raw = new Uint8Array(10 + payload.length);
    raw.set([0xff, 0x5a, 0, raw.length, 0x40, 0, 0, 1, 0], 0);
    raw.set(payload, 9);
    return { control: 0x40, sequence: 0, acknowledgement: 0, sessionId: 1, payload, raw };
  };
  const challenge = new Uint8Array([0x11, 0x22, 0x33, 0x44]);
  const wifiPassword = new TextEncoder().encode('private-wifi-password');
  const authOutput = formatIap2RawFrameDiagnostic('TX',
    frame(0xaa02, parameter(0, challenge)), true);
  const wifiOutput = formatIap2RawFrameDiagnostic('TX',
    frame(0x5703, parameter(2, wifiPassword)));
  const wirelessOutput = formatIap2RawFrameDiagnostic('RX',
    frame(0x4301, parameter(1, parameter(1, wifiPassword))));
  for (const output of [authOutput, wifiOutput, wirelessOutput]) {
    assert.match(output, /\*\*/);
    assert.doesNotMatch(output, /11 22 33 44|70 72 69 76 61 74 65/);
  }
});

test('night mode received before UI setup is replayed, type checked and restricted to command requests', () => {
  const { PlistNode } = loadEts('airplay/BinaryPlist.ets', {
    '@ohos.util': {}, '../protocol/Iap2Codec': {}
  });
  const source = fs.readFileSync(path.join(sourceRoot, 'airplay/AirPlayMediaSession.ets'), 'utf8');
  const parsed = ts.createSourceFile('AirPlayMediaSession.ts', source, ts.ScriptTarget.Latest, true);
  const declaration = parsed.statements.find(statement =>
    ts.isClassDeclaration(statement) && statement.name?.text === 'AirPlayMediaSession');
  const methods = declaration.members.filter(member =>
    ['handleEventRequest', 'setNightModeHandler'].includes(member.name?.text));
  const javascript = ts.transpileModule(`class Target { ${methods.map(method => method.getText(parsed)).join('\n')} }`, {
    compilerOptions: { target: ts.ScriptTarget.ES2020 }
  }).outputText;
  let command;
  const Target = vm.runInNewContext(`${javascript}\nTarget`, {
    BinaryPlist: { decode: () => command }, extractCarPlayTouchReport: () => undefined,
    isForceKeyFrameCommand: () => false
  });
  const target = new Target();
  const logs = [];
  target.log = line => logs.push(line);
  const request = { method: 'POST', target: '/command', cseq: 1, body: new Uint8Array([1]) };
  const nightCommand = value => PlistNode.dictionary(new Map([
    ['type', PlistNode.string('setNightMode')],
    ['params', PlistNode.dictionary(new Map([['nightMode', value]]))]
  ]));
  command = nightCommand(PlistNode.boolean(true));
  target.handleEventRequest(request);
  const changes = [];
  target.setNightModeHandler(value => changes.push(value));
  assert.deepEqual(changes, [true]);
  command = nightCommand(PlistNode.string('false'));
  target.handleEventRequest(request);
  assert.deepEqual(changes, [true]);
  assert.ok(logs.some(line => line.includes('requires params.nightMode Boolean')));
  command = nightCommand(PlistNode.boolean(false));
  target.handleEventRequest({ ...request, method: 'GET' });
  assert.deepEqual(changes, [true]);
  target.handleEventRequest(request);
  assert.deepEqual(changes, [true, false]);
  target.setNightModeHandler(undefined);
});

test('vehicle overlays work while unverified third-party launch requests stay disabled', () => {
  const source = fs.readFileSync(path.join(sourceRoot, 'pages/ProjectionDashboard.ets'), 'utf8');
  const parsed = ts.createSourceFile('ProjectionDashboard.ts',
    source.replace('struct ProjectionDashboard {', 'class ProjectionDashboard {'), ts.ScriptTarget.Latest, true);
  const declaration = parsed.statements.find(statement =>
    ts.isClassDeclaration(statement) && statement.name?.text === 'ProjectionDashboard');
  const methods = declaration.members.filter(member =>
    ['selectApp', 'showDashboardView', 'setNavigationPreview'].includes(member.name?.text));
  const javascript = ts.transpileModule(`class Target { ${methods.map(method => method.getText(parsed)).join('\n')} }`, {
    compilerOptions: { target: ts.ScriptTarget.ES2020 }
  }).outputText;
  const stored = new Map();
  const Target = vm.runInNewContext(`${javascript}\nTarget`, {
    AppStorage: {
      setOrCreate: (name, value) => stored.set(name, value),
      get: key => stored.get(key)
    },
    HOME_APP: { appId: 'shell-home', uri: 'carplay-client://v1/shell/home', category: 'home' },
    isProjectionAppLaunchable: () => false
  });
  const target = new Target();
  target.touchBounds = new Map();
  target.showDockActionMessage = () => {};
  target.onHomeClick = () => { throw new Error('must not release an existing app for a vehicle page'); };
  target.showDashboardView('apps');
  assert.equal(stored.get('carplayDashboardView'), 'apps');
  target.selectApp({ category: 'vehicle', view: 'themes' });
  assert.equal(target.dashboardView, 'themes');
  assert.equal(stored.get('carplayDashboardView'), 'themes');
  let opened;
  target.onAppClick = app => { opened = app.uri; };
  target.selectApp({
    appId: 'huawei-music',
    uri: 'carplay-client://v1/apps/huawei-music/launch',
    launchState: 'UNVERIFIED',
    unavailableReason: '入口尚未验证',
    category: 'music'
  });
  assert.equal(opened, undefined);
  assert.equal(target.appDiscoveryMessage, '入口尚未验证');
  assert.equal(stored.get('carplayDashboardView'), 'themes');
});

test('active media sessions are not treated as verified app launch targets', () => {
  const { includeMediaSessionApp } = loadEts('pages/ProjectionAppCatalog.ets');
  const apps = includeMediaSessionApp([], 'com.huawei.hmsapp.music', 'MainAbility');
  assert.equal(apps[0].label, '\u5f53\u524d\u64ad\u653e\u5668');
  assert.equal(apps[0].bundleName, 'com.huawei.hmsapp.music');
  assert.equal(apps[0].abilityName, 'MainAbility');
  assert.equal(apps[0].launchState, 'UNVERIFIED');
  assert.equal(apps[0].launchTarget, undefined);
  assert.equal(includeMediaSessionApp(apps, 'com.huawei.hmsapp.music', 'MainAbility').length, 1);
});

function audioSenderFixture() {
  const sent = [];
  const encrypted = [];
  const socket = { async bind() {}, async close() {}, async send(options) { sent.push(options); } };
  const codec = {
    concatBytes(...parts) {
      const result = new Uint8Array(parts.reduce((total, part) => total + part.length, 0));
      let offset = 0;
      for (const part of parts) { result.set(part, offset); offset += part.length; }
      return result;
    },
    toArrayBuffer(data) { return data.slice().buffer; }
  };
  const { AudioRtpSender } = loadEts('audio/AudioRtpSender.ets', {
    '../network/SocketDeadline': loadEts('network/SocketDeadline.ets'),
    '@ohos.net.socket': { constructUDPSocketInstance: () => socket },
    '../crypto/MediaPacketCipher': {
      MediaPacketCipher: class {
      async seal(nonce, data, aad) {
        encrypted.push({ nonce: nonce.slice(), data: data.slice(), aad: aad.slice() });
        return codec.concatBytes(data, new Uint8Array(16));
      }
      }
    },
    '../network/WifiNetworkLease': {
      getSocketAddressFamily: () => 1,
      WifiNetworkLease: class {}
    },
    '../protocol/Iap2Codec': codec,
    '../session/ProtocolLogger': { formatProtocolEvent: () => '' },
    './AudioPcm': { swapPcmS16(data) {
      const result = data.slice();
      for (let offset = 0; offset < result.length; offset += 2) {
        result[offset] = data[offset + 1]; result[offset + 1] = data[offset];
      }
      return result;
    } }
  });
  const sender = new AudioRtpSender(() => {}, message => { throw new Error(message); });
  const session = { host: '127.0.0.1', dataPort: 7001, controlPort: 0,
    streamKey: new Uint8Array(32), sampleRate: 48000 };
  return { sender, session, sent, encrypted };
}

function loadEts(relativePath, imports = {}, selectFunction) {
  const filename = path.join(sourceRoot, relativePath);
  let source = fs.readFileSync(filename, 'utf8');
  if (selectFunction) {
    const parsed = ts.createSourceFile(filename, source, ts.ScriptTarget.Latest, true);
    const declaration = parsed.statements.find(statement =>
      ts.isFunctionDeclaration(statement) && statement.name?.text === selectFunction);
    assert.ok(declaration, `Missing function ${selectFunction}`);
    source = `${declaration.getText(parsed)}\nexports.${selectFunction} = ${selectFunction};`;
  }
  const result = ts.transpileModule(source, {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
  });
  const exports = {};
  const requireMock = name => {
    assert.ok(Object.hasOwn(imports, name), `Unexpected import ${name}`);
    return { __esModule: true, default: imports[name], ...imports[name] };
  };
  const execute = vm.runInThisContext(`(function(exports, require) { ${result.outputText}\n})`, { filename });
  execute(exports, requireMock);
  return exports;
}

function loadMethods(relativePath, className, names, globals = {}) {
  const source = fs.readFileSync(path.join(sourceRoot, relativePath), 'utf8');
  const parsed = ts.createSourceFile(relativePath,
    source.replace(`struct ${className} {`, `class ${className} {`), ts.ScriptTarget.Latest, true);
  const declaration = parsed.statements.find(statement =>
    ts.isClassDeclaration(statement) && statement.name?.text === className);
  assert.ok(declaration, `Missing class ${className}`);
  const methods = declaration.members.filter(member => names.includes(member.name?.text));
  assert.equal(methods.length, names.length);
  const javascript = ts.transpileModule(`class Target { ${methods.map(method => method.getText(parsed)).join('\n')} }`, {
    compilerOptions: { target: ts.ScriptTarget.ES2020 }
  }).outputText;
  return vm.runInNewContext(`${javascript}\nTarget`, globals);
}

test('an active media session does not imply a verified app launch target', () => {
  const { includeMediaSessionApp } = loadEts('pages/ProjectionAppCatalog.ets');
  const maps = [{ appId: 'amap', uri: 'carplay-client://v1/apps/amap/launch', category: 'map' }];
  const apps = includeMediaSessionApp(maps, 'com.huawei.hmsapp.music', 'MainAbility');
  assert.equal(apps.length, 2);
  assert.equal(apps[1].category, 'music');
  assert.equal(apps[1].bundleName, 'com.huawei.hmsapp.music');
  assert.equal(apps[1].abilityName, 'MainAbility');
  assert.equal(apps[1].launchState, 'UNVERIFIED');
  assert.equal(apps[1].launchTarget, undefined);
  assert.equal(includeMediaSessionApp(apps, 'com.huawei.hmsapp.music', 'MainAbility').length, 2);
  assert.equal(includeMediaSessionApp(apps), apps);
  assert.equal(maps.length, 1);
});

test('all HID reports in a TCP read are dispatched before awaiting any response write', async () => {
  const filename = path.join(sourceRoot, 'airplay/AirPlayEventChannel.ets');
  const source = fs.readFileSync(filename, 'utf8');
  const parsed = ts.createSourceFile(filename, source, ts.ScriptTarget.Latest, true);
  const declaration = parsed.statements.find(statement =>
    ts.isClassDeclaration(statement) && statement.name.text === 'AirPlayEventChannel');
  const method = declaration.members.find(member => member.name?.getText(parsed) === 'handleIncoming');
  const result = ts.transpileModule(`class Channel { ${method.getText(parsed)} } exports.Channel = Channel;`, {
    compilerOptions: { target: ts.ScriptTarget.ES2020, module: ts.ModuleKind.CommonJS }
  });
  const requests = [1, 2, 3].map(cseq => ({
    method: 'POST',
    target: '/command',
    cseq,
    body: new Uint8Array(0)
  }));
  const exports = {};
  vm.runInThisContext(`(function(exports, concatBytes, parseAirPlayEventRequests, buildAirPlayEventResponse,
    formatProtocolEvent, formatEventBodySummary) {
    ${result.outputText}
  })`)(exports, (...parts) => Uint8Array.from(parts.flatMap(part => [...part])),
    () => ({ requests, remaining: new Uint8Array(0) }), cseq => new Uint8Array([cseq]),
    (event, ...fields) => JSON.stringify({ event, fields }), () => 'empty body');
  const channel = new exports.Channel();
  channel.running = true;
  channel.receiveBuffer = new Uint8Array(0);
  channel.cipher = { async decrypt(data) { return data; } };
  channel.log = () => {};
  channel.logQueueDelay = () => {};
  channel.logProcessingDelay = () => {};
  channel.hidReportSummary = { record: () => 1 };
  const handled = [];
  channel.onRequest = request => { handled.push(request.cseq); return true; };
  let release;
  let writes = 0;
  const gate = new Promise(resolve => { release = resolve; });
  channel.sendPlaintext = async bytes => {
    writes++;
    assert.deepEqual(handled, [1, 2, 3]);
    assert.deepEqual([...bytes], [1, 2, 3]);
    await gate;
  };
  const operation = channel.handleIncoming(new Uint8Array([0]), Date.now());
  await Promise.resolve();
  assert.deepEqual(handled, [1, 2, 3]);
  release();
  await operation;
  assert.equal(writes, 1);
});

test('authenticated start endpoints do not depend on the optional reverse probe', () => {
  const { isAirPlayStartReady } = loadEts('session/SessionController.ets', {}, 'isAirPlayStartReady');
  assert.equal(isAirPlayStartReady(true, false, true), true);
  assert.equal(isAirPlayStartReady(true, true, false), true);
  assert.equal(isAirPlayStartReady(false, true, true), false);
  assert.equal(isAirPlayStartReady(true, false, false), false);
});

test('wireless startup keeps address candidates without treating UUID identities as public keys', () => {
  const source = fs.readFileSync(path.join(sourceRoot, 'session/Iap2SenderSession.ets'), 'utf8');
  const parsed = ts.createSourceFile('Iap2SenderSession.ts', source, ts.ScriptTarget.Latest, true);
  const declaration = parsed.statements.find(statement =>
    ts.isFunctionDeclaration(statement) && statement.name?.text === 'parseWirelessSessionEndpoint');
  const javascript = ts.transpileModule(declaration.getText(parsed), {
    compilerOptions: { target: ts.ScriptTarget.ES2020, module: ts.ModuleKind.CommonJS }
  }).outputText;
  const body = new Uint8Array([1]);
  const group = new Uint8Array([2]);
  const encode = value => new TextEncoder().encode(value + '\0');
  const fields = [
    { id: 1, value: group }, { id: 2, value: new Uint8Array([0, 0, 0x1b, 0x58]) },
    { id: 3, value: encode('EC:D9:09:40:7A:49') },
    { id: 4, value: encode('24e3089a-b9c8-4998-beb2-ae9120b44053') },
    { id: 5, value: encode('450.14') }
  ];
  const exports = {};
  vm.runInNewContext(javascript, {
    exports, Uint8Array,
    decodeIap2Parameters: bytes => bytes === body ? fields : [
      { id: 3, value: encode('fe80::1899:7bff:fe39:e165') },
      { id: 3, value: encode('192.168.49.1') }
    ],
    decodeIap2String: bytes => new TextDecoder().decode(bytes).replace(/\0.*$/s, '')
  });
  const parse = exports.parseWirelessSessionEndpoint;
  const candidate = parse(body);
  assert.equal(candidate.port, 7000);
  assert.deepEqual([...candidate.addresses], ['fe80::1899:7bff:fe39:e165', '192.168.49.1']);
  assert.equal(candidate.publicKey, '');
  assert.equal(candidate.unrecognizedIdentity, '24e3089a-b9c8-4998-beb2-ae9120b44053');
  fields[3].value = encode('a'.repeat(64));
  assert.equal(parse(body).publicKey, 'a'.repeat(64));
  assert.equal(parse(body).unrecognizedIdentity, undefined);
  fields[1].value = new Uint8Array([0x1b, 0x58]);
  assert.equal(parse(body), undefined);
  fields[1].value = new Uint8Array(4);
  assert.equal(parse(body), undefined);
});

test('wireless startup invitation survives missing endpoint metadata and control advertisement', async () => {
  const Target = loadMethods('session/SessionController.ets', 'SessionController',
    ['handleIap2AirPlayEndpoint', 'startControlAdvertisement'], {
      CarPlayCtrlAdvertiser: class {
        async start() {}
      }
    });
  const target = new Target();
  let connections = 0;
  target.running = true;
  target.events = { onLog() {}, onAirPlayService() {} };
  target.refreshDiscoveredAirPlay = () => {};
  target.discoveredAirPlay = { host: '192.168.49.1', port: 7000 };
  target.connectAirPlay = async () => { connections++; };
  target.handleIap2AirPlayEndpoint(undefined);
  assert.equal(target.inviteReceived, true);
  assert.equal(connections, 1);
  await target.startControlAdvertisement();
  assert.equal(target.inviteReceived, true);
  assert.equal(connections, 2);
  target.inviteReceived = false;
  target.running = false;
  target.handleIap2AirPlayEndpoint(undefined);
  assert.equal(target.inviteReceived, false);
});

test('wireless startup availability waits without arming a start-request deadline', async () => {
  const Target = loadMethods('session/Iap2SenderSession.ets', 'Iap2SenderSession',
    ['requestWifiConfiguration'], {
      MESSAGE: { CARPLAY_AVAILABILITY: 0x4300, CARPLAY_START_SESSION: 0x4301 },
      shouldProbeLegacyWifi: () => false
    });
  const target = new Target();
  target.accessorySendMessages = [0x4301];
  target.accessoryReceiveMessages = [0x4300];
  target.log = () => {};
  let announcements = 0;
  target.sendDeviceAnnouncement = async () => { announcements++; };
  target.startWifiConfigurationTimer = () => { throw new Error('must wait for a start request'); };
  await target.requestWifiConfiguration();
  assert.equal(announcements, 1);
});

test('wireless startup never publishes an unknown identity as a pairing public key', () => {
  const { makeAirPlayServiceFromEndpoint } = loadEts('session/SessionController.ets', {},
    'makeAirPlayServiceFromEndpoint');
  const endpoint = { addresses: ['192.168.49.1'], port: 7000, deviceIdentifier: 'AA:BB:CC:DD:EE:FF',
    publicKey: '', unrecognizedIdentity: '24e3089a-b9c8-4998-beb2-ae9120b44053', sourceVersion: '450.14' };
  assert.equal(Object.hasOwn(makeAirPlayServiceFromEndpoint(endpoint).txt, 'pk'), false);
  endpoint.publicKey = 'a'.repeat(64);
  assert.equal(makeAirPlayServiceFromEndpoint(endpoint).txt.pk, 'a'.repeat(64));
});

test('wireless startup candidates wait for matching mDNS keys and still reject key conflicts', () => {
  const { makeAirPlayServiceFromEndpoint } = loadEts('session/SessionController.ets', {},
    'makeAirPlayServiceFromEndpoint');
  const { normalizeDeviceIdentifier } = loadEts('session/SessionController.ets', {},
    'normalizeDeviceIdentifier');
  const { correlateAirPlayIdentity } = loadEts('network/AirPlayIdentityCorrelation.ets');
  const Target = loadMethods('session/SessionController.ets', 'SessionController',
    ['refreshDiscoveredAirPlay'], { makeAirPlayServiceFromEndpoint, normalizeDeviceIdentifier,
      correlateAirPlayIdentity });
  const target = new Target();
  target.events = { onLog() {} };
  target.iap2AirPlayEndpoint = { addresses: ['fe80::1'], port: 7000,
    deviceIdentifier: 'AA:BB:CC:DD:EE:FF', publicKey: '', sourceVersion: '450.14' };
  target.refreshDiscoveredAirPlay();
  assert.equal(target.discoveredAirPlay, undefined);
  target.mdnsAirPlayService = { host: '192.168.49.1', port: 7000, name: 'receiver',
    txt: { deviceid: 'AA:BB:CC:DD:EE:FF' } };
  target.refreshDiscoveredAirPlay();
  assert.equal(target.discoveredAirPlay, undefined);
  target.mdnsAirPlayService.txt.pk = 'a'.repeat(64);
  target.refreshDiscoveredAirPlay();
  assert.equal(target.discoveredAirPlay.txt.pk, 'a'.repeat(64));
  target.mdnsAirPlayService.txt.deviceid = '11:22:33:44:55:66';
  target.refreshDiscoveredAirPlay();
  assert.equal(target.discoveredAirPlay, undefined);
  target.iap2AirPlayEndpoint.publicKey = 'b'.repeat(64);
  target.mdnsAirPlayService.txt.deviceid = 'AA:BB:CC:DD:EE:FF';
  let rejected = false;
  target.rejectAirPlayIdentityConflict = () => { rejected = true; };
  target.refreshDiscoveredAirPlay();
  assert.equal(rejected, true);
});

test('wireless startup rejects malformed and unauthenticated start requests', async () => {
  let valid = false;
  const Target = loadMethods('session/Iap2SenderSession.ets', 'Iap2SenderSession',
    ['receiveControlMessage'], {
      MESSAGE: { CARPLAY_START_SESSION: 0x4301 },
      formatIap2MessageDiagnostic: () => '',
      decodeIap2Parameters: () => { if (!valid) throw new Error('invalid length'); return []; },
      parseWirelessSessionCredentials: () => undefined,
      parseWirelessSessionEndpoint: () => undefined
    });
  const target = new Target();
  target.log = () => {};
  target.authenticated = true;
  target.errorDetails = error => error.message;
  target.hasValidDeviceAddress = () => true;
  target.sendTransportIdentifier = async () => {};
  let invitations = 0;
  target.onEndpoint = () => { invitations++; };
  await target.receiveControlMessage(0x4301, new Uint8Array([0]));
  assert.equal(invitations, 0);
  valid = true;
  target.authenticated = false;
  await target.receiveControlMessage(0x4301, new Uint8Array(0));
  assert.equal(invitations, 0);
  target.authenticated = true;
  await target.receiveControlMessage(0x4301, new Uint8Array(0));
  assert.equal(invitations, 1);
});

test('wireless WLAN selection reuses the matching local network without requiring internet', async () => {
  const handlers = {};
  const cellular = { netId: 1 };
  const otherWifi = { netId: 2 };
  let bound = 0;
  const socketEvents = [];
  const vehicleWifi = { netId: 3, async bindSocket() { socketEvents.push('network-bind'); bound++; } };
  let unregistered = 0;
  const { WifiNetworkLease } = loadEts('network/WifiNetworkLease.ets', {
    '@ohos.net.connection': {
      NetBearType: { BEARER_WIFI: 1 },
      async getAllNets() { return [cellular, otherWifi, vehicleWifi]; },
      async getNetCapabilities(handle) { return { bearerTypes: [handle.netId === 1 ? 0 : 1] }; },
      async getConnectionProperties(handle) {
        return { linkAddresses: [
          { address: { address: handle.netId === 3 ? '10.36.232.67' : '192.168.1.2' } },
          ...(handle.netId === 3 ? [{ address: { address: 'fe80::3' } }] : [])
        ] };
      },
      createNetConnection(specifier, timeout) {
        assert.equal(specifier.bearerPrivateIdentifier, undefined);
        assert.equal(timeout, 5000);
        return { on(name, handler) { handlers[name] = handler; },
          register(callback) { callback(); }, unregister(callback) { unregistered++; callback(); } };
      }
    }
  });
  const lease = new WifiNetworkLease();
  let lost = false;
  assert.equal((await lease.acquire('BUICK_7841', () => { lost = true; }, () => {}, '10.36.232.67')).netId, 3);
  await lease.bindSocket({ async bind(address) {
    socketEvents.push('socket-bind');
    assert.deepEqual(address, { address: '10.36.232.67', family: 1, port: 0 });
  } }, 'test IPv4 TCP');
  await lease.bindSocket({ async bind(address) {
    assert.deepEqual(address, { address: 'fe80::3', family: 2, port: 0 });
  } }, 'test IPv6 TCP', 2);
  assert.deepEqual(socketEvents, ['socket-bind', 'network-bind', 'network-bind']);
  assert.equal(bound, 2);
  handlers.netLost(vehicleWifi);
  assert.equal(lost, true);
  await assert.rejects(lease.bindSocket({}), /默认路由/);
  await lease.release();
  assert.equal(unregistered, 1);
});

test('wireless WLAN selection cancels pending acquisition and ignores late availability', async () => {
  const handlers = {};
  let registered = false;
  let unregistered = 0;
  const { WifiNetworkLease } = loadEts('network/WifiNetworkLease.ets', {
    '@ohos.net.connection': {
      NetBearType: { BEARER_WIFI: 1 },
      async getAllNets() { return []; },
      async getNetCapabilities() { return { bearerTypes: [1] }; },
      async getConnectionProperties() { return { linkAddresses: [{ address: { address: '10.36.232.67' } }] }; },
      createNetConnection() { return {
        on(name, handler) { handlers[name] = handler; },
        register(callback) { registered = true; callback(); },
        unregister(callback) { unregistered++; callback(); }
      }; }
    }
  });
  const lease = new WifiNetworkLease();
  const acquiring = lease.acquire('BUICK_7841', () => {}, () => {}, '10.36.232.67');
  const rejected = assert.rejects(acquiring, /取消/);
  for (let turn = 0; turn < 20; turn++) await Promise.resolve();
  assert.equal(registered, true);
  await lease.release();
  await rejected;
  handlers.netAvailable({ netId: 3 });
  for (let turn = 0; turn < 10; turn++) await Promise.resolve();
  await assert.rejects(lease.bindSocket({}), /默认路由/);
  assert.equal(unregistered, 1);
});

test('wireless discovery starts before network selection but pairing waits for the selected WLAN', async () => {
  const Target = loadMethods('session/SessionController.ets', 'SessionController', ['joinVehicleWifi']);
  const target = new Target();
  const actions = [];
  target.running = true;
  target.deviceAddress = '40:06:34:E5:ED:EA';
  target.credentials = { ssid: 'BUICK_7841', password: 'test-password', securityType: 3, channel: 149 };
  target.iap2 = { isAuthenticationComplete: true, async onWifiConnected() { actions.push('iap2'); } };
  target.events = { onLog() {}, onStatus() {} };
  target.requestPermissions = async () => {};
  target.wifi = { async connect() { return { ssid: 'BUICK_7841', ipAddress: '10.36.232.67' }; } };
  target.startControlAdvertisement = async () => { actions.push('advertise'); };
  target.startAirPlayDiscovery = () => { actions.push('discovery'); };
  let finishNetwork;
  target.wifiNetworkLease = { acquire() {
    actions.push('network');
    return new Promise(resolve => { finishNetwork = resolve; });
  } };
  target.connectAirPlay = async () => { actions.push('pair'); };
  const joining = target.joinVehicleWifi();
  for (let turn = 0; turn < 20 && !finishNetwork; turn++) await Promise.resolve();
  assert.deepEqual(actions, ['iap2', 'advertise', 'discovery', 'network']);
  assert.notEqual(target.vehicleWifiConnected, true);
  finishNetwork({ netId: 3 });
  await joining;
  assert.equal(target.vehicleWifiConnected, true);
  assert.equal(actions.at(-1), 'pair');
  target.vehicleWifiConnected = false;
  target.wifiNetworkLease.acquire = async () => { throw new Error('no matching WLAN'); };
  await assert.rejects(target.joinVehicleWifi(), /无法确认 WLAN 选路/);
  assert.equal(target.vehicleWifiConnected, false);
  assert.equal(actions.filter(action => action === 'pair').length, 1);
});

test('shake switching ignores vibration, requires three pulses, and cools down', () => {
  const { ProjectionShakeDetector } = loadEts('video/ProjectionShakeDetector.ets');
  const detector = new ProjectionShakeDetector();
  assert.equal(detector.update(0, 0, 9.8, 0), false);
  assert.equal(detector.update(1, 0, 9.8, 100), false);
  assert.equal(detector.update(22, 0, 9.8, 200), false);
  assert.equal(detector.update(-22, 0, 9.8, 350), false);
  assert.equal(detector.update(22, 0, 9.8, 500), true);
  assert.equal(detector.update(-22, 0, 9.8, 650), false);
  assert.equal(detector.update(Number.NaN, 0, 0, 1000), false);
  assert.equal(detector.update(22, 0, 9.8, 3100), false);
  assert.equal(detector.update(-22, 0, 9.8, 3250), false);
  assert.equal(detector.update(22, 0, 9.8, 3400), true);
});

test('touch reports are routed to the CarPlayer shell without third-party injection', () => {
  const reports = loadEts('airplay/CarPlayTouchReport.ets');
  const { CarPlayTouchInput } = loadEts('video/CarPlayTouchInput.ets', {
    '@ohos.events.emitter': { emit() {} }, '../airplay/CarPlayTouchReport': reports
  });
  const taps = [];
  const routed = [];
  const input = new CarPlayTouchInput(tap => taps.push(tap), report => routed.push(report));
  input.start(42, 320, 240);
  input.handleReport(new Uint8Array([1, 100, 0, 50, 0]));
  input.handleReport(new Uint8Array([1, 105, 0, 55, 0]));
  input.handleReport(new Uint8Array([0, 0, 0, 0, 0]));
  assert.equal(routed.length, 3);
  assert.equal(taps.length, 1);
  assert.equal(taps[0].displayId, 42);
  assert.equal(taps[0].endX, 105);
  input.handleReport(new Uint8Array([1, 120, 0, 70, 0]));
  input.stop();
  assert.deepEqual(routed.at(-1), { displayId: 42, contacts: [] });
});

test('fallback touch preserves long press duration and rejects moved contacts', () => {
  const { CarPlayTouchInput } = loadEts('video/CarPlayTouchInput.ets', {
    '@ohos.events.emitter': { emit() {} },
    '../airplay/CarPlayTouchReport': loadEts('airplay/CarPlayTouchReport.ets')
  });
  const taps = [];
  const input = new CarPlayTouchInput(tap => taps.push(tap), () => {});
  input.start(7, 800, 480);
  input.handleReport(new Uint8Array([1, 100, 0, 50, 0]));
  input.startedAt = Date.now() - 1500;
  input.handleReport(new Uint8Array([0, 0, 0, 0, 0]));
  assert.equal(taps.length, 1);
  assert.ok(taps[0].durationMs >= 1500);
  input.handleReport(new Uint8Array([1, 100, 0, 50, 0]));
  input.handleReport(new Uint8Array([1, 150, 0, 50, 0]));
  input.startedAt = Date.now() - 1500;
  input.handleReport(new Uint8Array([0, 0, 0, 0, 0]));
  assert.equal(taps.length, 1);
  input.stop();
});

test('phone touch handling contains no third-party input injection fallback', () => {
  const source = fs.readFileSync(path.join(sourceRoot, 'session/SessionController.ets'), 'utf8');
  const input = fs.readFileSync(path.join(sourceRoot, 'video/CarPlayTouchInput.ets'), 'utf8');
  const module = fs.readFileSync(path.join(sourceRoot, '../module.json5'), 'utf8');
  assert.doesNotMatch(source, /injectProjectionTouch|injectTouchEvent|requestTouchInjection/);
  assert.doesNotMatch(input, /CarPlayTouchInjector|injectContacts|injectBackKey/);
  assert.doesNotMatch(module, /ohos\.permission\.CONTROL_DEVICE/);
});

test('navigation preview and full view share the running app without returning it to the phone', () => {
  const source = fs.readFileSync(path.join(sourceRoot, 'pages/ProjectionDashboard.ets'), 'utf8');
  const parsed = ts.createSourceFile('ProjectionDashboard.ts',
    source.replace('struct ProjectionDashboard {', 'class ProjectionDashboard {'), ts.ScriptTarget.Latest, true);
  const component = parsed.statements.find(statement =>
    ts.isClassDeclaration(statement) && statement.name?.text === 'ProjectionDashboard');
  const methods = component.members.filter(member =>
    ['selectApp', 'showHome', 'setNavigationPreview'].includes(member.name?.text));
  const javascript = ts.transpileModule(`class Target { ${methods.map(method => method.getText(parsed)).join('\n')} }`, {
    compilerOptions: { target: ts.ScriptTarget.ES2020 }
  }).outputText;
  const stored = new Map();
  const Target = vm.runInNewContext(`${javascript}\nTarget`, {
    AppStorage: {
      setOrCreate: (name, value) => stored.set(name, value),
      get: key => stored.get(key)
    },
    HOME_APP: { appId: 'shell-home', uri: 'carplay-client://v1/shell/home', category: 'home' },
    PROJECTION_MAP_URI: 'carplay-client://v1/apps/amap/launch'
  });
  const target = new Target();
  target.activeAppUri = 'carplay-client://v1/apps/amap/launch';
  target.activeAppLabel = 'Amap';
  target.onHomeClick = () => { throw new Error('must not release navigation on preview'); };
  target.onAppClick = () => { throw new Error('must not relaunch navigation on expansion'); };
  target.selectApp({ appId: 'shell-home', uri: 'carplay-client://v1/shell/home', category: 'home' });
  assert.equal(target.navigationPreview, true);
  assert.equal(stored.get('carplayNavigationPreview'), true);
  target.setNavigationPreview(false);
  assert.equal(stored.get('carplayNavigationPreview'), false);
  assert.equal((source.match(/id: 'projectionAppSurface'/g) || []).length, 1);
});

test('home selects a map preview and shows only navigation and AVSession music cards', async () => {
  const source = fs.readFileSync(path.join(sourceRoot, 'pages/ProjectionDashboard.ets'), 'utf8');
  const parsed = ts.createSourceFile('ProjectionDashboard.ts',
    source.replace('struct ProjectionDashboard {', 'class ProjectionDashboard {'), ts.ScriptTarget.Latest, true);
  const component = parsed.statements.find(statement =>
    ts.isClassDeclaration(statement) && statement.name?.text === 'ProjectionDashboard');
  const methods = component.members.filter(member =>
    ['selectApp', 'showHome', 'setNavigationPreview', 'discoverApps'].includes(member.name?.text));
  const javascript = ts.transpileModule(`class Target { ${methods.map(method => method.getText(parsed)).join('\n')} }`, {
    compilerOptions: { target: ts.ScriptTarget.ES2020 }
  }).outputText;
  const map = {
    appId: 'amap',
    uri: 'carplay-client://v1/apps/amap/launch',
    label: '高德地图',
    category: 'map',
    launchState: 'VERIFIED',
    launchTarget: { kind: 'appLink', uri: 'verified-amap-link' }
  };
  const stored = new Map();
  const Target = vm.runInNewContext(`${javascript}\nTarget`, {
    AppStorage: {
      setOrCreate: (name, value) => stored.set(name, value),
      get: key => stored.get(key)
    },
    HOME_APP: { appId: 'shell-home', uri: 'carplay-client://v1/shell/home', category: 'home' },
    PROJECTION_MAP_URI: map.uri,
    discoverProjectionApps: () => [map],
    projectionAppCatalog: () => [map],
    isProjectionAppLaunchable: app => app.launchState === 'VERIFIED' && !!app.launchTarget
  });
  const target = new Target();
  target.apps = [map];
  target.activeAppUri = 'hwmusic://com.huawei.hmsapp.music';
  target.activeAppLabel = 'Music';
  const opened = [];
  target.onAppClick = app => opened.push(app.uri);
  target.onHomeClick = () => { throw new Error('Home must retain the content display'); };
  target.selectApp({ appId: 'shell-home', uri: 'carplay-client://v1/shell/home', category: 'home' });
  assert.equal(target.navigationPreview, true);
  assert.deepEqual(opened, [map.uri]);
  target.activeAppUri = map.uri;
  target.selectApp({ appId: 'shell-home', uri: 'carplay-client://v1/shell/home', category: 'home' });
  assert.deepEqual(opened, [map.uri], 'returning from full map must not reopen it');
  target.activeAppUri = '';
  target.activeAppLabel = '';
  await target.discoverApps();
  assert.equal(stored.get('carplayNavigationPreview'), true);
  assert.deepEqual(opened, [map.uri, map.uri]);
  assert.match(source, /private DashboardSidebar\(\)/);
  for (const heading of ['\u97f3\u4e50', '\u5bfc\u822a']) {
    assert.ok(source.includes(heading), `missing home card ${heading}`);
  }
  assert.doesNotMatch(source, /天气数据暂不可用|app\.media\.ic_cloud_sun/);
  assert.doesNotMatch(source, /在手机打开地图/);
  assert.match(source, /this\.mediaState\.lyric/);
  assert.match(source, /this\.mediaProgressPercent\(\)/);
  assert.ok(!source.includes('this.navigationPreview ? 0.7'), 'preview uses actual layout, not a floating scaled page');
});

test('AVSession lyric metadata resolves the current LRC line at playback position', () => {
  const { resolveCurrentLyric } = loadEts('session/MediaSessionBridge.ets', {
    '@ohos.multimedia.avsession': {}
  });
  const lyric = '[offset:-500]\n[00:00.00]Intro\n[00:01.25][00:01.50]Chorus\n[00:02.00]Outro';
  assert.equal(resolveCurrentLyric(lyric, undefined, 100), 'Intro');
  assert.equal(resolveCurrentLyric(lyric, undefined, 900), 'Chorus');
  assert.equal(resolveCurrentLyric(lyric, 'live lyric', 0), 'live lyric');
  assert.equal(resolveCurrentLyric(undefined, undefined, 1000), '');
});

test('music discovers late sessions, publishes changes, controls and cleans up', async () => {
  let descriptors = [];
  let title = 'First track';
  let lyric = '[00:00.00]First line\n[00:02.00]Current line';
  let state = 1;
  let notifications = 0;
  let destroyed = 0;
  const commands = [];
  const listeners = new Map();
  const managerListeners = new Map();
  const controller = {
    on(name, ...args) { listeners.set(name, args.at(-1)); },
    off(name) { listeners.delete(name); },
    async getAVMetadata() { return { title, artist: 'Artist', lyric, duration: 120000 }; },
    async getAVPlaybackState() {
      return { state, duration: 120000, position: { elapsedTime: 2500, updateTime: Date.now() - 500 } };
    },
    async getValidCommands() { return ['play', 'pause', 'playNext', 'playPrevious']; },
    async getAVQueueItems() { return []; },
    async sendControlCommand(command) { commands.push(command.command); },
    async destroy() { destroyed++; }
  };
  const api = {
    PlaybackState: { PLAYBACK_STATE_PLAY: 1 },
    async getAllSessionDescriptors() { return descriptors; },
    async createController() { return controller; }
  };
  for (const event of ['SessionCreate', 'SessionDestroy', 'TopSessionChange']) {
    api[`on${event}`] = handler => managerListeners.set(event, handler);
    api[`off${event}`] = () => managerListeners.delete(event);
  }
  const { MediaSessionBridge } = loadEts('session/MediaSessionBridge.ets', { '@ohos.multimedia.avsession': api });
  const bridge = new MediaSessionBridge(() => notifications++);
  assert.equal((await bridge.refresh()).commands.length, 0);
  descriptors = [{ sessionId: 'music', type: 'audio', isTopSession: true, isActive: true,
    elementName: { bundleName: 'example.music', abilityName: 'MainAbility' } }];
  managerListeners.get('SessionCreate')();
  assert.equal(notifications, 1);
  const first = await bridge.refresh();
  assert.equal(first.title, 'First track');
  assert.equal(first.durationMs, 120000);
  assert.ok(first.positionMs >= 2500);
  assert.equal(first.lyric, 'Current line');
  title = 'Next track';
  listeners.get('metadataChange')();
  assert.equal((await bridge.refresh()).title, 'Next track');
  descriptors[0].isActive = false;
  state = 0;
  const paused = await bridge.refresh();
  assert.equal(paused.isPlaying, false);
  assert.equal(paused.positionMs, 2500, 'paused position must not advance from its last update timestamp');
  assert.equal(paused.bundleName, 'example.music');
  await bridge.send('play');
  assert.deepEqual(commands, ['play']);
  await bridge.close();
  assert.equal(destroyed, 1);
  assert.equal(listeners.size, 0);
  assert.equal(managerListeners.size, 0);
});

test('audio authorization is awaited and a cancelled start cannot reactivate capture', async () => {
  let authorize;
  let released = 0;
  let options;
  const capturer = {
    on() {}, off() {},
    requestPlaybackCaptureStart(callback) { authorize = callback; },
    async stop() {}, async release() { released++; }
  };
  const api = {
    AudioSamplingRate: { SAMPLE_RATE_44100: 44100, SAMPLE_RATE_48000: 48000 },
    AudioChannel: { CHANNEL_2: 2 }, AudioSampleFormat: { SAMPLE_FORMAT_S16LE: 1 },
    AudioEncodingType: { ENCODING_TYPE_RAW: 0 }, SourceType: { SOURCE_TYPE_PLAYBACK_CAPTURE: 2 },
    AudioPlaybackCaptureMode: { MODE_DEFAULT: 0 },
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
  const source = fs.readFileSync(path.join(sourceRoot, 'session/SessionController.ets'), 'utf8');
  const parsed = ts.createSourceFile('SessionController.ts', source, ts.ScriptTarget.Latest, true);
  const controller = parsed.statements.find(statement =>
    ts.isClassDeclaration(statement) && statement.name?.text === 'SessionController');
  const method = controller.members.find(member => member.name?.text === 'startAudio');
  const javascript = ts.transpileModule(`class Target { ${method.getText(parsed)} }`, {
    compilerOptions: { target: ts.ScriptTarget.ES2020 }
  }).outputText;
  for (const setting of [undefined, false, true, 'true']) {
    const calls = [];
    const logs = [];
    const Target = vm.runInNewContext(`${javascript}\nTarget`, {
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
  const source = fs.readFileSync(path.join(sourceRoot, 'session/SessionController.ets'), 'utf8');
  const parsed = ts.createSourceFile('SessionController.ts', source, ts.ScriptTarget.Latest, true);
  const controller = parsed.statements.find(statement =>
    ts.isClassDeclaration(statement) && statement.name?.text === 'SessionController');
  const method = controller.members.find(member => member.name?.text === 'startAudio');
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
  const javascript = ts.transpileModule(`class Target { ${method.getText(parsed)} }`, {
    compilerOptions: { target: ts.ScriptTarget.ES2020 }
  }).outputText;
  const Target = vm.runInNewContext(`${javascript}\nTarget`, {
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

test('video worker uses cloned buffers and falls back once without losing the frame or key', async () => {
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
  assert.equal((await cipher.seal(nonce, data, aad)).length, 4112);
  assert.equal(calls[0][1], nonce);
  assert.equal(calls[0][2], data);
  await cipher.seal(nonce, data, aad);
  assert.equal(executions, 2);
  assert.equal(calls.length, 2);
  assert.equal(key.byteLength, 32);
  assert.equal(data.byteLength, 4096);
  assert.equal(aad.byteLength, 128);
});

function videoSenderFixture(send, split = data => [data]) {
  const sent = [];
  const encrypted = [];
  let keyFrameRequests = 0;
  const concatBytes = (...parts) => {
    const result = new Uint8Array(parts.reduce((total, part) => total + part.length, 0));
    let offset = 0;
    for (const part of parts) { result.set(part, offset); offset += part.length; }
    return result;
  };
  const api = loadEts('airplay/AirPlayVideoStream.ets', {
    '../crypto/MediaPacketCipher': { MediaPacketCipher: class {
      async seal(nonce, data, aad) {
        encrypted.push({ nonce: nonce.slice(), aad: aad.slice(), data: data.slice() });
        return concatBytes(data, new Uint8Array(16));
      }
    } },
    '../protocol/Iap2Codec': { concatBytes },
    '../session/ProtocolLogger': { formatProtocolEvent: () => '' },
    '../video/NativeH264Data': { splitH264NalUnits: split }
  });
  const sender = new api.AirPlayVideoStreamSender(new Uint8Array(32), 1280, 720,
    async data => { sent.push(data); if (send) { await send(data); } },
    () => {}, () => { keyFrameRequests++; });
  const event = (type, data, flags = 0) => ({ type, data, flags, timestampUs: 0 });
  const sps = new Uint8Array([0x67, 0x64, 0, 0x1f, 0x80]);
  const pps = new Uint8Array([0x68, 0x80]);
  const frame = new Uint8Array([0x41, 0x80]);
  const configure = async () => {
    await sender.handleEncoderEvent(event('codecConfig', sps));
    await sender.handleEncoderEvent(event('codecConfig', pps));
  };
  return { sender, sent, encrypted, event, sps, pps, frame, configure,
    keyFrameRequests: () => keyFrameRequests };
}

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
  fixture.sender.beginFrameRecovery('test recovery');
  await fixture.sender.handleEncoderEvent(fixture.event('frame', fixture.frame));
  assert.equal(fixture.encrypted.length, 1);
  await fixture.sender.handleEncoderEvent(fixture.event('frame', idr));
  assert.equal(fixture.encrypted.length, 2);
  assert.equal(fixture.sender.awaitingKeyFrame, false);
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
  assert.equal(fixture.sender.awaitingKeyFrame, true);
  assert.equal(fixture.encrypted.length, 1);
  release();
  await first;
  await fixture.sender.flush();
  assert.equal(fixture.sender.queuedBytes, 0);
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
    assert.equal(fixture.sender.awaitingKeyFrame, true);
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

test('unknown app candidates remain unverified without a source-backed launch target', async () => {
  const { resolveProjectionApps } = loadEts('pages/ProjectionAppCatalog.ets');
  const resolved = await resolveProjectionApps(() => true);
  const petal = resolved.find(app => app.appId === 'petal-maps');
  const tangshui = resolved.find(app => app.appId === 'tangshui-music');
  assert.equal(petal.launchTarget, undefined);
  assert.equal(petal.launchState, 'UNVERIFIED');
  assert.equal(tangshui.launchTarget, undefined);
  assert.equal(tangshui.launchState, 'UNVERIFIED');
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

test('volume control works on systems that do not grant media mute', async () => {
  const calls = [];
  const manager = {
    async isMute() { return false; },
    async mute(type, value) { calls.push(value); throw new Error('mute not permitted'); },
    getVolumeManager() { return { on() {}, off() {} }; }
  };
  const { CarAudioOutput } = loadEts('audio/CarAudioOutput.ets', {
    '@ohos.multimedia.audio': {
      AudioVolumeType: { MEDIA: 3 }, StreamUsage: { STREAM_USAGE_MEDIA: 1 },
      getAudioManager: () => manager
    }
  });
  const route = new CarAudioOutput();
  await route.start();
  await route.stop();
  assert.deepEqual(calls, []);
});

test('phone media volume changes update car gain and the route releases its subscription', async () => {
  let muted = false;
  const systemWrites = [];
  let listener;
  let removed = false;
  const volumeManager = {
    getMaxVolumeByStream() { return 15; },
    getVolumeByStream() { return 9; },
    on(type, usage, callback) { listener = callback; },
    off(type, callback) { removed = callback === listener; }
  };
  const manager = {
    async isMute() { return muted; },
    async mute(type, value) { muted = value; systemWrites.push(value); },
    getVolumeManager() { return volumeManager; }
  };
  const storage = global.AppStorage;
  let value;
  try {
    global.AppStorage = { setOrCreate(name, next) { value = next; } };
    const { CarAudioOutput } = loadEts('audio/CarAudioOutput.ets', {
      '@ohos.multimedia.audio': {
        AudioVolumeType: { MEDIA: 3 }, StreamUsage: { STREAM_USAGE_MEDIA: 1 },
        getAudioManager: () => manager
      }
    });
    const route = new CarAudioOutput();
    await route.start();
    assert.equal(value, 60);
    listener({ volume: 6, updateUi: false });
    assert.equal(value, 40);
    listener({ volume: 10, updateUi: true });
    assert.equal(value, 67);
    listener({ volume: 4, updateUi: true });
    assert.equal(value, 27);
    listener({ volume: 0, updateUi: true });
    assert.equal(value, 0);
    listener({ volume: 1, updateUi: true });
    assert.equal(value, 7);
    await route.stop();
    assert.deepEqual(systemWrites, []);
    assert.equal(removed, true);
    assert.equal(muted, false);
  } finally { global.AppStorage = storage; }
});

test('Dock supports Apps, Home, split and map/music alternative menus', () => {
  const { findLaunchableProjectionApp, isProjectionAppLaunchable } = loadEts('pages/ProjectionAppCatalog.ets');
  const Target = loadMethods('pages/ProjectionDashboard.ets', 'ProjectionDashboard',
    ['activateDock', 'isDashboardHome', 'categoryApp', 'launchableCategoryApp'], {
      HOME_APP: { uri: 'home' },
      PROJECTION_MAP_URI: 'amap',
      findLaunchableProjectionApp,
      isProjectionAppLaunchable
    });
  const dashboardSource = fs.readFileSync(path.join(sourceRoot, 'pages/ProjectionDashboard.ets'), 'utf8');
  assert.match(dashboardSource, /Scroll\(this\.dockScroller\)/);
  assert.match(dashboardSource, /\.width\(vertical \? '100%' : 64\)/);
  assert.match(dashboardSource, /\.height\(vertical \? 48 : '100%'\)/);
  assert.match(dashboardSource, /DockItem\('home', '首页', 'app\.media\.ic_house'/);
  assert.match(dashboardSource, /DockItem\('apps', '应用', 'app\.media\.ic_layout_grid'/);
  assert.match(dashboardSource, /DockItem\('map', '地图', 'app\.media\.ic_navigation'/);
  assert.match(dashboardSource, /DockItem\('music', '音乐', 'app\.media\.ic_music'/);
  assert.match(dashboardSource, /DockItem\('split', '分屏', 'app\.media\.ic_split'/);
  assert.doesNotMatch(dashboardSource, /DockItem\([\s\S]{0,800}?\.layoutWeight\(1\)/);
  assert.match(dashboardSource, /accessibilityText\(this\.appOnPhone \? '切换地图到虚拟屏' : '切换地图到手机'\)/);
  assert.match(dashboardSource, /'map', 'toggleDisplay', newArea, \(\): void => this\.onToggleMapDisplay\(\)/);
  assert.match(dashboardSource, /this\.onToggleAppDisplay\(\)/);
  const target = new Target();
  target.apps = [
    { appId: 'amap', uri: 'amap', category: 'map', launchState: 'VERIFIED',
      launchTarget: { kind: 'ability', bundleName: 'com.amap.hmapp', abilityName: 'EntryAbility' } },
    { appId: 'baidu-map', uri: 'baidu', category: 'map', launchState: 'VERIFIED',
      launchTarget: { kind: 'appLink', uri: 'baidumap://map' } },
    { appId: 'huawei-music', uri: 'music', category: 'music', launchState: 'VERIFIED',
      launchTarget: { kind: 'appLink', uri: 'hwmusic://com.huawei.hmsapp.music' } },
    { appId: 'other-music', uri: 'otherMusic', category: 'music', launchState: 'VERIFIED',
      launchTarget: { kind: 'appLink', uri: 'other-music://' } }
  ];
  target.mediaState = {};
  target.selectedMapUri = 'amap';
  target.selectedMusicUri = 'music';
  target.activeAppLabel = '';
  target.dashboardView = 'home';
  const actions = [];
  target.showDashboardView = view => actions.push(view);
  target.selectApp = app => actions.push(app.uri);
  target.activateDock('apps');
  target.activeAppLabel = 'Map';
  target.navigationPreview = false;
  target.activateDock('home');
  target.activateDock('map');
  target.selectedMapUri = 'baidu';
  target.activateDock('map');
  target.activateDock('map', true);
  target.activateDock('music');
  target.selectedMusicUri = 'otherMusic';
  target.activateDock('music');
  target.activateDock('music', true);
  target.activateDock('split');
  target.activateDock('settings');
  assert.deepEqual(actions, ['apps', 'home', 'amap', 'baidu', 'maps', 'music', 'otherMusic', 'music', 'split', 'settings']);
});

test('Apps grid includes only launchable third-party apps and adapts from three to six columns', () => {
  const vehicleApps = [{ appId: 'shell-settings', uri: 'settings', category: 'vehicle' }];
  const Target = loadMethods('pages/ProjectionDashboard.ets', 'ProjectionDashboard', [
    'visibleApps', 'updateAppsGridColumns', 'appsGridTemplate'
  ], {
    PROJECTION_VEHICLE_APPS: vehicleApps,
    isProjectionAppLaunchable: app => app.launchState === 'VERIFIED' && !!app.launchTarget
  });
  const target = new Target();
  target.apps = [
    { appId: 'verified', uri: 'verified', launchState: 'VERIFIED', launchTarget: { uri: 'open' } },
    { appId: 'unverified', uri: 'unverified', launchState: 'UNVERIFIED', launchTarget: { uri: 'unknown' } }
  ];
  assert.equal(target.visibleApps().map(app => app.appId).join(','), 'shell-settings,verified');
  for (const [width, columns] of [[320, 3], [400, 4], [520, 5], [700, 6]]) {
    target.updateAppsGridColumns(width);
    assert.equal(target.appsGridColumns, columns);
    assert.equal(target.appsGridTemplate().split(' ').length, columns);
  }
});

test('split dashboard hides ratio controls and requires an opened music app', () => {
  const source = fs.readFileSync(path.join(sourceRoot, 'pages/ProjectionDashboard.ets'), 'utf8');
  assert.doesNotMatch(source, /splitMapWeight|splitMusicWeight|selectSplitRatio|Text\('2:2'\)|Text\('3:1'\)|Text\('4:1'\)/);
  assert.match(source, /\.layoutWeight\(2\)/);
  assert.match(source, /\.layoutWeight\(1\)/);
  assert.match(source, /if \(view === 'split' && !this\.activeMusicApp\(\)\)/);
  const Target = loadMethods('pages/ProjectionDashboard.ets', 'ProjectionDashboard', ['showDashboardView'], {
    AppStorage: { get: () => -1, setOrCreate: () => {} }
  });
  const target = new Target();
  target.dashboardView = 'home';
  target.touchBounds = new Map();
  target.activeMusicApp = () => undefined;
  target.showDockActionMessage = message => { target.dockActionMessage = message; };
  target.showDashboardView('split');
  assert.equal(target.dashboardView, 'home');
  assert.match(target.dockActionMessage, /音乐 app/);
  target.activeMusicApp = () => ({ appId: 'huawei-music' });
  target.setNavigationPreview = () => {};
  target.showDashboardView('split');
  assert.equal(target.dashboardView, 'split');
});

test('socket shutdown deadlines settle stalled operations instead of hanging recovery', async () => {
  const { settleSocketWithin } = loadEts('network/SocketDeadline.ets');
  await assert.rejects(settleSocketWithin(new Promise(() => {}), 1, 'stalled socket'), /stalled socket/);
  assert.equal(await settleSocketWithin(Promise.resolve(42), 1000, 'unexpected'), 42);
});

test('audio closes its socket before waiting for a blocked packet write', async () => {
  const { sender, session } = audioSenderFixture();
  await sender.start(session);
  let release;
  const events = [];
  sender.sendQueue = new Promise(resolve => { release = resolve; });
  sender.socket.close = async () => { events.push('close'); release(); };
  await sender.stop();
  assert.deepEqual(events, ['close']);
  assert.equal(sender.socket, undefined);
});

test('shake toggles the existing app display and preserves state on failure', async () => {
  const source = fs.readFileSync(path.join(sourceRoot, 'pages/ProjectionHome.ets'), 'utf8');
  assert.match(source, /@State private appOnPhone: boolean = false/);
  const parsed = ts.createSourceFile('ProjectionHome.ts',
    source.replace('struct ProjectionHome {', 'class ProjectionHome {'), ts.ScriptTarget.Latest, true);
  const component = parsed.statements.find(statement =>
    ts.isClassDeclaration(statement) && statement.name?.text === 'ProjectionHome');
  const method = component.members.find(member => member.name?.text === 'toggleAppDisplay');
  const javascript = ts.transpileModule(`class Target { ${method.getText(parsed)} }`, {
    compilerOptions: { target: ts.ScriptTarget.ES2020 }
  }).outputText;
  const Target = vm.runInNewContext(`${javascript}\nTarget`, {
    display: { getDefaultDisplaySync: () => ({ id: 0 }) },
    projectionDisplayToggleTarget: (currentlyOnPhone, phoneDisplayId, virtualDisplayId) =>
      currentlyOnPhone ? virtualDisplayId : phoneDisplayId
  });
  const target = new Target();
  target.appSwitching = false;
  target.appOnPhone = true;
  target.appDisplayId = 12;
  target.activeApp = { appId: 'huawei-music', uri: 'hwmusic://com.huawei.hmsapp.music', label: 'Music' };
  target.logProjection = () => {};
  target.publishAppTouchBounds = () => {};
  const opened = [];
  target.launchApp = async (app, displayId) => opened.push([app.uri, displayId]);
  await target.toggleAppDisplay();
  assert.deepEqual(opened, [['hwmusic://com.huawei.hmsapp.music', 12]]);
  assert.equal(target.appOnPhone, false);
  await target.toggleAppDisplay();
  assert.equal(target.appOnPhone, true);
  assert.deepEqual(opened[1], ['hwmusic://com.huawei.hmsapp.music', 0]);
  target.launchApp = async () => { throw new Error('open rejected'); };
  await target.toggleAppDisplay();
  assert.equal(target.appOnPhone, true);
  assert.equal(target.appSwitching, false);
  assert.match(target.launchMessage, /open rejected/);
});

test('projection launches only verified targets on the requested display', async () => {
  const { projectionAppLaunchTarget } = loadEts('pages/ProjectionAppCatalog.ets');
  const source = fs.readFileSync(path.join(sourceRoot, 'pages/ProjectionHome.ets'), 'utf8');
  const parsed = ts.createSourceFile('ProjectionHome.ts',
    source.replace('struct ProjectionHome {', 'class ProjectionHome {'), ts.ScriptTarget.Latest, true);
  const component = parsed.statements.find(statement =>
    ts.isClassDeclaration(statement) && statement.name?.text === 'ProjectionHome');
  const method = component.members.find(member => member.name?.text === 'launchApp');
  const javascript = ts.transpileModule(`class Target { ${method.getText(parsed)} }`, {
    compilerOptions: { target: ts.ScriptTarget.ES2020 }
  }).outputText;
  const Target = vm.runInNewContext(`${javascript}\nTarget`, {
    isProjectionAppLaunchable: app => app.launchState === 'VERIFIED' && !!app.launchTarget,
    projectionAppLaunchTarget
  });
  const calls = [];
  const target = new Target();
  target.getUIContext = () => ({ getHostContext: () => ({
    async startAbility(want, options) { calls.push(JSON.parse(JSON.stringify({ want, options }))); }
  }) });
  await target.launchApp({
    appId: 'verified-music',
    uri: 'carplay-client://v1/apps/verified-music/launch',
    label: 'Verified Music',
    launchState: 'VERIFIED',
    launchTarget: { kind: 'appLink', uri: 'verified-music-link://' }
  }, 12);
  assert.deepEqual(calls, [{ want: { action: 'ohos.want.action.viewData', uri: 'verified-music-link://' },
    options: { displayId: 12 } }]);
  await target.launchApp({
    appId: 'verified-map',
    uri: 'carplay-client://v1/apps/verified-map/launch',
    label: 'Verified Map',
    launchState: 'VERIFIED',
    launchTarget: { kind: 'ability', bundleName: 'org.example.verified', abilityName: 'EntryAbility' }
  }, 15);
  assert.deepEqual(calls[1], { want: {
    bundleName: 'org.example.verified', abilityName: 'EntryAbility'
  },
    options: { displayId: 15 } });
  assert.equal(Object.hasOwn(calls[1].want, 'uri'), false);
  assert.equal(Object.hasOwn(calls[1].want, 'flags'), false);
  const amap = {
    appId: 'amap',
    uri: 'carplay-client://v1/apps/amap/launch',
    bundleName: 'com.amap.hmapp',
    moduleName: 'entry',
    abilityName: 'EntryAbility',
    label: '高德地图',
    launchState: 'VERIFIED',
    launchTarget: {
      kind: 'ability',
      bundleName: 'com.amap.hmapp',
      moduleName: 'entry',
      abilityName: 'EntryAbility',
      isSingleton: true,
      probeUri: 'amapuri://'
    }
  };
  await target.launchApp(amap, 18);
  assert.deepEqual(calls[2], {
    want: { action: 'ohos.want.action.viewData', uri: 'amapuri://' },
    options: { displayId: 18 }
  });
  await target.launchApp(amap, 19, true);
  assert.deepEqual(calls[3], {
    want: { bundleName: 'com.amap.hmapp', moduleName: 'entry', abilityName: 'EntryAbility' },
    options: { displayId: 19 }
  });
  const nonSingletonAmap = {
    ...amap,
    launchTarget: { ...amap.launchTarget, isSingleton: false }
  };
  await assert.rejects(target.launchApp(nonSingletonAmap, 20, true), /拒绝重新启动/);
  await assert.rejects(target.launchApp({
    appId: 'amap',
    uri: 'carplay-client://v1/apps/amap/launch',
    label: 'Amap',
    launchState: 'UNVERIFIED'
  }, 17), /启动入口尚未验证/);
});

test('app surface replacement retains the display and never relaunches the navigation app', async () => {
  const source = fs.readFileSync(path.join(sourceRoot, 'pages/ProjectionHome.ets'), 'utf8');
  const parsed = ts.createSourceFile('ProjectionHome.ts',
    source.replace('struct ProjectionHome {', 'class ProjectionHome {'), ts.ScriptTarget.Latest, true);
  const component = parsed.statements.find(statement =>
    ts.isClassDeclaration(statement) && statement.name?.text === 'ProjectionHome');
  const method = component.members.find(member => member.name?.text === 'updateAppSurface');
  const javascript = ts.transpileModule(`class Target { ${method.getText(parsed)} }`, {
    compilerOptions: { target: ts.ScriptTarget.ES2020 }
  }).outputText;
  const calls = [];
  let releaseSurface;
  const Target = vm.runInNewContext(`${javascript}\nTarget`, {
    display: { async setVirtualScreenSurface(id, surfaceId) {
      if (surfaceId === 'broken') throw new Error('surface unavailable');
      if (surfaceId === 'delayed') await new Promise(resolve => { releaseSurface = resolve; });
      calls.push([id, surfaceId]);
    } }
  });
  const target = new Target();
  target.appDisplayId = 23;
  target.activeAppSurface = { surfaceId: 'old', width: 1200, height: 700 };
  target.appDisplayGeneration = 0;
  target.appSurfaceGeneration = 0;
  target.launchMessage = '';
  target.logProjection = () => {};
  target.releaseAppDisplay = async () => { throw new Error('navigation display must survive'); };
  target.launchApp = async () => { throw new Error('navigation must not be relaunched'); };
  let published;
  target.publishAppTouchBounds = surface => { published = surface; };
  const surface = { surfaceId: 'new', left: 80, top: 10, width: 1200, height: 700 };
  await target.updateAppSurface(surface);
  assert.deepEqual(calls, [[23, 'new']]);
  assert.equal(target.appDisplayId, 23);
  assert.equal(published, surface);
  const resized = { ...surface, left: 100, width: 600, height: 350 };
  await target.updateAppSurface(resized);
  assert.equal(target.appDisplayId, 23);
  assert.equal(published, resized);
  assert.equal(calls.length, 1);
  await target.updateAppSurface({ ...resized, surfaceId: 'broken' });
  assert.equal(target.appDisplayId, 23);
  assert.equal(published, resized);
  assert.equal(target.activeAppSurface, resized);
  assert.match(target.launchMessage, /surface unavailable/);
  await target.updateAppSurface(undefined);
  assert.equal(target.appDisplayId, 23);
  assert.equal(published, undefined);
  await target.updateAppSurface(resized);
  assert.equal(target.appDisplayId, 23);
  assert.equal(published, resized);
  assert.deepEqual(calls, [[23, 'new'], [23, 'new']]);
  assert.equal(target.launchMessage, '');
  const pending = target.updateAppSurface({ ...resized, surfaceId: 'delayed' });
  await target.updateAppSurface(undefined);
  releaseSurface();
  await pending;
  assert.equal(published, undefined, 'late binding must not restore a detached touch target');
  assert.equal(target.appSurfaceAttached, false);
});

test('map card opens its link on the phone before releasing the content display', async () => {
  const source = fs.readFileSync(path.join(sourceRoot, 'pages/ProjectionHome.ets'), 'utf8');
  const parsed = ts.createSourceFile('ProjectionHome.ts',
    source.replace('struct ProjectionHome {', 'class ProjectionHome {'), ts.ScriptTarget.Latest, true);
  const component = parsed.statements.find(statement =>
    ts.isClassDeclaration(statement) && statement.name?.text === 'ProjectionHome');
  const method = component.members.find(member => member.name?.text === 'releaseMapDisplay');
  const javascript = ts.transpileModule(`class Target { ${method.getText(parsed)} }`, {
    compilerOptions: { target: ts.ScriptTarget.ES2020 }
  }).outputText;
  const order = [];
  const Target = vm.runInNewContext(`${javascript}\nTarget`, {
    AppStorage: { setOrCreate() {} }, display: {
      getDefaultDisplaySync: () => ({ id: 0 }),
      async destroyVirtualScreen(id) { order.push(['destroy', id]); }
    }
  });
  const target = new Target();
  target.mapDisplayId = 23;
  target.mapApp = { uri: 'carplay-client://v1/apps/amap/launch' };
  target.logProjection = () => {};
  target.launchApp = async (app, id) => order.push(['link', app.uri, id]);
  await target.releaseMapDisplay();
  assert.deepEqual(order, [['link', 'carplay-client://v1/apps/amap/launch', 0], ['destroy', 23]]);
  await target.releaseMapDisplay();
  assert.equal(order.length, 2);
});

test('resizing the map split surface rebuilds its virtual display without a phone handoff', async () => {
  const mapApp = {
    appId: 'amap', uri: 'map', category: 'map', launchState: 'VERIFIED',
    launchTarget: { kind: 'appLink', uri: 'map-link' }
  };
  const events = [];
  const Target = loadMethods('pages/ProjectionHome.ets', 'ProjectionHome', ['updateMapSurface'], {
    AppStorage: { get: key => key === 'carplaySelectedMapAppId' ? 'amap' : 2, setOrCreate() {} },
    discoverProjectionApps: async () => [mapApp],
    isProjectionAppLaunchable: () => true,
    PROJECTION_APP_CANDIDATES: [],
    display: {
      async createVirtualScreen(options) { events.push(['create', options.width, options.height]); return 24; },
      async setVirtualScreenSurface(id, surfaceId) { events.push(['surface', id, surfaceId]); },
      async makeUnique(id) { events.push(['unique', id]); }
    }
  });
  const target = new Target();
  target.mapDisplayId = 23;
  target.mapDisplayGeneration = 0;
  target.activeMapSurface = { surfaceId: 'map-surface', left: 0, top: 0, width: 600, height: 400 };
  target.releaseMapDisplay = async restoreToPhone => {
    events.push(['release', restoreToPhone]);
    target.mapDisplayId = -1;
    target.activeMapSurface = undefined;
  };
  target.publishMapTouchBounds = () => {};
  target.launchApp = async (app, displayId) => events.push(['launch', app.appId, displayId]);
  target.logProjection = () => {};
  await target.updateMapSurface({ surfaceId: 'map-surface', left: 0, top: 0, width: 800, height: 400 });
  assert.deepEqual(events, [
    ['release', false], ['create', 800, 400], ['surface', 24, 'map-surface'], ['unique', 24], ['launch', 'amap', 24]
  ]);
});

test('selecting map from split promotes it to the content display without a phone handoff', async () => {
  const Target = loadMethods('pages/ProjectionHome.ets', 'ProjectionHome', ['selectApp'], {
    AppStorage: { get: () => 'home' },
    isProjectionAppLaunchable: app => app.launchState === 'VERIFIED' && !!app.launchTarget
  });
  const target = new Target();
  const events = [];
  target.appSwitching = false;
  target.appDisplayId = 42;
  target.appOnPhone = false;
  target.mapDisplayId = 23;
  target.activeApp = { uri: 'music', category: 'music' };
  target.releaseMapDisplay = async restoreToPhone => events.push(['releaseMap', restoreToPhone]);
  target.launchApp = async (app, displayId) => events.push(['launch', app.uri, displayId]);
  target.publishAppTouchBounds = () => {};
  await target.selectApp({
    uri: 'map', label: '地图', category: 'map', launchState: 'VERIFIED',
    launchTarget: { kind: 'appLink', uri: 'map-link' }
  });
  assert.deepEqual(events, [['releaseMap', false], ['launch', 'map', 42]]);
  assert.equal(target.activeApp.uri, 'map');
  assert.equal(target.appOnPhone, false);
});

test('abnormal video shutdown closes TCP before draining and does not send TEARDOWN', async () => {
  const source = fs.readFileSync(path.join(sourceRoot, 'airplay/AirPlayMediaSession.ets'), 'utf8');
  const parsed = ts.createSourceFile('AirPlayMediaSession.ts', source, ts.ScriptTarget.Latest, true);
  const declaration = parsed.statements.find(statement =>
    ts.isClassDeclaration(statement) && statement.name?.text === 'AirPlayMediaSession');
  const method = declaration.members.find(member => member.name?.text === 'stop');
  const javascript = ts.transpileModule(`class Target { ${method.getText(parsed)} }`, {
    compilerOptions: { target: ts.ScriptTarget.ES2020 }
  }).outputText;
  const { settleSocketWithin } = loadEts('network/SocketDeadline.ets');
  const Target = vm.runInNewContext(`${javascript}\nTarget`, {
    settleSocketWithin, clearInterval, clearTimeout
  });
  const target = new Target();
  const order = [];
  let release;
  const blocked = new Promise(resolve => { release = resolve; });
  target.log = () => {};
  target.recorded = true;
  target.client = { isConnected: true };
  target.request = () => { throw new Error('must not TEARDOWN a broken connection'); };
  target.videoDataSocket = { async close() { order.push('close'); release(); } };
  target.videoStreamSender = { async flush() { order.push('drain'); await blocked; } };
  target.videoWriteQueue = blocked;
  await target.stop(true);
  assert.deepEqual(order, ['close', 'drain']);
  assert.equal(target.videoDataSocket, undefined);
  assert.equal(target.videoStreamSender, undefined);
  assert.equal(target.recorded, false);
});

test('embedded app and map hit rectangles use the actual window density, not the requested virtual density', () => {
  const source = fs.readFileSync(path.join(sourceRoot, 'pages/ProjectionDashboard.ets'), 'utf8');
  const parsed = ts.createSourceFile('ProjectionDashboard.ts',
    source.replace('struct ProjectionDashboard {', 'class ProjectionDashboard {'), ts.ScriptTarget.Latest, true);
  const declaration = parsed.statements.find(statement =>
    ts.isClassDeclaration(statement) && statement.name?.text === 'ProjectionDashboard');
  const methods = declaration.members.filter(member => ['notifyAppSurface', 'notifyMapSurface'].includes(member.name?.text));
  const javascript = ts.transpileModule(`class Target { ${methods.map(method => method.getText(parsed)).join('\n')} }`, {
    compilerOptions: { target: ts.ScriptTarget.ES2020 }
  }).outputText;
  const Target = vm.runInNewContext(`${javascript}\nTarget`, {
    AppStorage: { get: () => 1.333 }
  });
  const target = new Target();
  target.getUIContext = () => ({ vp2px: value => value * 3, px2vp: value => value / 3 });
  target.appSurfaceId = 'app';
  target.mapSurfaceId = 'map';
  target.mapSurfaceLoaded = true;
  target.appSurfaceArea = target.mapSurfaceArea = {
    globalPosition: { x: 70, y: 8 }, width: 300, height: 200
  };
  let app;
  let map;
  target.onAppSurfaceChange = surface => { app = JSON.parse(JSON.stringify(surface)); };
  target.onMapSurfaceChange = surface => { map = JSON.parse(JSON.stringify(surface)); };
  target.notifyAppSurface();
  target.notifyMapSurface();
  assert.deepEqual(app, { surfaceId: 'app', left: 210, top: 24, width: 900, height: 600 });
  assert.deepEqual(map, { ...app, surfaceId: 'map' });
  assert.ok(120 < app.left, 'a Dock touch must stay outside the embedded app');
});

test('CarPlay tap hit testing tolerates small finger drift by targeting the contact midpoint', () => {
  const Target = loadMethods('pages/ProjectionDashboard.ets', 'ProjectionDashboard', [
    'touchHandler', 'canvasPixelToContentPoint', 'screenToContentPoint', 'contains'
  ], {
    AppStorage: { get: key => ({ carplayProjectionHomeActive: true, carplayProjectionDisplayId: 7 })[key] }
  });
  const target = new Target();
  target.viewAreaOriginX = 0;
  target.viewAreaOriginY = 0;
  target.contentScalePercent = 100;
  target.contentOffsetXPercent = 0;
  target.contentOffsetYPercent = 0;
  target.projectionViewportWidth = 400;
  target.projectionViewportHeight = 200;
  target.getUIContext = () => ({ px2vp: value => value });
  const bounds = { left: 10, top: 10, right: 60, bottom: 60 };
  let activated = 0;
  target.touchBounds = new Map([['dock', bounds]]);
  target.touchAreas = new Map([['dock:map', {
    group: 'dock', ...bounds, action: () => { activated++; }
  }]]);
  target.touchHandler({ data: {
    displayId: 7, startX: 54, endX: 62, startY: 30, endY: 30, maxDistance: 8, durationMs: 120
  } });
  assert.equal(activated, 1);
  const settingsBounds = { left: 100, top: 10, right: 160, bottom: 60 };
  let settingsActivated = 0;
  target.dashboardView = 'settings';
  target.touchBounds.set('settings', settingsBounds);
  target.touchAreas.set('settings:dayNight', {
    group: 'settings', ...settingsBounds, action: () => { settingsActivated++; }
  });
  target.touchHandler({ data: {
    displayId: 7, startX: 120, endX: 120, startY: 30, endY: 30, maxDistance: 0, durationMs: 800
  } });
  assert.equal(settingsActivated, 1, 'a slow non-Dock touch must still activate on release');
});

test('Dock taps use measured bounds and window density while hidden map areas cannot steal grid taps', () => {
  const source = fs.readFileSync(path.join(sourceRoot, 'pages/ProjectionDashboard.ets'), 'utf8');
  const parsed = ts.createSourceFile('ProjectionDashboard.ts',
    source.replace('struct ProjectionDashboard {', 'class ProjectionDashboard {'), ts.ScriptTarget.Latest, true);
  const declaration = parsed.statements.find(statement =>
    ts.isClassDeclaration(statement) && statement.name?.text === 'ProjectionDashboard');
  const members = declaration.members.filter(member =>
    ['touchHandler', 'contains', 'screenToContentPoint', 'canvasPixelToContentPoint'].includes(member.name?.text));
  const javascript = ts.transpileModule(`class Target { ${members.map(member => member.getText(parsed)).join('\n')} }`, {
    compilerOptions: { target: ts.ScriptTarget.ES2020 }
  }).outputText;
  const Target = vm.runInNewContext(`${javascript}\nTarget`, {
    AppStorage: { get: key => ({
      carplayProjectionHomeActive: true, carplayProjectionDisplayId: 7, carplayProjectionDensity: 1.333
    })[key] }
  });
  const target = new Target();
  target.contentScalePercent = 100;
  target.contentOffsetXPercent = 0;
  target.contentOffsetYPercent = 0;
  target.projectionViewportWidth = 1000;
  target.projectionViewportHeight = 600;
  target.viewAreaOriginX = 0;
  target.viewAreaOriginY = 0;
  let density = 3;
  target.getUIContext = () => ({ px2vp: value => value / density });
  target.touchBounds = new Map([
    ['dock', { left: 0, top: 0, right: 60, bottom: 200 }],
    ['map', { left: 80, top: 0, right: 300, bottom: 180 }],
    ['grid', { left: 80, top: 0, right: 300, bottom: 180 }]
  ]);
  let mapOpened = false;
  let gridOpened = false;
  let longPresses = 0;
  const selected = [];
  target.touchAreas = new Map([
    ['dock-first', { group: 'dock', left: 4, top: 8, right: 56, bottom: 31,
      action: () => selected.push('first') }],
    ['dock-second', { group: 'dock', left: 4, top: 38, right: 56, bottom: 54,
      action: () => selected.push('second'), longPress: () => { longPresses++; } }],
    ['map', { group: 'map', left: 80, top: 0, right: 300, bottom: 180, action: () => { mapOpened = true; } }],
    ['grid', { group: 'grid', left: 80, top: 0, right: 300, bottom: 180, action: () => { gridOpened = true; } }]
  ]);
  const tap = (x, y) => target.touchHandler({ data: {
    displayId: 7, startX: x, endX: x, startY: y, endY: y
  } });
  for (const scale of [1, 1.333, 2, 3]) {
    density = scale;
    tap(10 * scale, 50 * scale);
    assert.equal(selected.at(-1), 'second');
    const count = selected.length;
    tap(10 * scale, 35 * scale);
    tap(59 * scale, 50 * scale);
    assert.equal(selected.length, count, 'spacing and side padding must not open an app');
  }
  assert.equal(selected.length, 4);
  density = 3;
  target.touchHandler({ data: {
    displayId: 7, startX: 30, endX: 30, startY: 150, endY: 150, durationMs: 800
  } });
  assert.equal(longPresses, 1);
  assert.equal(selected.length, 4, 'long press must not also launch an app');
  target.dashboardView = 'apps';
  target.activeAppLabel = '';
  tap(300, 60);
  assert.equal(mapOpened, false);
  assert.equal(gridOpened, true);
  target.touchBounds.set('media', { left: 320, top: 0, right: 400, bottom: 180 });
  let mediaCommands = 0;
  target.touchAreas.set('media', {
    group: 'media', left: 320, top: 0, right: 400, bottom: 180,
    action: () => { mediaCommands++; }
  });
  target.dashboardView = 'home';
  target.activeAppLabel = 'Amap';
  target.navigationPreview = true;
  tap(1050, 60);
  assert.equal(mediaCommands, 1, 'home music controls must work alongside an active map preview');
  target.navigationPreview = false;
  tap(1050, 60);
  assert.equal(mediaCommands, 1, 'hidden home music controls must not intercept full map touches');
  const menuBounds = { left: 80, top: 0, right: 300, bottom: 180 };
  target.touchBounds.set('maps', menuBounds);
  target.touchBounds.set('music', menuBounds);
  const menus = [];
  target.touchAreas.set('maps', { ...menuBounds, group: 'maps', action: () => menus.push('map') });
  target.touchAreas.set('music', { ...menuBounds, group: 'music', action: () => menus.push('music') });
  target.dashboardView = 'music';
  tap(300, 60);
  assert.deepEqual(menus, ['music'], 'a hidden map menu must not intercept music selections');
  target.dashboardView = 'maps';
  tap(300, 60);
  assert.deepEqual(menus, ['music', 'map']);
  density = 2;
  target.viewAreaOriginX = 200;
  target.viewAreaOriginY = 100;
  target.contentScalePercent = 200;
  const mapped = target.canvasPixelToContentPoint(400, 300);
  assert.deepEqual([mapped.x, mapped.y], [400, 250]);
});

test('disabled media commands cannot be invoked through fallback touch', async () => {
  const Target = loadMethods('pages/ProjectionDashboard.ets', 'ProjectionDashboard', ['sendMediaCommand']);
  const target = new Target();
  const commands = [];
  target.mediaState = { commands: ['play'] };
  target.mediaSessionBridge = { async send(command) { commands.push(command); } };
  target.refreshMediaSession = async () => {};
  await target.sendMediaCommand('playNext');
  await target.sendMediaCommand('play');
  assert.deepEqual(commands, ['play']);
});

test('split dashboard has independent navigation and app surfaces', () => {
  const source = fs.readFileSync(path.join(sourceRoot, 'pages/ProjectionDashboard.ets'), 'utf8');
  assert.match(source, /id: 'projectionSplitMapSurface'/);
  assert.match(source, /id: 'projectionSplitMusicSurface'/);
  assert.doesNotMatch(source, /Text\('导航 APP'\)|Text\('音乐 APP'\)/);
  assert.match(source, /this\.dashboardView === 'split'/);
  assert.match(source, /this\.dashboardView === 'split' && app\.category === 'music'/);
  assert.match(source, /this\.DockPanel\(false\)/);
  assert.match(source, /this\.DockPanel\(true\)/);
});

test('split mode keeps the navigation display while selecting a verified music app', async () => {
  let releasedMap = 0;
  const Target = loadMethods('pages/ProjectionHome.ets', 'ProjectionHome', ['selectApp'], {
    AppStorage: { get: () => 'split' },
    isProjectionAppLaunchable: app => app.launchState === 'VERIFIED' && !!app.launchTarget
  });
  const target = new Target();
  target.appSwitching = false;
  target.mapDisplayId = 42;
  target.appDisplayId = -1;
  target.releaseMapDisplay = async () => { releasedMap++; };
  target.logProjection = () => {};
  await target.selectApp({
    appId: 'verified-music',
    uri: 'carplay-client://v1/apps/verified-music/launch',
    label: 'Verified Music',
    category: 'music',
    launchState: 'VERIFIED',
    launchTarget: { kind: 'appLink', uri: 'verified-music-link' }
  });
  assert.equal(releasedMap, 0);
  assert.equal(target.activeApp.appId, 'verified-music');
});

test('Wi-Fi link addresses are formatted with the first octet in the most significant byte', () => {
  const { formatWifiIpv4Address } = loadEts('network/WifiCarPlayConnector.ets', {}, 'formatWifiIpv4Address');
  assert.equal(formatWifiIpv4Address(0xc0a889ab), '192.168.137.171');
  assert.equal(formatWifiIpv4Address(0x0a24e843), '10.36.232.67');
});

test('touch HID UUID and logical extents come from /info and reports scale to the encoded video', () => {
  const touch = loadEts('airplay/CarPlayTouchReport.ets');
  const descriptor = new Uint8Array([
    0x05, 0x0d, 0x09, 0x04, 0xa1, 0x01, 0x05, 0x0d, 0x09, 0x22, 0xa1, 0x02,
    0x09, 0x38, 0x75, 0x08, 0x95, 0x01, 0x81, 0x02,
    0x05, 0x01, 0x26, 0xff, 0x09, 0x09, 0x30, 0x75, 0x10, 0x81, 0x02,
    0x26, 0xcf, 0x02, 0x09, 0x31, 0x81, 0x02, 0xc0, 0xc0
  ]);
  assert.deepEqual({ ...touch.parseHidPointerExtents(descriptor) },
    { touchScreen: true, logicalMaxX: 2559, logicalMaxY: 719 });
  const node = (kind, values) => ({ kind, ...values, get(key) { return this.dictionaryValue.get(key); } });
  const device = node('dictionary', { dictionaryValue: new Map([
    ['uuid', { kind: 'string', stringValue: 'e5f7a68d' }],
    ['displayUUID', { kind: 'string', stringValue: 'display-1' }],
    ['hidDescriptor', { kind: 'data', dataValue: descriptor }]
  ]) });
  const info = node('dictionary', { dictionaryValue: new Map([['hidDevices', { kind: 'array', arrayValue: [device] }]]) });
  const found = touch.findTouchHidDevice(info, 'display-1');
  assert.equal(found.uuid, 'e5f7a68d');
  assert.equal(touch.findTouchHidDevice(info, 'display-2'), undefined);
  const report = new Uint8Array([0, 1, 0xff, 0x09, 0xcf, 0x02, 1, 0, 0, 0, 0, 0]);
  const scaled = touch.scaleCarPlayTouchReport(report, found, 1920, 540);
  assert.deepEqual([...scaled.subarray(2, 6)], [0x7f, 0x07, 0x1b, 0x02]);
  assert.deepEqual([...scaled.subarray(6)], [1, 0, 0, 0, 0, 0]);

  const integerUuid = node('dictionary', { dictionaryValue: new Map([
    ['uuid', { kind: 'integer', integerValue: BigInt('0x2a2a2a2a') }],
    ['displayUUID', { kind: 'string', stringValue: 'display-1' }],
    ['hidDescriptor', { kind: 'data', dataValue: descriptor }]
  ]) });
  const integerInfo = node('dictionary', { dictionaryValue: new Map([[
    'hidDevices', { kind: 'array', arrayValue: [integerUuid] }
  ]]) });
  const integerDevice = touch.findTouchHidDevice(integerInfo, 'display-1');
  assert.deepEqual(integerDevice, { uuid: '2a2a2a2a', logicalMaxX: 2559, logicalMaxY: 719 });
  const integerCommand = node('dictionary', { dictionaryValue: new Map([
    ['type', { kind: 'string', stringValue: 'hidSendReport' }],
    ['params', node('dictionary', { dictionaryValue: new Map([
      ['uuid', { kind: 'integer', integerValue: BigInt('0x2a2a2a2a') }],
      ['hidReport', { kind: 'data', dataValue: report }]
    ]) })]
  ]) });
  assert.deepEqual([...touch.extractCarPlayTouchReport(integerCommand, integerDevice.uuid)], [...report]);
});

test('HID drag scrolls the visible Apps and DockMenu lists in virtual-screen coordinates', () => {
  const source = fs.readFileSync(path.join(sourceRoot, 'pages/ProjectionDashboard.ets'), 'utf8');
  const parsed = ts.createSourceFile('ProjectionDashboard.ts',
    source.replace('struct ProjectionDashboard {', 'class ProjectionDashboard {'), ts.ScriptTarget.Latest, true);
  const declaration = parsed.statements.find(statement =>
    ts.isClassDeclaration(statement) && statement.name?.text === 'ProjectionDashboard');
  const members = declaration.members.filter(member =>
    ['scrollControllerAt', 'handleTouchReport', 'screenToContentPoint', 'canvasPixelToContentPoint',
      'contains'].includes(member.name?.text));
  const javascript = ts.transpileModule(`class Target { ${members.map(member => member.getText(parsed)).join('\n')} }`, {
    compilerOptions: { target: ts.ScriptTarget.ES2020 }
  }).outputText;
  const Target = vm.runInNewContext(`${javascript}\nTarget`, {
    AppStorage: { get: key => ({ carplayProjectionHomeActive: true, carplayProjectionDisplayId: 7 })[key] },
    Math
  });
  const moves = [];
  const makeScroller = target => ({ scrollBy: (x, y) => moves.push({ target, x, y }) });
  const target = new Target();
  target.appsScroller = makeScroller('apps');
  target.dockMenuScroller = makeScroller('dock-menu');
  target.settingsScroller = makeScroller('settings');
  target.themesScroller = makeScroller('themes');
  target.sidebarMediaScroller = makeScroller('media');
  target.touchBounds = new Map([
    ['grid', { left: 0, top: 0, right: 200, bottom: 300 }],
    ['maps', { left: 200, top: 0, right: 400, bottom: 300 }]
  ]);
  target.getUIContext = () => ({ px2vp: value => value / 2 });
  target.contentScalePercent = 100;
  target.contentOffsetXPercent = 0;
  target.contentOffsetYPercent = 0;
  target.projectionViewportWidth = 400;
  target.projectionViewportHeight = 600;
  target.viewAreaOriginX = 0;
  target.viewAreaOriginY = 0;
  target.dashboardView = 'apps';
  target.handleTouchReport({ displayId: 7, contacts: [{ id: 0, down: true, x: 100, y: 200 }] });
  target.handleTouchReport({ displayId: 7, contacts: [{ id: 0, down: true, x: 100, y: 120 }] });
  target.handleTouchReport({ displayId: 7, contacts: [{ id: 0, down: false, x: 100, y: 120 }] });
  target.dashboardView = 'maps';
  target.handleTouchReport({ displayId: 7, contacts: [{ id: 0, down: true, x: 500, y: 200 }] });
  target.handleTouchReport({ displayId: 7, contacts: [{ id: 0, down: true, x: 500, y: 120 }] });
  assert.deepEqual(moves, [
    { target: 'apps', x: 0, y: 40 },
    { target: 'dock-menu', x: 0, y: 40 }
  ]);
});

test('accessory changeModes requests are granted and reflected in the mode state', () => {
  const source = fs.readFileSync(path.join(sourceRoot, 'airplay/AirPlayMediaSession.ets'), 'utf8');
  const parsed = ts.createSourceFile('AirPlayMediaSession.ts', source, ts.ScriptTarget.Latest, true);
  const declaration = parsed.statements.find(statement =>
    ts.isClassDeclaration(statement) && statement.name?.text === 'AirPlayMediaSession');
  const method = declaration.members.find(member => member.name?.text === 'applyChangeModes');
  const javascript = ts.transpileModule(`class Target { ${method.getText(parsed)} }`, {
    compilerOptions: { target: ts.ScriptTarget.ES2020 }
  }).outputText;
  const Modes = vm.runInNewContext(`${javascript}\nTarget`, { BigInt, Number });
  const dict = entries => ({ kind: 'dictionary', get(key) { return entries[key]; } });
  const integer = value => ({ kind: 'integer', integerValue: BigInt(value) });
  const defaults = { screenEntity: 1, screenPermanentEntity: 1, audioEntity: 1, audioPermanentEntity: 1,
    speechEntity: 0, speechMode: -1, phoneCallEntity: 0, turnByTurnEntity: 0 };
  const params = dict({
    resources: { kind: 'array', arrayValue: [dict({ resourceID: integer(1), transferType: integer(1) }),
      dict({ resourceID: integer(2), transferType: integer(3) })] },
    appStates: { kind: 'array', arrayValue: [dict({ appStateID: integer(3), state: { kind: 'boolean', boolValue: true } })] }
  });
  const next = Modes.applyChangeModes(defaults, params);
  assert.equal(next.screenEntity, 2);
  assert.equal(next.screenPermanentEntity, 2);
  assert.equal(next.audioEntity, 2);
  assert.equal(next.audioPermanentEntity, 1);
  assert.equal(next.turnByTurnEntity, 2);
  assert.equal(defaults.screenEntity, 1);
  const restored = Modes.applyChangeModes(next, dict({ resources: { kind: 'array', arrayValue: [
    dict({ resourceID: integer(2), transferType: integer(4) })] } }));
  assert.equal(restored.audioEntity, 1);
});