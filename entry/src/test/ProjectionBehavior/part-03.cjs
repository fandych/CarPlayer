const { assert, fs, path, vm, test, ts, sourceRoot, audioSenderFixture, loadEts, loadMethods,
  loadProjectionSettingsController, videoSenderFixture } = require('../ProjectionBehaviorSupport.cjs');

test('connection tab taps hit the full settings page without capturing content scrolling', () => {
  const shellSource = fs.readFileSync(path.join(sourceRoot, 'pages/ProjectionDashboardShell.ets'), 'utf8');
  const settingsSource = fs.readFileSync(
    path.join(sourceRoot, 'pages/ProjectionDashboardShellSettingsPage.ets'), 'utf8'
  );
  const connectionSource = fs.readFileSync(
    path.join(sourceRoot, 'pages/ProjectionConnectionSettingsPane.ets'), 'utf8'
  );
  assert.match(settingsSource, /onTouchBoundsChange\('settings', newArea\)/);
  assert.match(shellSource, /onTouchBoundsChange: this\.onTouchBoundsChange/);
  assert.match(connectionSource, /onAreaChange\(\(_oldArea, newArea\) => this\.onContentAreaChange\(newArea\)\)/);
  const Target = loadMethods('pages/ProjectionDashboard.ets', 'ProjectionDashboard', ['touchHandler'], {
    AppStorage: { get: key => ({
      carplayProjectionHomeActive: true, carplayProjectionDisplayId: 7
    })[key] }
  });
  const target = new Target();
  let activated = 0;
  target.canvasPixelToContentPoint = (x, y) => ({ x, y });
  target.dashboardView = 'settings';
  target.activeAppLabel = '';
  target.navigationPreview = false;
  target.touchBounds = new Map([
    ['settings', { left: 0, top: 0, right: 400, bottom: 300 }],
    ['settingsContent', { left: 100, top: 0, right: 400, bottom: 300 }]
  ]);
  target.touchAreas = new Map([['settings:tab-connect', {
    group: 'settings', left: 10, top: 20, right: 90, bottom: 70, action: () => { activated++; }
  }]]);
  target.touchHandler({ data: {
    displayId: 7, startX: 40, endX: 40, startY: 40, endY: 40, durationMs: 100
  } });
  assert.equal(activated, 1);
  const ScrollTarget = loadMethods('pages/ProjectionDashboardTouchController.ets', 'ProjectionDashboardTouchController', [
    'emptyBounds', 'scrollControllerAt'
  ]);
  const scrollTarget = new ScrollTarget();
  target.settingsScroller = {};
  assert.equal(scrollTarget.scrollControllerAt(target, 40, 40), undefined);
});

test('third-party virtual displays render at higher resolution with matching logical density', () => {
  const { projectionContentDisplayConfig } = loadEts('video/CarPlayVirtualDisplay.ets', {
    '@ohos.display': {},
    './ProjectionSettings': {
      isSupportedProjectionSize: () => true,
      PROJECTION_ENCODER_MAX_WIDTH: 4096,
      PROJECTION_ENCODER_MAX_HEIGHT: 2160
    }
  });
  assert.deepEqual(projectionContentDisplayConfig(1200, 700, 1.25), {
    width: 2400, height: 1400, density: 2.5, scale: 2
  });
  assert.deepEqual(projectionContentDisplayConfig(1200, 700, 2), {
    width: 1800, height: 1050, density: 3, scale: 1.5
  });
  assert.deepEqual(projectionContentDisplayConfig(5000, 2500, 2), {
    width: 4096, height: 2048, density: 1.6384, scale: 0.8192
  });
  assert.throws(() => projectionContentDisplayConfig(0, 700, 1), /Invalid virtual content display/);
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
  const shellLayoutSource = fs.readFileSync(path.join(sourceRoot, 'pages/ProjectionDashboardShellLayout.ets'), 'utf8');
  assert.match(shellLayoutSource,
    /\.scale\(\{ x: this\.contentScalePercent \/ 100, y: this\.contentScalePercent \/ 100 \}\)/);
});

