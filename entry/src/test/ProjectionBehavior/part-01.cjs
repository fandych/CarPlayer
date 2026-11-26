const { assert, fs, path, vm, test, ts, sourceRoot, audioSenderFixture, loadEts, loadMethods,
  loadProjectionSettingsController, videoSenderFixture } = require('../ProjectionBehaviorSupport.cjs');

test('capture, encoder, Dock, safe-area and day/night settings stay within supported defaults', () => {
  const {
    resolveProjectionRates, projectionTheme, resolveNightMode, PROJECTION_THEMES, PROJECTION_ACCENTS,
    normalizeSafeInset, projectionSafeInsetKey,
    projectionDisplayModes, resolveProjectionDisplayMode, projectionResolutionKey,
    projectionContentCalibrationKey, normalizeProjectionContentScale, normalizeProjectionContentOffset,
    isSupportedProjectionSize
  } = loadEts('video/ProjectionSettings.ets');
  assert.deepEqual(resolveProjectionRates(30, 60, 60), { capture: 30, encode: 30 });
  assert.deepEqual(resolveProjectionRates(60, 24, 60), { capture: 60, encode: 24 });
  assert.deepEqual(resolveProjectionRates(60, 60, 30), { capture: 30, encode: 30 });
  assert.deepEqual(resolveProjectionRates(NaN, -1, 999), { capture: 30, encode: 30 });
  assert.equal(projectionTheme('unknown').id, 'aurora');
  assert.equal(projectionTheme('aurora').background, '#10101C');
  assert.equal(projectionTheme('sunset').background, '#2B1033');
  assert.equal(projectionTheme('forest').background, '#0B1F1A');
  assert.equal(projectionTheme('forest').surface, '#262630');
  assert.equal(projectionTheme('forest').panel, '#1E1E26');
  assert.equal(projectionTheme('graphite').background, '#16161A');
  assert.equal(projectionTheme('ocean').background, '#06102A');
  assert.deepEqual(PROJECTION_THEMES.map(theme => theme.id),
    ['aurora', 'sunset', 'forest', 'ocean', 'graphite']);
  assert.deepEqual(PROJECTION_ACCENTS, [
    '#0A84FF', '#30D158', '#FF9F0A', '#FF375F', '#BF5AF2', '#64D2FF'
  ]);
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

test('projection settings match the reference glass palette and two-pane layout', () => {
  const source = fs.readFileSync(path.join(sourceRoot, 'pages/ProjectionDashboard.ets'), 'utf8');
  const shellSource = fs.readFileSync(path.join(sourceRoot, 'pages/ProjectionDashboardShell.ets'), 'utf8');
  const shellContentSource = fs.readFileSync(
    path.join(sourceRoot, 'pages/ProjectionDashboardShellContent.ets'), 'utf8'
  );
  const shellSettingsSource = fs.readFileSync(
    path.join(sourceRoot, 'pages/ProjectionDashboardShellSettingsPage.ets'), 'utf8'
  );
  const shellLayoutSource = fs.readFileSync(
    path.join(sourceRoot, 'pages/ProjectionDashboardShellLayout.ets'), 'utf8'
  );
  const contentSource = fs.readFileSync(path.join(sourceRoot, 'pages/ProjectionDashboardContent.ets'), 'utf8');
  const displaySource = fs.readFileSync(path.join(sourceRoot, 'pages/ProjectionDisplaySettingsPane.ets'), 'utf8');
  const calibrationSource = fs.readFileSync(
    path.join(sourceRoot, 'pages/ProjectionDisplayCalibrationControls.ets'), 'utf8'
  );
  const connectionSource = fs.readFileSync(
    path.join(sourceRoot, 'pages/ProjectionConnectionSettingsPane.ets'), 'utf8'
  );
  const routerSource = fs.readFileSync(path.join(sourceRoot, 'pages/ProjectionTouchRouter.ets'), 'utf8');
  const dropdownSource = fs.readFileSync(path.join(sourceRoot, 'pages/ProjectionSettingsDropdown.ets'), 'utf8');
  const presentationSource = fs.readFileSync(
    path.join(sourceRoot, 'pages/ProjectionDashboardPresentationController.ets'), 'utf8'
  );
  const componentSource =
    `${source}\n${shellSource}\n${shellContentSource}\n${shellSettingsSource}\n${shellLayoutSource}\n` +
    `${contentSource}\n${displaySource}\n${calibrationSource}\n${dropdownSource}\n${presentationSource}`;
  assert.match(shellSettingsSource, /app\.media\.ic_day_night/);
  assert.match(shellSettingsSource, /settingsPanelColor/);
  assert.match(shellSettingsSource, /settingsGroupColor/);
  assert.match(shellSettingsSource, /settingsSeparatorColor/);
  assert.doesNotMatch(componentSource, /#DCE4DE|#AAB8AF/);
  assert.match(displaySource, /\.height\(42\)\.padding\(\{ left: 9, right: 9 \}\)/);
  const settings = loadEts('video/ProjectionSettings.ets');
  const { ProjectionDashboardPresentationController } = loadEts(
    'pages/ProjectionDashboardPresentationController.ets',
    { '../video/ProjectionSettings': settings }
  );
  const presentation = new ProjectionDashboardPresentationController();
  const nightAppearance = { dayNightMode: 'NIGHT', nightMode: false, theme: 'aurora' };
  const dayAppearance = { ...nightAppearance, dayNightMode: 'DAY' };
  assert.equal(presentation.glassPanelColor(nightAppearance), '#75262630');
  assert.equal(presentation.primaryTextColor(nightAppearance), '#FFFFFF');
  assert.equal(presentation.glassStrokeColor(nightAppearance), '#38FFFFFF');
  assert.equal(presentation.glassPanelColor(dayAppearance), '#85FFFFFF');
  assert.equal(presentation.primaryTextColor(dayAppearance), '#1C1C1E');
  assert.equal(presentation.glassStrokeColor(dayAppearance), '#BFFFFFFF');
  assert.doesNotMatch(componentSource, /#FFFFFF(?:14|1F|38|55|6B|80|85|9E|A6|B8|BF|D9)|#0000000D|#3C3C43A6|#3C3C4399/);
  assert.match(componentSource, /colorWithAlpha\(this\.accent, 'D9'\)|#D9\$\{this\.accent\.slice\(1\)\}/);
  assert.match(componentSource, /\.border\(\{ width: 1, color: this\.glassStrokeColor(?:\(\))? \}\)/);
  assert.match(shellLayoutSource, /\.brightness\(0\.5 \+ this\.displayBrightness \/ 200\)/);
  assert.equal((componentSource.match(/backgroundColor\('#6BFFFFFF'\)/g) || []).length, 2);
  assert.ok(shellSettingsSource.includes('ProjectionConnectionSettingsPane({'));
  assert.ok(connectionSource.includes('Toggle({ type: ToggleType.Switch'));
  assert.ok(displaySource.includes('Slider({ value: this.displayBrightness'));
  assert.ok(contentSource.includes('.layoutWeight(this.splitMapRatio)'));
  assert.ok(contentSource.includes('.layoutWeight(this.splitMusicRatio)'));
  const mainPanelStart = contentSource.indexOf('private MainPanel()');
  const mainPanelEnd = contentSource.indexOf('\n  build()', mainPanelStart);
  const mainPanelSource = contentSource.slice(mainPanelStart, mainPanelEnd);
  assert.match(mainPanelSource, /\.width\('100%'\)\.height\('100%'\)/);
  assert.doesNotMatch(mainPanelSource, /\.width\(this\.verticalDock \? '0%'/);
  assert.match(shellContentSource, /\.layoutWeight\(1\)/);
  assert.match(displaySource, /this\.SplitRatioControl\('map'\)/);
  assert.match(displaySource, /this\.SplitRatioControl\('music'\)/);
  assert.match(displaySource, /\.type\(InputType\.Number\)/);
  assert.match(routerSource, /previous\.drag\(point\.x\)/);
  assert.match(calibrationSource, /Text\(`\$\{edge === 'top' \? this\.safeInsetTop/);
  assert.match(calibrationSource, /Text\(`\$\{control === 'scale' \? this\.contentScalePercent/);
  assert.ok(displaySource.includes("Text('−').fontSize(26).fontWeight(FontWeight.Bold)"));
  assert.ok(displaySource.includes("Text('+').fontSize(26).fontWeight(FontWeight.Bold)"));
  assert.doesNotMatch(componentSource, /ForEach\(\[3, 4, 5\]/);
  const target = loadProjectionSettingsController();
  const state = { dayNightMode: 'DAY' };
  target.selectDayNightMode(state, 'NIGHT');
  assert.equal(state.dayNightMode, 'NIGHT');
  target.selectDayNightMode(state, 'AUTO');
  assert.equal(state.dayNightMode, 'AUTO');
});

test('split pane ratios default to 3:2, persist independently and stay within 1–10', () => {
  const previousAppStorage = global.AppStorage;
  const previousPersistentStorage = global.PersistentStorage;
  const stored = new Map();
  global.AppStorage = {
    get: key => stored.get(key),
    setOrCreate: (key, value) => stored.set(key, value)
  };
  global.PersistentStorage = {
    persistProp(key, value) {
      if (!stored.has(key)) stored.set(key, value);
    }
  };
  try {
    const settings = loadEts('video/ProjectionSettings.ets');
    assert.equal(settings.readProjectionSplitRatio('map'), 3);
    assert.equal(settings.readProjectionSplitRatio('music'), 2);
    assert.equal(settings.normalizeProjectionSplitRatio(0), 1);
    assert.equal(settings.normalizeProjectionSplitRatio(11), 10);
    assert.equal(settings.normalizeProjectionSplitRatio(Number.NaN), 3);
    assert.equal(settings.saveProjectionSplitRatio('map', 7), 7);
    assert.equal(settings.saveProjectionSplitRatio('music', -2), 1);
    assert.equal(settings.readProjectionSplitRatio('map'), 7);
    assert.equal(settings.readProjectionSplitRatio('music'), 1);
  } finally {
    if (previousAppStorage === undefined) delete global.AppStorage;
    else global.AppStorage = previousAppStorage;
    if (previousPersistentStorage === undefined) delete global.PersistentStorage;
    else global.PersistentStorage = previousPersistentStorage;
  }
});

test('projection touch reports update slider values during drag', () => {
  const Target = loadMethods('pages/ProjectionDashboard.ets', 'ProjectionDashboard', [
    'handleTouchReport', 'scrollControllerAt', 'setDisplayBrightnessFromTouch'
  ], {
    AppStorage: { get: key => ({
      carplayProjectionHomeActive: true, carplayProjectionDisplayId: 7
    })[key] }
  });
  const target = new Target();
  target.settingsController = loadProjectionSettingsController();
  const sliderBounds = { left: 10, top: 10, right: 110, bottom: 40 };
  target.displayBrightness = 80;
  target.dashboardView = 'settings';
  target.touchAreas = new Map([['settings:brightness', {
    group: 'settings', ...sliderBounds,
    action() {}, drag: x => target.setDisplayBrightnessFromTouch(x, sliderBounds)
  }]]);
  target.touchBounds = new Map([['settings', { left: 0, top: 0, right: 120, bottom: 60 }]]);
  target.touchScrollState = undefined;
  target.canvasPixelToContentPoint = (x, y) => ({ x, y });
  target.scrollControllerAt = () => undefined;
  const report = x => ({
    displayId: 7, contacts: [{ id: 1, down: true, x, y: 20 }]
  });
  target.handleTouchReport(report(20));
  target.handleTouchReport(report(90));
  assert.equal(target.displayBrightness, 84);
  target.handleTouchReport(report(200));
  assert.equal(target.displayBrightness, 100);
});

test('split ratio inputs and steppers validate and clamp both panes to 1–10', () => {
  const target = loadProjectionSettingsController({
    saveProjectionSplitRatio: (pane, value) => Math.max(1, Math.min(10, Math.round(value)))
  });
  const state = {
    splitMapRatio: 3,
    splitMusicRatio: 2,
    splitMapRatioInput: '3',
    splitMusicRatioInput: '2',
    splitRatioMessage: ''
  };
  target.updateSplitRatioInput(state, 'map', '10');
  assert.equal(state.splitMapRatio, 10);
  target.updateSplitRatioInput(state, 'map', '11');
  assert.equal(state.splitMapRatio, 10);
  assert.equal(state.splitMapRatioInput, '11');
  assert.match(state.splitRatioMessage, /1–10/);
  target.restoreSplitRatioInput(state, 'map');
  assert.equal(state.splitMapRatioInput, '10');
  assert.match(state.splitRatioMessage, /1–10/);
  target.adjustSplitRatio(state, 'music', -1);
  assert.equal(state.splitMusicRatio, 1);
  assert.equal(state.splitRatioMessage, '');
  target.adjustSplitRatio(state, 'music', -1);
  assert.equal(state.splitMusicRatio, 1);
});