test('content calibration persists independently for each display profile', () => {
  const writes = [];
  const controller = loadProjectionSettingsController({
    saveProjectionContentCalibration(displayUuid, control, value) {
      writes.push([displayUuid, control, value]);
      return control === 'scale' ? Math.min(100, Math.max(70, value)) : Math.min(15, Math.max(-15, value));
    }
  });
  const target = {
    vehicleDisplayUuid: 'display-a',
    contentScalePercent: 100,
    contentOffsetXPercent: 0,
    contentOffsetYPercent: 0,
    calibrationMessage: ''
  };
  controller.adjustContentCalibration(target, 'scale', -1);
  controller.adjustContentCalibration(target, 'offsetX', 1);
  target.vehicleDisplayUuid = 'display-b';
  controller.adjustContentCalibration(target, 'offsetY', -1);
  assert.deepEqual(writes, [
    ['display-a', 'scale', 99],
    ['display-a', 'offsetX', 1],
    ['display-b', 'offsetY', -1]
  ]);
  assert.equal(target.contentOffsetYPercent, -1);
});

test('AirPlay display profile uses /info dimensions and refuses invented or silently scaled sizes', () => {
  const settings = loadEts('video/ProjectionSettings.ets');
  const filename = path.join(sourceRoot, 'airplay/media/AirPlayDisplayInfo.ets');
  const source = fs.readFileSync(filename, 'utf8');
  const parsed = ts.createSourceFile(filename, source, ts.ScriptTarget.Latest, true);
  const declaration = parsed.statements.find(statement =>
    ts.isFunctionDeclaration(statement) && statement.name?.text === 'readDisplayInfo');
  const activeAreaDeclaration = parsed.statements.find(statement =>
    ts.isFunctionDeclaration(statement) && statement.name?.text === 'readActiveViewArea');
  assert.ok(declaration);
  assert.ok(activeAreaDeclaration);
  const javascript = ts.transpileModule(
    `${activeAreaDeclaration.getText(parsed).replace(/^export\s+/, '')}\n` +
      `${declaration.getText(parsed).replace(/^export\s+/, '')}\nreadDisplayInfo`, {
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

test('ArkTS iAP2 framing preserves checksums, stream recovery and parameter validation', () => {
  const { encodeIap2LinkFrame, scanIap2Link, encodeIap2Control, scanIap2Control,
    encodeIap2Parameter, decodeIap2Parameters } = loadEts('protocol/Iap2FrameCodec.ets');
  const payload = new Uint8Array([0x40, 0x40, 0, 6, 0x57, 3]);
  const frame = encodeIap2LinkFrame({
    control: 0x40, sequence: 12, acknowledgement: 9, sessionId: 1, payload
  });
  assert.equal(frame.reduce((sum, byte) => (sum + byte) & 0xff, 0), 0);
  assert.deepEqual(scanIap2Link(frame), { consumed: frame.length, frameOffset: 0, frameLength: frame.length });
  const corrupt = frame.slice();
  corrupt[9] ^= 1;
  assert.equal(scanIap2Link(corrupt).frameLength, 0);
  const control = encodeIap2Control(0xaa01, new Uint8Array([0x12, 0x34]));
  assert.deepEqual(scanIap2Control(control), {
    consumed: control.length, frameOffset: 0, frameLength: control.length
  });
  assert.equal(scanIap2Control(control.slice(0, 4)).frameLength, 0);
  const parameter = encodeIap2Parameter(0xabcd, new Uint8Array([0x12, 0x34]));
  assert.deepEqual(decodeIap2Parameters(parameter).map(item => [item.id, ...item.value]), [
    [0xabcd, 0x12, 0x34]
  ]);
  assert.throws(() => decodeIap2Parameters(new Uint8Array([0, 6, 0, 1, 0x12])), /parameter length/);
  assert.throws(() => encodeIap2LinkFrame({
    control: 0, sequence: 0, acknowledgement: 0, sessionId: 0, payload: new Uint8Array(65526)
  }), /too large/);
});

test('ArkTS TLV8 preserves continuation and duplicate-item semantics', () => {
  const { encodeTlv8, decodeTlv8 } = loadEts('airplay/Tlv8.ets');
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
  assert.throws(() => decodeTlv8(new Uint8Array([4])), /Malformed TLV8/);
  assert.throws(() => decodeTlv8(new Uint8Array([0xff, 1, 0])), /Malformed TLV8/);
});
