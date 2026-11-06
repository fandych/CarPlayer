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
  const contentSource = fs.readFileSync(path.join(sourceRoot, 'pages/ProjectionDashboardContent.ets'), 'utf8');
  const displaySource = fs.readFileSync(path.join(sourceRoot, 'pages/ProjectionDisplaySettingsPane.ets'), 'utf8');
  const connectionSource = fs.readFileSync(
    path.join(sourceRoot, 'pages/ProjectionConnectionSettingsPane.ets'), 'utf8'
  );
  const routerSource = fs.readFileSync(path.join(sourceRoot, 'pages/ProjectionTouchRouter.ets'), 'utf8');
  const dropdownSource = fs.readFileSync(path.join(sourceRoot, 'pages/ProjectionSettingsDropdown.ets'), 'utf8');
  const componentSource = `${source}\n${shellSource}\n${contentSource}\n${displaySource}\n${dropdownSource}`;
  assert.match(shellSource, /app\.media\.ic_day_night/);
  assert.match(shellSource, /settingsPanelColor/);
  assert.match(shellSource, /settingsGroupColor/);
  assert.match(shellSource, /settingsSeparatorColor/);
  assert.doesNotMatch(componentSource, /#DCE4DE|#AAB8AF/);
  assert.match(displaySource, /\.height\(42\)\.padding\(\{ left: 9, right: 9 \}\)/);
  assert.match(source, /this\.isLightAppearance\(\) \? '#85FFFFFF' : this\.colorWithAlpha\(projectionTheme\(this\.theme\)\.surface, '75'\)/);
  assert.match(source, /this\.isLightAppearance\(\) \? '#1C1C1E' : '#FFFFFF'/);
  assert.match(source, /this\.isLightAppearance\(\) \? '#BFFFFFFF' : '#38FFFFFF'/);
  assert.doesNotMatch(componentSource, /#FFFFFF(?:14|1F|38|55|6B|80|85|9E|A6|B8|BF|D9)|#0000000D|#3C3C43A6|#3C3C4399/);
  assert.match(componentSource, /colorWithAlpha\(this\.accent, 'D9'\)|#D9\$\{this\.accent\.slice\(1\)\}/);
  assert.match(componentSource, /\.border\(\{ width: 1, color: this\.glassStrokeColor(?:\(\))? \}\)/);
  assert.match(shellSource, /\.brightness\(0\.5 \+ this\.displayBrightness \/ 200\)/);
  assert.equal((componentSource.match(/backgroundColor\('#6BFFFFFF'\)/g) || []).length, 2);
  assert.ok(shellSource.includes('ProjectionConnectionSettingsPane({'));
  assert.ok(connectionSource.includes('Toggle({ type: ToggleType.Switch'));
  assert.ok(displaySource.includes('Slider({ value: this.displayBrightness'));
  assert.ok(contentSource.includes('.layoutWeight(this.splitMapRatio)'));
  assert.ok(contentSource.includes('.layoutWeight(this.splitMusicRatio)'));
  const mainPanelStart = contentSource.indexOf('private MainPanel()');
  const mainPanelEnd = contentSource.indexOf('\n  build()', mainPanelStart);
  const mainPanelSource = contentSource.slice(mainPanelStart, mainPanelEnd);
  assert.match(mainPanelSource, /\.width\('100%'\)\.height\('100%'\)/);
  assert.doesNotMatch(mainPanelSource, /\.width\(this\.verticalDock \? '0%'/);
  assert.match(shellSource, /private Content\(\)[\s\S]*?\.layoutWeight\(1\)/);
  assert.match(displaySource, /this\.SplitRatioControl\('map'\)/);
  assert.match(displaySource, /this\.SplitRatioControl\('music'\)/);
  assert.match(displaySource, /\.type\(InputType\.Number\)/);
  assert.match(routerSource, /previous\.drag\(point\.x\)/);
  assert.match(displaySource, /Text\(`\$\{edge === 'top' \? this\.safeInsetTop/);
  assert.match(displaySource, /Text\(`\$\{control === 'scale' \? this\.contentScalePercent/);
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

test('split ratio stepper taps update layout values through the projection touch router', () => {
  const source = fs.readFileSync(path.join(sourceRoot, 'pages/ProjectionDashboard.ets'), 'utf8');
  const displaySource = fs.readFileSync(path.join(sourceRoot, 'pages/ProjectionDisplaySettingsPane.ets'), 'utf8');
  assert.match(source, /this\.touchRouter\.handleTap\(/);
  assert.match(displaySource, /`splitRatio-\$\{pane\}-minus`[\s\S]*onSplitRatioAdjust\(pane, -1\)/);
  assert.match(displaySource, /`splitRatio-\$\{pane\}-plus`[\s\S]*onSplitRatioAdjust\(pane, 1\)/);
  const { ProjectionTouchRouter } = loadEts('pages/ProjectionTouchRouter.ets');
  const router = new ProjectionTouchRouter();
  const controller = loadProjectionSettingsController({
    saveProjectionSplitRatio: (pane, value) => Math.max(1, Math.min(10, Math.round(value)))
  });
  const state = {
    splitMapRatio: 3, splitMusicRatio: 2, splitMapRatioInput: '3', splitMusicRatioInput: '2',
    splitRatioMessage: ''
  };
  router.touchBounds.set('settings', { left: 0, top: 0, right: 400, bottom: 300 });
  let touchActions = 0;
  router.touchAreas = new Map([
    ['map-plus', {
      group: 'settings', left: 10, top: 20, right: 50, bottom: 60,
      action: () => {
        touchActions++;
        controller.adjustSplitRatio(state, 'map', 1);
      }
    }],
    ['music-minus', {
      group: 'settings', left: 60, top: 20, right: 100, bottom: 60,
      action: () => {
        touchActions++;
        controller.adjustSplitRatio(state, 'music', -1);
      }
    }]
  ]);
  const tap = x => ({
    displayId: 7, startX: x, endX: x, startY: 40, endY: 40
  });
  router.handleTap(tap(30), true, 7, 'settings', '', false, (x, y) => ({ x, y }));
  router.handleTap(tap(80), true, 7, 'settings', '', false, (x, y) => ({ x, y }));
  assert.equal(touchActions, 2);
  assert.equal(state.splitMapRatio, 4);
  assert.equal(state.splitMusicRatio, 1);
});

test('settings dropdowns select values from both local and receiver touch paths', () => {
  const source = fs.readFileSync(path.join(sourceRoot, 'pages/ProjectionDashboard.ets'), 'utf8');
  const shellSource = fs.readFileSync(path.join(sourceRoot, 'pages/ProjectionDashboardShell.ets'), 'utf8');
  const dropdownSource = fs.readFileSync(path.join(sourceRoot, 'pages/ProjectionSettingsDropdown.ets'), 'utf8');
  const connectionSource = fs.readFileSync(
    path.join(sourceRoot, 'pages/ProjectionConnectionSettingsPane.ets'), 'utf8'
  );
  assert.match(shellSource, /onDropdownToggle: \(key: string\)/);
  assert.match(shellSource, /onDropdownSelect: \(key: string, index: number\)/);
  assert.match(connectionSource, /dropdownKey: 'encoderFps'/);
  assert.match(connectionSource, /dropdownKey: 'captureFps'/);
  assert.match(source, /this\.chooseSettingsDropdownOption\(/);
  assert.match(dropdownSource, /dropdown-\$\{this\.dropdownKey\}-trigger/);
  assert.match(dropdownSource, /dropdown-\$\{this\.dropdownKey\}-option-\$\{index\}/);

  const Target = loadMethods('pages/ProjectionDashboard.ets', 'ProjectionDashboard', [
    'toggleSettingsDropdown', 'closeSettingsDropdown', 'clearSettingsDropdownAreas',
    'chooseSettingsDropdownOption'
  ]);
  const target = new Target();
  target.activeSettingsDropdown = '';
  target.touchAreas = new Map([
    ['settings:dropdown-encoderFps-option-0', {}],
    ['settings:dropdown-captureFps-option-0', {}]
  ]);
  target.toggleSettingsDropdown('encoderFps');
  assert.equal(target.activeSettingsDropdown, 'encoderFps');
  target.toggleSettingsDropdown('captureFps');
  assert.equal(target.activeSettingsDropdown, 'captureFps');
  assert.equal(target.touchAreas.has('settings:dropdown-encoderFps-option-0'), false);

  let selectedIndex = -1;
  target.chooseSettingsDropdownOption('captureFps', 1, index => { selectedIndex = index; });
  assert.equal(selectedIndex, 1);
  assert.equal(target.activeSettingsDropdown, '');
  assert.equal(target.touchAreas.has('settings:dropdown-captureFps-option-0'), false);

  const settingsController = loadProjectionSettingsController();
  const settingsState = { encoderFps: 30, captureFps: 30 };
  settingsController.selectEncoderFps(settingsState, 0);
  assert.equal(settingsState.encoderFps, 30);
  settingsController.selectEncoderFps(settingsState, 1);
  assert.equal(settingsState.encoderFps, 60);
  assert.equal(settingsState.captureFps, 60);
  settingsController.selectEncoderFps(settingsState, 0);
  assert.equal(settingsState.encoderFps, 30);
  settingsController.selectEncoderFps(settingsState, 99);
  assert.equal(settingsState.encoderFps, 30);
  settingsState.encoderFps = 24;
  settingsController.normalizeEncoderFps(settingsState);
  assert.equal(settingsState.encoderFps, 30);
  settingsState.captureFps = 60;
  settingsController.selectCaptureFps(settingsState, 0);
  assert.equal(settingsState.captureFps, 30);
});

test('accepted launch statuses are logged rather than rendered over app surfaces', () => {
  const source = fs.readFileSync(path.join(sourceRoot, 'pages/ProjectionHome.ets'), 'utf8');
  assert.doesNotMatch(source, /this\.launchMessage\s*=\s*`[^`]*请求已受理/);
  assert.match(source, /this\.logProjection\(`应用启动请求已受理/);
  assert.match(source, /this\.launchMessage = `应用链接打开失败/);
});

test('apps list icons are not wrapped in an extra colored background tile', () => {
  const source = fs.readFileSync(path.join(sourceRoot, 'pages/ProjectionAppsPage.ets'), 'utf8');
  const tileStart = source.indexOf('struct ProjectionAppTile');
  const tileEnd = source.indexOf('@Component', tileStart + 1);
  const tileSource = source.slice(tileStart, tileEnd);
  assert.ok(tileStart >= 0);
  assert.doesNotMatch(tileSource, /\.backgroundColor\(app\.color\)/);
  assert.doesNotMatch(tileSource, /\.shadow\(\{ radius: 14/);
  assert.match(tileSource, /ProjectionAppIcon\(\{ app: this\.app, iconSize: 42/);
  assert.match(tileSource, /Text\(this\.app\.label\)/);
});

test('projection wallpapers, accents and map colors match the HTML reference', () => {
  const { PROJECTION_THEMES, PROJECTION_ACCENTS } = loadEts('video/ProjectionSettings.ets');
  const html = fs.readFileSync(path.resolve(__dirname, '../../../docs/carplay.html'), 'utf8').toLowerCase();
  const mediaRoot = path.resolve(sourceRoot, '..', 'resources', 'base', 'media');
  const walls = [
    ['aurora', ['#3a2bd6', '#d6336c', '#0e9aa7', '#10101c']],
    ['sunset', ['#ff9f0a', '#ff375f', '#2b1033']],
    ['forest', ['#30d158', '#0a6f8f', '#0b1f1a']],
    ['ocean', ['#0a84ff', '#5e5ce6', '#06102a']],
    ['graphite', ['#4a4a55', '#16161a']]
  ];
  assert.deepEqual(PROJECTION_THEMES.map(theme => theme.id), walls.map(([id]) => id));
  for (const [id, colors] of walls) {
    const asset = fs.readFileSync(path.join(mediaRoot, `projection_${id}.svg`), 'utf8').toLowerCase();
    for (const color of colors) {
      assert.ok(html.includes(color), `HTML is missing ${color}`);
      assert.ok(asset.includes(color), `${id} wallpaper is missing ${color}`);
    }
  }
  for (const color of PROJECTION_ACCENTS) {
    assert.ok(html.includes(color.toLowerCase()), `HTML is missing accent ${color}`);
  }
  const lightMap = fs.readFileSync(path.join(mediaRoot, 'projection_map_preview_light.svg'), 'utf8');
  for (const color of ['#E9E7E1', '#FFFFFF', '#FFF6D8', '#CFE6C3', '#AED3F2', '#CFCBC2', '#3C3C43']) {
    assert.ok(lightMap.includes(color), `Light map is missing ${color}`);
  }
  const weather = fs.readFileSync(path.join(mediaRoot, 'projection_weather_card.svg'), 'utf8');
  assert.match(weather, /stop-color="#409CFF" stop-opacity="\.55"/);
  assert.match(weather, /stop-color="#0A3CA0" stop-opacity="\.45"/);
});

test('dashboard text and glass colors switch between the exact HTML dark and light palettes', () => {
  const { projectionTheme, resolveNightMode } = loadEts('video/ProjectionSettings.ets');
  const Target = loadMethods('pages/ProjectionDashboard.ets', 'ProjectionDashboard', [
    'isLightAppearance', 'colorWithAlpha', 'primaryTextColor', 'secondaryTextColor', 'mutedTextColor',
    'mapBackgroundColor', 'glassStrokeColor', 'cardStrokeColor', 'glassSecondaryColor', 'glassPanelColor',
    'glassSurfaceColor', 'settingsPanelColor', 'settingsGroupColor', 'settingsSeparatorColor'
  ], { projectionTheme, resolveNightMode });
  const target = new Target();
  target.theme = 'aurora';
  target.dayNightMode = 'NIGHT';
  target.nightMode = false;
  assert.equal(target.isLightAppearance(), false);
  assert.equal(target.primaryTextColor(), '#FFFFFF');
  assert.equal(target.secondaryTextColor(), '#9EFFFFFF');
  assert.equal(target.mutedTextColor(), '#80FFFFFF');
  assert.equal(target.mapBackgroundColor(), '#1D2230');
  assert.equal(target.glassPanelColor(), '#75262630');
  assert.equal(target.glassSurfaceColor(), '#9E1E1E26');
  assert.equal(target.glassStrokeColor(), '#38FFFFFF');
  assert.equal(target.cardStrokeColor(), '#20FFFFFF');
  assert.equal(target.glassSecondaryColor(), '#14FFFFFF');
  assert.equal(target.settingsPanelColor(), '#75262630');
  assert.equal(target.settingsGroupColor(), '#14FFFFFF');
  assert.equal(target.settingsSeparatorColor(), '#1FFFFFFF');
  assert.equal(target.colorWithAlpha('#0A84FF', 'D9'), '#D90A84FF');

  target.dayNightMode = 'DAY';
  assert.equal(target.isLightAppearance(), true);
  assert.equal(target.primaryTextColor(), '#1C1C1E');
  assert.equal(target.secondaryTextColor(), '#A63C3C43');
  assert.equal(target.mutedTextColor(), '#993C3C43');
  assert.equal(target.mapBackgroundColor(), '#E9E7E1');
  assert.equal(target.glassPanelColor(), '#85FFFFFF');
  assert.equal(target.glassSurfaceColor(), '#B8FFFFFF');
  assert.equal(target.glassStrokeColor(), '#BFFFFFFF');
  assert.equal(target.cardStrokeColor(), '#243C3C43');
  assert.equal(target.glassSecondaryColor(), '#0D000000');
  assert.equal(target.settingsPanelColor(), '#85FFFFFF');
  assert.equal(target.settingsGroupColor(), '#0D000000');
  assert.equal(target.settingsSeparatorColor(), '#243C3C43');
});

test('wallpaper, map and light-mode icon resources follow the selected appearance', () => {
  const { resolveNightMode } = loadEts('video/ProjectionSettings.ets');
  const Target = loadMethods('pages/ProjectionDashboard.ets', 'ProjectionDashboard', [
    'isLightAppearance', 'wallpaperResource', 'mapPreviewResource',
    'dockIconResource', 'settingsIconResource'
  ], { $r: (resource) => resource, resolveNightMode });
  const target = new Target();
  target.dayNightMode = 'NIGHT';
  target.nightMode = false;
  assert.equal(target.wallpaperResource('aurora'), 'app.media.projection_aurora');
  assert.equal(target.wallpaperResource('sunset'), 'app.media.projection_sunset');
  assert.equal(target.wallpaperResource('forest'), 'app.media.projection_forest');
  assert.equal(target.wallpaperResource('ocean'), 'app.media.projection_ocean');
  assert.equal(target.wallpaperResource('graphite'), 'app.media.projection_graphite');
  assert.equal(target.mapPreviewResource(), 'app.media.projection_map_preview');
  target.dayNightMode = 'DAY';
  assert.equal(target.mapPreviewResource(), 'app.media.projection_map_preview_light');
  assert.equal(target.dockIconResource('app.media.ic_house', false), 'app.media.ic_house_light');
  assert.equal(target.dockIconResource('app.media.ic_house', true), 'app.media.ic_house');
  assert.equal(
    target.settingsIconResource('app.media.ic_day_night_light', 'app.media.ic_day_night'),
    'app.media.ic_day_night_light'
  );
  assert.equal(
    target.settingsIconResource('app.media.ic_day_night_light', 'app.media.ic_day_night', true),
    'app.media.ic_day_night'
  );
});

test('phone home button has no horizontal sheen but keeps its circular shadow and action', () => {
  const source = fs.readFileSync(path.join(sourceRoot, 'pages/HomePage.ets'), 'utf8');
  assert.doesNotMatch(source, /backgroundColor\('#38FFFFFF'\)/);
  assert.match(source, /\.shadow\(\{ radius: 32, color: this\.statusColor, offsetX: 0, offsetY: 18 \}\)/);
  assert.match(source, /\.onClick\(\(\) => this\.onAction\(\)\)/);
});

test('connection tab taps hit the full settings page without capturing content scrolling', () => {
  const shellSource = fs.readFileSync(path.join(sourceRoot, 'pages/ProjectionDashboardShell.ets'), 'utf8');
  const connectionSource = fs.readFileSync(
    path.join(sourceRoot, 'pages/ProjectionConnectionSettingsPane.ets'), 'utf8'
  );
  assert.match(shellSource, /onTouchBoundsChange\('settings', newArea\)/);
  assert.match(connectionSource, /onAreaChange\(\(_oldArea, newArea\) => this\.onContentAreaChange\(newArea\)\)/);
  const Target = loadMethods('pages/ProjectionDashboard.ets', 'ProjectionDashboard', [
    'touchHandler', 'scrollControllerAt'
  ], {
    AppStorage: { get: key => ({
      carplayProjectionHomeActive: true, carplayProjectionDisplayId: 7
    })[key] }
  });
  const target = new Target();
  let activated = 0;
  target.getUIContext = () => ({ px2vp: value => value });
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
  target.canvasPixelToContentPoint = (x, y) => ({ x, y });
  target.touchHandler({ data: {
    displayId: 7, startX: 40, endX: 40, startY: 40, endY: 40, durationMs: 100
  } });
  assert.equal(activated, 1);
  assert.equal(target.scrollControllerAt(40, 40), undefined);
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
  const shellSource = fs.readFileSync(path.join(sourceRoot, 'pages/ProjectionDashboardShell.ets'), 'utf8');
  assert.match(shellSource,
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
  const filename = path.join(sourceRoot, 'airplay/media/AirPlayMediaHelpers.ets');
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
    assert.equal(stored.get('carplayTheme'), 'aurora');
    assert.equal(stored.get('carplayAccent'), '#0A84FF');
    assert.equal(stored.get('carplayDayNightMode'), 'NIGHT');
    assert.equal(calls.filter(key => key === 'carplayDockPosition').length, 1);
    assert.equal(calls.filter(key => key === 'carplayDayNightMode').length, 1);
  }

  const savedTheme = new Map([['carplayTheme', 'forest'], ['carplayAccent', '#FF9F0A']]);
  const preservedExports = {};
  vm.runInNewContext(javascript, {
    exports: preservedExports,
    PersistentStorage: {
      persistProp(key, value) {
        if (!savedTheme.has(key)) savedTheme.set(key, value);
      }
    }
  });
  preservedExports.initializeProjectionSettings();
  assert.equal(savedTheme.get('carplayTheme'), 'forest');
  assert.equal(savedTheme.get('carplayAccent'), '#FF9F0A');
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
  const { ProjectionTouchRouter } = loadEts('pages/ProjectionTouchRouter.ets');
  target.touchRouter = new ProjectionTouchRouter();
  let toggles = 0;
  target.getUIContext = () => ({ px2vp: value => value });
  target.viewAreaOriginX = 0;
  target.viewAreaOriginY = 0;
  target.screenToContentPoint = (x, y) => ({ x, y });
  target.touchRouter.touchBounds = new Map([['settings', { left: 0, top: 0, right: 20, bottom: 20 }]]);
  target.touchRouter.touchAreas = new Map([['settings:bluetoothAudio', {
    group: 'settings', left: 0, top: 0, right: 20, bottom: 20, action: () => { toggles++; }
  }]]);
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
  assert.equal(PROJECTION_APP_CANDIDATES.length, 10);
  for (const app of PROJECTION_APP_CANDIDATES) {
    assert.ok(app.icon, app.label);
    assert.ok(app.category === 'map' || app.category === 'music');
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
  const petal = PROJECTION_APP_CANDIDATES.find(app => app.appId === 'petal-maps');
  assert.equal(petal.label, '地图');
  assert.equal(petal.bundleName, 'com.huawei.hmos.maps.app');
  assert.equal(petal.launchTarget.uri, 'petalmaps://');
  const tangxin = PROJECTION_APP_CANDIDATES.find(app => app.appId === 'tangshui-music');
  assert.equal(tangxin.bundleName, 'com.salmon.sweetmusic');
  assert.equal(tangxin.launchTarget.uri, 'sweetmusic://');
  const kuwo = PROJECTION_APP_CANDIDATES.find(app => app.appId === 'kuwo-music');
  assert.equal(kuwo.bundleName, 'com.hmkuwo.cn');
  assert.equal(kuwo.abilityName, 'KuWoAbility');
  assert.equal(kuwo.launchTarget.uri, 'kwapp://');
  assert.equal(PROJECTION_APP_CANDIDATES.find(app => app.appId === 'kugou-music').launchTarget.uri,
    'kugou://m.kugou.com');
  assert.deepEqual(PROJECTION_VEHICLE_APPS.map(app => app.view), ['receiver', 'settings', 'themes', 'split']);
  const probedLinks = [];
  const resolved = await resolveProjectionApps(uri => {
    probedLinks.push(uri);
    return [
      'amapuri://',
      'baidumap://map',
      'petalmaps://',
      'qqmap://',
      'hwmusic://com.huawei.hmsapp.music',
      'qqmusic://',
      'orpheus://',
      'kugou://m.kugou.com',
      'sweetmusic://',
      'kwapp://'
    ].includes(uri);
  });
  assert.deepEqual(resolved.filter(app => app.launchState === 'VERIFIED').map(app => app.appId),
    ['amap', 'baidu-map', 'petal-maps', 'tencent-map', 'huawei-music', 'qq-music', 'netease-music',
      'kugou-music', 'tangshui-music', 'kuwo-music']);
  assert.ok(probedLinks.includes('amapuri://'));
  assert.ok(probedLinks.includes('baidumap://map'));
  assert.ok(probedLinks.includes('petalmaps://'));
  assert.ok(probedLinks.includes('qqmap://'));
  assert.ok(probedLinks.includes('hwmusic://com.huawei.hmsapp.music'));
  assert.ok(probedLinks.includes('qqmusic://'));
  assert.ok(probedLinks.includes('orpheus://'));
  assert.ok(probedLinks.includes('kugou://m.kugou.com'));
  assert.ok(probedLinks.includes('sweetmusic://'));
  assert.ok(probedLinks.includes('kwapp://'));
  for (const uri of ['snssdk1128://', 'kwai://', 'emoh://eastmoney.com', 'tenvideo2://']) {
    assert.equal(probedLinks.includes(uri), false);
  }
  const moduleManifest = fs.readFileSync(path.join(sourceRoot, '../module.json5'), 'utf8');
  for (const scheme of [
    'amapuri', 'baidumap', 'petalmaps', 'hwmusic', 'qqmap', 'qqmusic', 'orpheus', 'kugou', 'sweetmusic',
    'kwapp'
  ]) {
    assert.match(moduleManifest, new RegExp(`"${scheme}"`), `querySchemes must include ${scheme}`);
  }
  assert.doesNotMatch(moduleManifest, /ohos\.permission\.GET_BUNDLE_INFO/);
  assert.doesNotMatch(moduleManifest, /"snssdk1128"|"kwai"|"emoh"|"tenvideo2"/);
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
    'kugou-music': 'app_kugou'
  };
  const media = path.join(sourceRoot, '../resources/base/media');
  for (const [appId, iconName] of Object.entries(legacyIcons)) {
    const app = PROJECTION_APP_CANDIDATES.find(candidate => candidate.appId === appId);
    assert.equal(app.icon, `app.media.${iconName}`);
    assert.ok(fs.existsSync(path.join(media, `${iconName}.png`)), `missing icon for ${appId}`);
  }
});

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
  assert.match(content, /surfaceName: 'projectionSplitMapSurface',\s*landscape: true/);
  assert.match(content, /surfaceName: 'projectionAppSurface',\s*landscape: this\.isActiveMap\(\)/);
  assert.match(content, /this\.viewportWidth > 0 && this\.viewportHeight > 0/);
  assert.match(content, /onSurfaceChange\(this\.surfaceId, newArea, true\)/);
});

test('log export menu sits above the page sheet and success waits for file close', async () => {
  const source = fs.readFileSync(path.join(sourceRoot, 'pages/Index.ets'), 'utf8');
  assert.ok(source.indexOf('this.PageSheet()') < source.indexOf('IndexMenuOverlay({'));
  const sheetStart = source.indexOf('  PageSheet()');
  const sheetEnd = source.indexOf('\n  statusLabel()', sheetStart);
  const sheet = source.slice(sheetStart, sheetEnd);
  assert.match(sheet, /this\.page === 'logs'[\s\S]*accessibilityText\('日志操作'\)/);
  assert.match(sheet, /this\.showMenu = !this\.showMenu/);
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

test('AirPlay SETUP payloads include et=NONE and the virtual iAP2 command shape', () => {
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
  assert.ok(mediaSessionSource.indexOf("'video stream SETUP'") <
    mediaSessionSource.indexOf('await eventChannel.connect(this.receiverHost, eventPort, sharedSecret)'));
  assert.ok(mediaSessionSource.indexOf('await eventChannel.connect(this.receiverHost, eventPort, sharedSecret)') <
    mediaSessionSource.indexOf('eventChannel.sendCommand(AirPlayMediaSession.buildHidSetInputModePayload'));

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
    ['buildSessionSetupPayload', 'buildIapSendMessagePayload'], {
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
  const legacySession = BinaryPlist.decode(
    sessionSetup.buildSessionSetupPayload('AA:BB:CC:DD:EE:FF', 7000, true)
  );
  assert.equal(legacySession.get('et').integerValue, 1n);
  assert.equal(session.get('et'), undefined);
  const marker = new Uint8Array([0xff, 0x55, 0x02, 0x00, 0xee, 0x10]);
  const iapCommand = BinaryPlist.decode(sessionSetup.buildIapSendMessagePayload(marker));
  assert.equal(iapCommand.get('type').stringValue, 'iAPSendMessage');
  assert.deepEqual(iapCommand.get('params').get('data').dataValue, marker);

  const screenSetupAt = mediaSessionSource.indexOf("'video stream SETUP'");
  const mib3DetectAt = mediaSessionSource.indexOf('buildIapSendMessagePayload(MIB3_IAP2_DETECT_MARKER)');
  const eventChannelAt = mediaSessionSource.indexOf('await eventChannel.connect(this.receiverHost, eventPort, sharedSecret)');
  const recordAt = mediaSessionSource.indexOf("'RECORD'");
  assert.ok(screenSetupAt < mib3DetectAt && mib3DetectAt < eventChannelAt && eventChannelAt < recordAt);
});

test('MIB3 virtual iAP2 accepts event-channel bytes and reaches identification over the RTSP command route', async () => {
  const checksum = bytes => {
    let sum = 0;
    for (const byte of bytes) sum = (sum + byte) & 0xff;
    return (-sum) & 0xff;
  };
  const encodeLink = (control, sequence, acknowledgement, session, payload) => {
    const length = 9 + payload.length + (payload.length > 0 ? 1 : 0);
    const frame = new Uint8Array(length);
    frame.set([0xff, 0x5a, length >>> 8, length & 0xff, control, sequence,
      acknowledgement, session]);
    frame[8] = checksum(frame.slice(0, 8));
    frame.set(payload, 9);
    if (payload.length > 0) frame[length - 1] = checksum(payload);
    return frame;
  };
  const scanLink = bytes => {
    for (let offset = 0; offset + 9 <= bytes.length; offset++) {
      if (bytes[offset] !== 0xff || bytes[offset + 1] !== 0x5a) continue;
      const length = (bytes[offset + 2] << 8) | bytes[offset + 3];
      if (length < 9 || offset + length > bytes.length) return [offset, 0, 0];
      if (checksum(bytes.slice(offset, offset + 9)) !== 0 ||
        checksum(bytes.slice(offset + 9, offset + length)) !== 0) continue;
      return [offset + length, offset, length];
    }
    return [Math.max(0, bytes.length - 1), 0, 0];
  };
  const encodeControl = (messageId, body) => {
    const result = new Uint8Array(6 + body.length);
    result.set([0x40, 0x40, result.length >>> 8, result.length & 0xff,
      messageId >>> 8, messageId & 0xff]);
    result.set(body, 6);
    return result;
  };
  const codec = {
    encodeIap2LinkFrame: frame => encodeLink(frame.control, frame.sequence,
      frame.acknowledgement, frame.sessionId, frame.payload),
    encodeIap2Control: encodeControl,
    formatIap2RawFrameDiagnostic: () => '',
    formatIap2LinkPayloadDiagnostic: () => '',
    formatIap2MessageDiagnostic: () => '',
    concatBytes: (...parts) => {
      const result = new Uint8Array(parts.reduce((size, part) => size + part.length, 0));
      let offset = 0;
      for (const part of parts) { result.set(part, offset); offset += part.length; }
      return result;
    },
    Iap2LinkDecoder: class {
      buffer = new Uint8Array(0);
      push(chunk, onEvent) {
        this.buffer = codec.concatBytes(this.buffer, chunk);
        const frames = [];
        while (true) {
          const [consumed, start, length] = scanLink(this.buffer);
          if (!length) {
            this.buffer = this.buffer.slice(consumed);
            break;
          }
          const raw = this.buffer.slice(start, start + length);
          const frame = {
            control: raw[4], sequence: raw[5], acknowledgement: raw[6], sessionId: raw[7],
            payload: raw.slice(9, length - 1), raw
          };
          frames.push(frame);
          this.buffer = this.buffer.slice(consumed);
          onEvent?.(frame);
        }
        return frames;
      }
    },
    Iap2ControlDecoder: class {},
    decodeIap2Parameters: () => [],
    decodeIap2String: () => '',
    numberParameter: () => new Uint8Array(0),
    stringParameter: () => new Uint8Array(0),
    groupedParameter: () => new Uint8Array(0)
  };
  const sessionProtocol = loadEts('session/iap2/Iap2SessionProtocol.ets', {
    '../../protocol/Iap2Codec': codec,
    '@ohos.i18n': { System: { getSystemLanguage: () => 'en-US' } },
    '../ProtocolLogger': { formatProtocolEvent: () => '' }
  });
  const linkLayer = loadEts('session/iap2/Iap2LinkLayer.ets', {
    '../../protocol/Iap2Codec': codec,
    './Iap2SessionProtocol': sessionProtocol
  });
  const sessionFlow = loadEts('session/iap2/Iap2SenderSessionFlow.ets', {
    '@ohos.app.ability.common': {},
    '@ohos.data.preferences': {},
    '../../protocol/Iap2Codec': codec,
    '@ohos.security.cryptoFramework': {},
    '../../iap2/MfiVerifier': { MfiVerifier: class {} },
    '../ProtocolLogger': { formatProtocolEvent: () => '', formatRawBytesDiagnostic: () => '' },
    './Iap2SessionProtocol': sessionProtocol,
    './WirelessSessionParser': {},
    './Iap2LinkLayer': linkLayer
  });
  const { Iap2SenderSession } = loadEts('session/Iap2SenderSession.ets', {
    '@ohos.app.ability.common': {},
    '@ohos.data.preferences': {},
    '../protocol/Iap2Codec': codec,
    '@ohos.security.cryptoFramework': {},
    '@ohos.i18n': { System: { getSystemLanguage: () => 'en-US' } },
    '../iap2/MfiVerifier': { MfiVerifier: class {} },
    './ProtocolLogger': { formatProtocolEvent: () => '', formatRawBytesDiagnostic: () => '' },
    './iap2/Iap2SenderSessionFlow': sessionFlow,
    './iap2/Iap2SessionProtocol': sessionProtocol,
    './iap2/WirelessSessionParser': {}
  });
  const outbound = [];
  const sender = new Iap2SenderSession(
    async bytes => { outbound.push(bytes); }, () => {}, () => {}, () => {},
    'AA:BB:CC:DD:EE:FF', 'MIB3', 'test-uuid', false, [], undefined, undefined,
    false, undefined, () => {}, true
  );
  await sender.start(false);
  const synPayload = new Uint8Array([
    1, 4, 0x04, 0x00, 0x0f, 0xa0, 0x0f, 0xa0, 4, 4,
    10, 0, 2, 11, 2, 1, 12, 1, 2
  ]);
  const eventChannelData = encodeLink(0x80, 7, 0, 0, synPayload);
  await sender.receive(eventChannelData);
  assert.equal(outbound.length, 2);
  const syncAck = outbound.map(bytes => ({
    control: bytes[4], sequence: bytes[5], acknowledgement: bytes[6], sessionId: bytes[7],
    payload: bytes.slice(9, bytes.length - (bytes.length > 9 ? 1 : 0))
  }));
  assert.equal(syncAck[0].control, 0xc0);
  assert.equal(syncAck[0].acknowledgement, 7);
  assert.deepEqual(syncAck[0].payload, synPayload);
  assert.equal(syncAck[1].control, 0x40);
  assert.equal(syncAck[1].sessionId, 10);
  assert.deepEqual(Array.from(syncAck[1].payload.slice(4, 6)), [0x1d, 0x00]);
  sender.cancel();
  sender.cancel();

  const { parseIapSendMessagePayload } = loadEts(
    'airplay/media/AirPlayMediaHelpers.ets', {}, 'parseIapSendMessagePayload'
  );
  const incoming = {
    kind: 'dictionary',
    get(key) {
      if (key === 'type') return { kind: 'string', stringValue: 'iAPSendMessage' };
      if (key === 'params') return {
        kind: 'dictionary',
        get: name => name === 'data' ? { kind: 'data', dataValue: eventChannelData } : undefined
      };
      return undefined;
    }
  };
  assert.deepEqual(parseIapSendMessagePayload(incoming), eventChannelData);
});

test('MIB3 virtual iAP2 sends runtime initialization only after strict MFi and answers idle subscriptions', async () => {
  const MESSAGE = {
    MFI_AUTHENTICATION_SUCCEEDED: 0xaa05,
    AUX_STATUS_NOTIFICATION: 0xa100,
    DEVICE_LANGUAGE_UPDATE: 0x4e0a,
    DEVICE_INFORMATION_UPDATE: 0x4e09,
    DEVICE_TIME_UPDATE: 0x4e0b,
    DEVICE_UUID_UPDATE: 0x4e0c,
    MIB3_START_CALL_STATE_UPDATES: 0x4154,
    MIB3_CALL_STATE_UPDATE: 0x4155,
    MIB3_START_COMMUNICATIONS_UPDATES: 0x4157,
    MIB3_COMMUNICATIONS_UPDATE: 0x4158,
    MIB3_START_LIST_UPDATES: 0x4170,
    MIB3_LIST_UPDATE: 0x4171,
    MIB3_START_NOW_PLAYING_UPDATES: 0x5000,
    MIB3_NOW_PLAYING_UPDATE: 0x5001
  };
  const finish = loadMethods('session/Iap2SenderSession.ets', 'Iap2SenderSession',
    ['finishMfiAuthentication'], { MESSAGE });
  const makeTarget = (challengeVerified, sent) => {
    const target = new finish();
    target.started = true;
    target.sessionGeneration = 3;
    target.mfiOnlyVirtualLink = true;
    target.mfiVerifier = { canContinueAfterChallengeVerification: () => true };
    target.log = () => {};
    target.sendControl = async (id, body = new Uint8Array(0)) => { sent.push({ id, body }); };
    target.clearMfiChallenge = () => {};
    target.persistSuccessfulChallengeLength = async () => {};
    target.sendMib3InitializationBurst = async () => { target.initializationSent = true; };
    target.pendingMfiChallenge = new Uint8Array(32);
    return { target, challengeVerified };
  };

  const bypassSent = [];
  const bypass = makeTarget(false, bypassSent);
  await bypass.target.finishMfiAuthentication(bypass.challengeVerified);
  assert.deepEqual(bypassSent.map(item => item.id), [MESSAGE.MFI_AUTHENTICATION_SUCCEEDED]);
  assert.equal(bypass.target.initializationSent, undefined);

  const verifiedSent = [];
  const verified = makeTarget(true, verifiedSent);
  await verified.target.finishMfiAuthentication(verified.challengeVerified);
  assert.deepEqual(verifiedSent.map(item => item.id), [MESSAGE.MFI_AUTHENTICATION_SUCCEEDED]);
  assert.equal(verified.target.initializationSent, true);

  const concatBytes = (...parts) => {
    const result = new Uint8Array(parts.reduce((size, part) => size + part.length, 0));
    let offset = 0;
    for (const part of parts) { result.set(part, offset); offset += part.length; }
    return result;
  };
  const greetings = loadMethods('session/Iap2SenderSession.ets', 'Iap2SenderSession',
    ['sendMib3InitializationBurst'], {
      MESSAGE,
      concatBytes,
      numberParameter: (_id, value, width) => Uint8Array.of(value, width),
      stringParameter: (_id, value) => new TextEncoder().encode(value)
    });
  const target = new greetings();
  target.mib3WirelessSessionUuid = '12345678-1234-4234-9234-1234567890AB';
  target.parameter = (id, value) => Uint8Array.from([
    (value.length + 4) >>> 8, (value.length + 4) & 0xff, id >>> 8, id & 0xff, ...value
  ]);
  const sent = [];
  target.sendControl = async (id, body) => { sent.push({ id, body }); };
  await target.sendMib3InitializationBurst();
  assert.deepEqual(sent.map(item => item.id), [
    MESSAGE.DEVICE_UUID_UPDATE, MESSAGE.AUX_STATUS_NOTIFICATION,
    MESSAGE.DEVICE_LANGUAGE_UPDATE, MESSAGE.DEVICE_TIME_UPDATE, MESSAGE.DEVICE_INFORMATION_UPDATE
  ]);
  assert.equal(new TextDecoder().decode(sent[0].body), target.mib3WirelessSessionUuid);
  assert.deepEqual(Array.from(sent[1].body), [0, 4, 0, 6]);
  assert.equal(new TextDecoder().decode(sent[2].body), 'zh');
  assert.ok(sent[3].body.length > 0);
  assert.equal(new TextDecoder().decode(sent[4].body), 'iPhone');

  const subscriptions = loadMethods('session/Iap2SenderSession.ets', 'Iap2SenderSession',
    ['handleMib3PostAuthenticationMessage'], {
      MESSAGE,
      concatBytes: (...parts) => {
        const result = new Uint8Array(parts.reduce((size, part) => size + part.length, 0));
        let offset = 0;
        for (const part of parts) {
          result.set(part, offset);
          offset += part.length;
        }
        return result;
      },
      MIB3_COMMUNICATIONS_IDLE_BODY: new Uint8Array(94),
      MIB3_NOW_PLAYING_IDLE_BODY: new Uint8Array(79)
    });
  const subscriptionTarget = new subscriptions();
  const responses = [];
  subscriptionTarget.log = () => {};
  subscriptionTarget.parameter = (id, value) => Uint8Array.from([
    (value.length + 4) >>> 8, (value.length + 4) & 0xff, id >>> 8, id & 0xff, ...value
  ]);
  subscriptionTarget.sendControl = async (id, body = new Uint8Array(0)) => { responses.push({ id, body }); };
  for (const [request, response] of [
    [MESSAGE.MIB3_START_CALL_STATE_UPDATES, MESSAGE.MIB3_CALL_STATE_UPDATE],
    [MESSAGE.MIB3_START_COMMUNICATIONS_UPDATES, MESSAGE.MIB3_COMMUNICATIONS_UPDATE],
    [MESSAGE.MIB3_START_LIST_UPDATES, MESSAGE.MIB3_LIST_UPDATE],
    [MESSAGE.MIB3_START_NOW_PLAYING_UPDATES, MESSAGE.MIB3_NOW_PLAYING_UPDATE]
  ]) {
    await subscriptionTarget.handleMib3PostAuthenticationMessage(request);
  }
  assert.deepEqual(responses.map(item => item.id), [
    MESSAGE.MIB3_CALL_STATE_UPDATE, MESSAGE.MIB3_COMMUNICATIONS_UPDATE,
    MESSAGE.MIB3_LIST_UPDATE, MESSAGE.MIB3_NOW_PLAYING_UPDATE
  ]);
  assert.deepEqual(responses.map(item => item.body.length), [5, 94, 22, 79]);
  assert.deepEqual(Array.from(responses[0].body), [0, 5, 0, 2, 0]);
  assert.deepEqual(Array.from(responses[2].body.slice(0, 5)), [0, 5, 0, 0, 0]);

  const receive = loadMethods('session/Iap2SenderSession.ets', 'Iap2SenderSession',
    ['receiveControlMessage'], {
      MESSAGE,
      formatIap2MessageDiagnostic: () => ''
    });
  const gated = new receive();
  gated.mfiOnlyVirtualLink = true;
  gated.authenticated = true;
  gated.mfiVerified = false;
  gated.log = () => {};
  const handled = [];
  gated.handleMib3PostAuthenticationMessage = async id => { handled.push(id); };
  await gated.receiveControlMessage(MESSAGE.MIB3_START_CALL_STATE_UPDATES, new Uint8Array(0));
  assert.deepEqual(handled, []);
  gated.mfiVerified = true;
  await gated.receiveControlMessage(MESSAGE.MIB3_START_CALL_STATE_UPDATES, new Uint8Array(0));
  assert.deepEqual(handled, [MESSAGE.MIB3_START_CALL_STATE_UPDATES]);
});

test('AirPlay feature bit selects pairing only when advertised', () => {
  const { supportsAirPlayPairingAndEncryption } = loadEts('airplay/AirPlayPairingClient.ets', {
    '@ohos.app.ability.common': {},
    '../network/AirPlayMdnsDiscovery': {},
    '../protocol/Iap2Codec': {},
    '../crypto/AirPlayStreamCrypto': {},
    './AirPlayCrypto': {},
    './AirPlayIdentityStore': {},
    './AirPlayMediaSession': {},
    './AirPlayVideoStream': {},
    './AirPlayRtspClient': {},
    './Srp6aClient': {},
    './Tlv8': {},
    '../network/WifiNetworkLease': {},
    './pairing/PairingProtocol': {},
    '../session/ProtocolLogger': { formatProtocolEvent: () => '' }
  });
  assert.equal(supportsAirPlayPairingAndEncryption('0x00000000,0x00000040'), true);
  assert.equal(supportsAirPlayPairingAndEncryption('0x00000040,0x00000000'), false);
  assert.equal(supportsAirPlayPairingAndEncryption('0x00000000,0x00000000'), false);
  assert.equal(supportsAirPlayPairingAndEncryption('invalid'), undefined);
  assert.equal(supportsAirPlayPairingAndEncryption(undefined), undefined);
});

test('AirPlay SRP-6a modular exponentiation runs in TaskPool with byte-array inputs', async () => {
  const tasks = [];
  const taskpool = {
    Priority: { MEDIUM: 1 },
    Task: class {
      constructor(operation, ...args) { this.operation = operation; this.args = args; }
      setTransferList(list) { this.transfers = list; }
    },
    async execute(task, priority) {
      tasks.push({ task, priority });
      return task.operation(...task.args);
    }
  };
  const { Srp6aSession, SRP_GENERATOR, SRP3072_MODULUS, modPow, srpBigIntToBytes,
    srpBytesToBigInt } = loadEts('airplay/Srp6aClient.ets', {
    '@ohos.security.cryptoFramework': {
      createRandom: () => ({ async generateRandom(length) {
        return { data: new Uint8Array(length).fill(2) };
      } })
    },
    '@ohos.taskpool': taskpool,
    '../protocol/Iap2Codec': {
      concatBytes: (...parts) => {
        const output = new Uint8Array(parts.reduce((length, part) => length + part.length, 0));
        let offset = 0;
        for (const part of parts) {
          output.set(part, offset);
          offset += part.length;
        }
        return output;
      }
    },
    './AirPlayCrypto': {
      async sha512() { return new Uint8Array(64).fill(1); }
    }
  });
  const randomBytes = new Uint8Array(32).fill(2);
  const serverPublic = new Uint8Array(384);
  serverPublic[383] = 7;
  const session = await Srp6aSession.start(new Uint8Array([1]), serverPublic);
  const expectedPublic = srpBigIntToBytes(modPow(SRP_GENERATOR, srpBytesToBigInt(randomBytes), SRP3072_MODULUS));
  const expectedPaddedPublic = new Uint8Array(384);
  expectedPaddedPublic.set(expectedPublic, expectedPaddedPublic.length - expectedPublic.length);
  assert.deepEqual(session.publicKeyA, expectedPaddedPublic);
  assert.equal((await session.clientProof()).length, 64);
  assert.equal(tasks.length, 3);
  for (const entry of tasks) {
    assert.equal(entry.priority, 1);
    assert.deepEqual(entry.task.transfers, []);
    assert.ok(entry.task.args.every(argument => argument instanceof Uint8Array));
  }
});

test('AirPlay Pair-Setup verifies the receiver key when it was not advertised in advance', async () => {
  const receiverKey = Uint8Array.from({ length: 32 }, (_, index) => index);
  const types = {
    METHOD: 0,
    STATE: 1,
    SALT: 2,
    PUBLIC_KEY: 3,
    PROOF: 4,
    ENCRYPTED_DATA: 5,
    IDENTIFIER: 6,
    SIGNATURE: 7
  };
  const responses = [
    new Map([[types.SALT, Uint8Array.of(1)], [types.PUBLIC_KEY, Uint8Array.of(2)]]),
    new Map([[types.STATE, Uint8Array.of(4)], [types.PROOF, Uint8Array.of(5)]]),
    new Map([[types.STATE, Uint8Array.of(6)], [types.ENCRYPTED_DATA, Uint8Array.of(7)]]),
    new Map([
      [types.IDENTIFIER, new TextEncoder().encode('buick.receiver')],
      [types.PUBLIC_KEY, receiverKey],
      [types.SIGNATURE, Uint8Array.of(8)]
    ])
  ];
  let responseIndex = 0;
  let verifiedKey;
  const { PairSetupClient } = loadEts('airplay/pairing/PairingProtocol.ets', {
    '../../protocol/Iap2Codec': {
      concatBytes: (...parts) => Uint8Array.from(parts.flatMap(part => [...part])),
      decodeUtf8: bytes => new TextDecoder().decode(bytes),
      encodeUtf8: text => new TextEncoder().encode(text)
    },
    '../../crypto/AirPlayStreamCrypto': {
      chachaOpen: async () => Uint8Array.of(1),
      chachaSeal: async () => Uint8Array.of(1)
    },
    '../AirPlayCrypto': {
      hkdfSha512: async () => new Uint8Array(32),
      signEd25519: async () => new Uint8Array(64),
      verifyEd25519: async key => { verifiedKey = key; return true; },
      generateX25519KeyPair: async () => ({}),
      x25519SharedSecret: async () => new Uint8Array(32)
    },
    '../Srp6aClient': {
      Srp6aSession: {
        start: async () => ({
          publicKeyA: Uint8Array.of(3),
          clientProof: async () => Uint8Array.of(4),
          verifyServerProof: async () => true,
          getSessionKey: () => Uint8Array.of(5)
        })
      }
    },
    '../Tlv8': {
      decodeTlv8: () => responses[responseIndex++],
      encodeTlv8: () => Uint8Array.of(0),
      Tlv8Type: types
    }
  });
  const identity = {
    pairingId: 'controller',
    privateKeyDer: Uint8Array.of(1),
    publicKeyRaw: Uint8Array.of(2)
  };
  const client = { request: async () => ({ statusCode: 200, statusLine: 'RTSP/1.0 200 OK', body: new Uint8Array(0) }) };
  const setup = new PairSetupClient(client, identity, () => {});

  const receiver = await setup.run();
  assert.equal(receiver.receiverId, 'buick.receiver');
  assert.deepEqual(receiver.receiverPublicKey, receiverKey);
  assert.deepEqual(verifiedKey, receiverKey);

  responseIndex = 0;
  await assert.rejects(
    () => setup.run(new Uint8Array(32).fill(0xff)),
    /does not match the advertised AirPlay identity/
  );
});

test('AirPlay Pair-Verify binds to the Pair-Setup key and rejects a different receiver ID', async () => {
  const setupReceiverKey = Uint8Array.from({ length: 32 }, (_, index) => index + 1);
  let pairVerifyKey;
  const Target = loadMethods('airplay/AirPlayPairingClient.ets', 'AirPlayPairingClient', ['pair'], {
    decodeHex: () => new Uint8Array(0),
    PairSetupClient: class {
      constructor() {}
      async run(advertisedKey) {
        assert.equal(advertisedKey, undefined);
        return { receiverId: 'setup-receiver', receiverPublicKey: setupReceiverKey };
      }
    },
    PairVerifyClient: class {
      constructor() {}
      async run(receiverKey) {
        pairVerifyKey = receiverKey;
        return {
          receiverId: 'different-receiver',
          sharedSecret: Uint8Array.of(1),
          phoneReadKey: Uint8Array.of(2),
          phoneWriteKey: Uint8Array.of(3)
        };
      }
    }
  });
  const target = new Target();
  target.lifecycleGeneration = 1;
  target.identityStore = {
    loadOrCreate: async () => ({ pairingId: 'controller' }),
    loadVerifiedReceiver: async () => undefined,
    saveVerifiedReceiver: async () => {}
  };
  target.connect = async () => {};
  target.requireClient = () => ({ activateEncryption() {} });
  target.log = () => {};
  target.close = async () => {};

  await assert.rejects(
    () => target.pair({}, { host: '10.36.232.90', port: 7000, txt: {} }),
    /pair-setup and pair-verify receiver identities do not match/
  );
  assert.deepEqual(pairVerifyKey, setupReceiverKey);
});

test('AirPlay Pair-Setup 403 without an advertised key preserves the status for backoff', async () => {
  class StubAirPlayRtspStatusError extends Error {
    constructor() {
      super('HTTP 403 Forbidden');
      this.statusCode = 403;
    }
  }
  const forbidden = new StubAirPlayRtspStatusError();
  const Target = loadMethods('airplay/AirPlayPairingClient.ets', 'AirPlayPairingClient', ['pair'], {
    decodeHex: () => new Uint8Array(0),
    Error,
    AirPlayRtspStatusError: StubAirPlayRtspStatusError,
    PairSetupClient: class {
      constructor() {}
      async run() { throw forbidden; }
    }
  });
  const target = new Target();
  target.lifecycleGeneration = 1;
  target.identityStore = {
    loadOrCreate: async () => ({ pairingId: 'controller' }),
    loadVerifiedReceiver: async () => undefined,
    saveVerifiedReceiver: async () => {}
  };
  target.connect = async () => {};
  target.requireClient = () => ({});
  target.log = () => {};
  target.close = async () => {};

  await assert.rejects(
    () => target.pair({}, { host: '10.36.232.90', port: 7000, txt: {} }),
    error => error === forbidden && error.statusCode === 403
  );
});

test('AirPlay Pair-Setup 403 fast path uses only a previously verified device identity', async () => {
  class StubAirPlayRtspStatusError extends Error {
    constructor() {
      super('HTTP 403 Forbidden');
      this.statusCode = 403;
    }
  }
  const forbidden = new StubAirPlayRtspStatusError();
  const trustedKey = new Uint8Array(32).fill(7);
  const connects = [];
  const verifiedKeys = [];
  const savedIdentities = [];
  const Target = loadMethods('airplay/AirPlayPairingClient.ets', 'AirPlayPairingClient', ['pair'], {
    decodeHex: () => new Uint8Array(0),
    Error,
    AirPlayRtspStatusError: StubAirPlayRtspStatusError,
    PairSetupClient: class {
      constructor() {}
      async run(expectedKey) {
        assert.deepEqual(expectedKey, trustedKey);
        throw forbidden;
      }
    },
    PairVerifyClient: class {
      constructor() {}
      async run(receiverKey) {
        verifiedKeys.push(receiverKey);
        return {
          receiverId: 'trusted-receiver',
          sharedSecret: Uint8Array.of(1),
          phoneReadKey: Uint8Array.of(2),
          phoneWriteKey: Uint8Array.of(3)
        };
      }
    }
  });
  const target = new Target();
  target.lifecycleGeneration = 1;
  target.identityStore = {
    loadOrCreate: async () => ({ pairingId: 'controller' }),
    loadVerifiedReceiver: async (_context, deviceId) => {
      assert.equal(deviceId, 'AA:BB:CC:DD:EE:FF');
      return { receiverId: 'trusted-receiver', publicKeyRaw: trustedKey };
    },
    saveVerifiedReceiver: async (...identity) => savedIdentities.push(identity)
  };
  target.connect = async () => { connects.push(true); };
  target.closeResources = async () => {};
  target.requireClient = () => ({ activateEncryption() {} });
  target.log = () => {};
  target.close = async () => {};

  const result = await target.pair({}, {
    host: '10.36.232.90', port: 7000, txt: { deviceid: 'AA:BB:CC:DD:EE:FF' }
  });
  assert.equal(result.receiverId, 'trusted-receiver');
  assert.equal(connects.length, 2);
  assert.deepEqual(verifiedKeys, [trustedKey]);
  assert.equal(savedIdentities.length, 1);
  assert.equal(savedIdentities[0][1], 'AA:BB:CC:DD:EE:FF');
});

test('AirPlay verified receiver identities are persisted per normalized deviceid', async () => {
  const values = new Map();
  const store = {
    async get(key, fallback) { return values.has(key) ? values.get(key) : fallback; },
    async put(key, value) { values.set(key, value); },
    async flush() {}
  };
  const { AirPlayIdentityStore } = loadEts('airplay/AirPlayIdentityStore.ets', {
    '@ohos.app.ability.common': {},
    '@ohos.security.cryptoFramework': {},
    '@ohos.data.preferences': { getPreferences: async () => store },
    './AirPlayCrypto': {}
  });
  const identities = new AirPlayIdentityStore();
  const publicKeyRaw = new Uint8Array(32).fill(11);
  await identities.saveVerifiedReceiver({}, 'AA:BB:CC:DD:EE:FF', 'receiver-1', publicKeyRaw);
  assert.deepEqual(
    await identities.loadVerifiedReceiver({}, 'aa-bb-cc-dd-ee-ff'),
    { receiverId: 'receiver-1', publicKeyRaw }
  );
  assert.equal(await identities.loadVerifiedReceiver({}, '11:22:33:44:55:66'), undefined);
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
    '../session/ProtocolLogger': { formatProtocolEvent, formatRawBytesDiagnostic }
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
    const Target = loadMethods('session/SessionControllerConnectionFlow.ets', 'SessionControllerConnectionFlow', [
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

test('audio and video packet diagnostics cover every send without logging media payloads', async () => {
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
    .map(line => Number(line.match(/packet=(\d+)/)?.[1])), [1, 2, 3, 4]);
  assert.ok(audioLogs.every(line => !line.includes('aa bb')));
  assert.ok(audioLogs[1].includes('载荷未写入日志'));

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
  const wirelessParser = loadEts('session/iap2/WirelessSessionParser.ets', {
    '../../protocol/Iap2Codec': codec
  });
  const credentials = wirelessParser.parseWirelessSessionCredentials(encodeParameter(1, concatBytes(
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
  const endpoint = wirelessParser.parseWirelessSessionEndpoint(concatBytes(
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
    'libiap2codec.so': {},
    './RawByteFormatter': loadEts('protocol/RawByteFormatter.ets')
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
  let command;
  const Target = loadMethods('airplay/AirPlayMediaSession.ets', 'AirPlayMediaSession',
    ['handleEventRequest', 'setNightModeHandler'], {
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
  const { ProjectionTouchRouter } = loadEts('pages/ProjectionTouchRouter.ets');
  target.touchRouter = new ProjectionTouchRouter();
  target.touchRouter.touchBounds = new Map();
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
  const sourceFiles = [{ path: relativePath, className }];
  if (className === 'Iap2SenderSession') {
    sourceFiles.push({
      path: 'session/iap2/Iap2SenderSessionFlow.ets',
      className: 'Iap2SenderSessionFlow'
    });
  }
  if (className === 'SessionController') {
    sourceFiles.push({
      path: 'session/SessionControllerConnectionFlow.ets',
      className: 'SessionControllerConnectionFlow'
    });
  }
  if (className === 'AirPlayMediaSession') {
    sourceFiles.push({
      path: 'airplay/media/AirPlayMediaSessionTransport.ets',
      className: 'AirPlayMediaSessionTransport'
    });
  }
  const parsedSources = sourceFiles.map(sourceFile => {
    const source = fs.readFileSync(path.join(sourceRoot, sourceFile.path), 'utf8');
    return {
      className: sourceFile.className,
      parsed: ts.createSourceFile(sourceFile.path,
        source.replace(`struct ${sourceFile.className} {`, `class ${sourceFile.className} {`),
        ts.ScriptTarget.Latest, true)
    };
  });
  const methods = names.map(name => {
    for (const sourceFile of parsedSources) {
      const { parsed } = sourceFile;
      const declaration = parsed.statements.find(statement =>
        ts.isClassDeclaration(statement) && statement.name?.text === sourceFile.className);
      if (!declaration) {
        continue;
      }
      const member = declaration.members.find(candidate => candidate.name?.text === name);
      if (member) {
        return { member, parsed };
      }
    }
    return undefined;
  });
  assert.ok(methods.every(Boolean), `Missing methods: ${names.filter((_, index) => !methods[index]).join(', ')}`);
  const constructor = className === 'ProjectionDashboard'
    ? `constructor() {
        this.touchRouter = new ProjectionTouchRouter();
        Object.defineProperty(this, 'touchAreas', {
          get: () => this.touchRouter.touchAreas,
          set: value => { this.touchRouter.touchAreas = value; }
        });
        Object.defineProperty(this, 'touchBounds', {
          get: () => this.touchRouter.touchBounds,
          set: value => { this.touchRouter.touchBounds = value; }
        });
      }`
    : '';
  const javascript = ts.transpileModule(
    `class Target { ${constructor}\n${methods.map(method => method.member.getText(method.parsed)).join('\n')} }`, {
    compilerOptions: { target: ts.ScriptTarget.ES2020 }
  }).outputText;
  const executionGlobals = { ...globals };
  if (className === 'ProjectionDashboard') {
    executionGlobals.ProjectionTouchRouter = loadEts('pages/ProjectionTouchRouter.ets').ProjectionTouchRouter;
  }
  return vm.runInNewContext(`${javascript}\nTarget`, executionGlobals);
}

function loadProjectionSettingsController(overrides = {}) {
  const settings = loadEts('video/ProjectionSettings.ets');
  const { ProjectionDashboardSettingsController } = loadEts(
    'pages/ProjectionDashboardSettingsController.ets',
    { '../video/ProjectionSettings': { ...settings, ...overrides } }
  );
  return new ProjectionDashboardSettingsController();
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

test('active media metadata is logged once per track or playback-state change', () => {
  const { ProjectionMediaCoordinator } = loadEts('pages/ProjectionMediaCoordinator.ets', {
    '@ohos.abilityAccessCtrl': {},
    '@ohos.app.ability.common': {},
    '../session/MediaSessionBridge': {
      EMPTY_PROJECTION_MEDIA: { title: '', artist: '', lyric: '', positionMs: 0, durationMs: 0, isPlaying: false,
        commands: [], queue: [], message: '' }
    },
    './ProjectionAppCatalog': { includeMediaSessionApp: apps => apps }
  });
  const logs = [];
  const controller = new ProjectionMediaCoordinator({
    getContext: () => ({}),
    getSnapshot: () => ({}),
    onSnapshot: () => {},
    getApps: () => [],
    onAppsChanged: () => {},
    onActionMessage: () => {},
    onLog: message => logs.push(message)
  });
  const snapshot = {
    bundleName: 'com.huawei.hmsapp.music',
    abilityName: 'MainAbility',
    title: 'Track One',
    artist: 'Artist',
    isPlaying: true
  };
  controller.logMediaSnapshotIfChanged(snapshot);
  controller.logMediaSnapshotIfChanged(snapshot);
  controller.logMediaSnapshotIfChanged({ ...snapshot, title: 'Track Two' });
  assert.equal(logs.length, 2);
  assert.match(logs[0], /Track One/);
  assert.match(logs[1], /Track Two/);
});

test('play and pause state stays optimistic until AVSession confirms the command', async () => {
  const { ProjectionMediaCoordinator } = loadEts('pages/ProjectionMediaCoordinator.ets', {
    '@ohos.abilityAccessCtrl': {},
    '@ohos.app.ability.common': {},
    '../session/MediaSessionBridge': {
      EMPTY_PROJECTION_MEDIA: { title: '', artist: '', lyric: '', positionMs: 0, durationMs: 0, isPlaying: false,
        commands: [], queue: [], message: '' }
    },
    './ProjectionAppCatalog': { includeMediaSessionApp: apps => apps }
  });
  const commands = [];
  let actualIsPlaying = false;
  let state = {
    title: 'Track', artist: 'Artist', lyric: '', positionMs: 1000, durationMs: 5000,
    isPlaying: false, commands: ['play', 'pause'], queue: [], message: ''
  };
  const target = new ProjectionMediaCoordinator({
    getSnapshot: () => state,
    onSnapshot: snapshot => { state = snapshot; },
    getApps: () => [],
    onAppsChanged: () => {},
    onActionMessage: () => {},
    onLog: () => {},
    getContext: () => ({})
  });
  target.bridge = {
    async send(command) { commands.push(command); },
    async refresh() {
      return {
        title: 'Track', artist: 'Artist', lyric: '', positionMs: 1000, durationMs: 5000,
        bundleName: 'music.app', isPlaying: actualIsPlaying, commands: ['play', 'pause'],
        queue: [], message: ''
      };
    }
  };

  await target.send('play');
  assert.equal(state.isPlaying, true);
  assert.equal(target.optimisticPlaybackState.isPlaying, true);
  actualIsPlaying = true;
  await target.refresh(target.bridge);
  assert.equal(state.isPlaying, true);
  assert.equal(target.optimisticPlaybackState, undefined);

  await target.send('pause');
  assert.equal(state.isPlaying, false);
  actualIsPlaying = true;
  await target.refresh(target.bridge);
  assert.equal(state.isPlaying, false,
    'an older playing snapshot must not immediately undo the pause state');
  assert.deepEqual(commands, ['play', 'pause']);
});

test('leaving projection pauses the active media session without terminating its app', async () => {
  const commands = [];
  let destroyed = false;
  const avSession = {
    PlaybackState: { PLAYBACK_STATE_PLAY: 2 },
    getAllSessionDescriptors: async () => [{
      isTopSession: true,
      isActive: true,
      type: 'audio',
      sessionId: 'music-session',
      elementName: { bundleName: 'com.huawei.hmsapp.music', abilityName: 'MainAbility' }
    }],
    createController: async () => ({
      getAVPlaybackState: async () => ({ state: 2 }),
      getValidCommands: async () => ['pause'],
      sendControlCommand: async command => { commands.push(command.command); },
      destroy: async () => { destroyed = true; }
    })
  };
  const Target = loadMethods('pages/Index.ets', 'Index', ['pauseActiveMediaOnProjectionStop'], { avSession });
  const target = new Target();
  const logs = [];
  target.logProtocol = (_stage, message) => logs.push(message);
  await target.pauseActiveMediaOnProjectionStop();
  assert.deepEqual(commands, ['pause']);
  assert.equal(destroyed, true);
  assert.ok(logs.some(message => message.includes('离车时已暂停音乐')));
});

test('media controls wait for the in-flight session refresh instead of using a stale snapshot', async () => {
  let descriptorCalls = 0;
  let resolveDescriptors;
  const avSession = {
    getAllSessionDescriptors() {
      descriptorCalls++;
      return new Promise(resolve => { resolveDescriptors = resolve; });
    },
    onSessionCreate() {},
    onSessionDestroy() {},
    onTopSessionChange() {}
  };
  const { MediaSessionBridge } = loadEts('session/MediaSessionBridge.ets', {
    '@ohos.multimedia.avsession': avSession
  });
  const bridge = new MediaSessionBridge();
  const first = bridge.refresh();
  let secondSettled = false;
  const second = bridge.refresh().then(snapshot => {
    secondSettled = true;
    return snapshot;
  });
  assert.equal(descriptorCalls, 1);
  await Promise.resolve();
  assert.equal(secondSettled, false);
  resolveDescriptors([]);
  const snapshots = await Promise.all([first, second]);
  assert.equal(snapshots[0].message, '未检测到活动音乐会话');
  assert.equal(snapshots[1].message, '未检测到活动音乐会话');
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
    (event, ...fields) => `${event} ${fields.join(' ')}`, () => 'empty body');
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

test('AirPlay mDNS discovery can release the ctrl invite wait early', () => {
  const { isAirPlayStartReady } = loadEts('session/airplay/AirPlayEndpointFactory.ets', {}, 'isAirPlayStartReady');
  assert.equal(isAirPlayStartReady(true, true, false, true), true);
  assert.equal(isAirPlayStartReady(true, false, true), true);
  assert.equal(isAirPlayStartReady(true, false, false, true), true);
  assert.equal(isAirPlayStartReady(true, true, false, false, true), true);
  assert.equal(isAirPlayStartReady(true, false, false, false, true), false);
  assert.equal(isAirPlayStartReady(false, true, true, true), false);
});

test('AirPlay mDNS callback rejects endpoints outside the selected WLAN prefix', async () => {
  const Target = loadMethods('session/SessionControllerConnectionFlow.ets', 'SessionControllerConnectionFlow',
    ['handleDiscoveredAirPlayService']);
  const target = new Target();
  const actions = [];
  target.wifiNetworkLease = { isAirPlayAddressOnSelectedNetwork: address => address.startsWith('10.36.232.') };
  target.events = {
    onAirPlayService: service => actions.push(['service', service.host]),
    onLog: message => actions.push(['log', message])
  };
  target.refreshDiscoveredAirPlay = () => actions.push(['refresh']);
  target.hasSelfContainedAirPlayEndpoint = () => false;
  target.clearAirPlayWaitTimers = () => actions.push(['clear-timers']);
  target.connectAirPlay = async () => { actions.push(['connect']); };
  target.reportError = error => { throw error; };
  target.mdnsAirPlayService = undefined;
  target.inviteReceived = false;
  target.airPlayInviteWaitElapsed = false;

  target.handleDiscoveredAirPlayService({ name: 'other', host: '192.168.1.5', port: 7000, txt: {} });
  assert.equal(target.mdnsAirPlayService, undefined);
  assert.deepEqual(actions, [['log', '忽略不属于车机 WLAN 网段的 AirPlay mDNS 地址：192.168.1.5']]);

  actions.length = 0;
  target.handleDiscoveredAirPlayService({ name: 'vehicle', host: '10.36.232.90', port: 7000, txt: {} });
  await Promise.resolve();
  assert.equal(target.mdnsAirPlayService.host, '10.36.232.90');
  assert.deepEqual(actions.map(action => action[0]), ['refresh', 'service', 'log', 'connect']);
});

test('AirPlay 403 retries back off longer than ordinary connection failures', () => {
  class StubAirPlayRtspStatusError extends Error {
    constructor(statusCode) {
      super(`HTTP ${statusCode}`);
      this.statusCode = statusCode;
    }
  }
  const delays = [];
  const Target = loadMethods('session/SessionControllerConnectionFlow.ets', 'SessionControllerConnectionFlow',
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

test('CarPlay ctrl reannouncement preserves its port and uses a dedicated source version', async () => {
  const actions = [];
  const Target = loadMethods('network/CarPlayCtrlAdvertiser.ets', 'CarPlayCtrlAdvertiser',
    ['reannounce', 'createServiceInfo'], {
      CARPLAY_CTRL_SOURCE_VERSION: '950.7.1',
      encodeUtf8: text => new TextEncoder().encode(text),
      formatProtocolEvent: event => event,
      mdns: {
        async removeLocalService(_context, service) { actions.push({ type: 'remove', service }); },
        async addLocalService(_context, service) {
          actions.push({ type: 'add', service });
          return service;
        }
      },
      describeSocketError: error => error instanceof Error ? error.message : String(error)
    });
  const advertiser = new Target();
  advertiser.context = {};
  advertiser.deviceAddress = '40:06:34:E5:ED:EA';
  advertiser.server = {};
  advertiser.servicePort = 42051;
  advertiser.service = { port: 42051 };
  advertiser.toNumberArray = bytes => Array.from(bytes);
  advertiser.onLog = message => actions.push({ type: 'log', message });

  await advertiser.reannounce();

  assert.equal(actions[0].type, 'remove');
  assert.equal(actions[1].type, 'add');
  assert.equal(actions[1].service.port, 42051);
  const attributes = Object.fromEntries(actions[1].service.serviceAttribute.map(attribute => [
    attribute.key,
    new TextDecoder().decode(new Uint8Array(attribute.value))
  ]));
  assert.equal(attributes.id, '40:06:34:E5:ED:EA');
  assert.equal(attributes.srcvers, '950.7.1');
  assert.equal(advertiser.server !== undefined, true);
});

test('wireless startup keeps address candidates without treating UUID identities as public keys', () => {
  const source = fs.readFileSync(path.join(sourceRoot, 'session/iap2/WirelessSessionParser.ets'), 'utf8');
  const parsed = ts.createSourceFile('WirelessSessionParser.ts', source, ts.ScriptTarget.Latest, true);
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

test('iAP2 start request does not masquerade as ctrl invitation', async () => {
  const Target = loadMethods('session/SessionController.ets', 'SessionController',
    ['handleIap2AirPlayEndpoint', 'startControlAdvertisement'], {
      CarPlayCtrlAdvertiser: class {
        constructor(_context, _address, onInvite) {
          this.onInvite = onInvite;
        }
        async start() {
          this.onInvite();
        }
      }
    });
  const target = new Target();
  let connections = 0;
  target.running = true;
  target.inviteReceived = false;
  target.vehicleWifiConnected = true;
  target.hasValidDeviceAddress = () => true;
  target.clearPendingStartSessionTimer = () => {};
  target.clearAirPlayInviteWaitTimer = () => {};
  target.startAirPlayPrerequisiteWait = () => {};
  target.startAirPlayEndpointResolutionWait = () => {};
  target.events = { onLog() {}, onStatus() {}, onAirPlayService() {} };
  target.refreshDiscoveredAirPlay = () => {};
  target.discoveredAirPlay = { host: '192.168.49.1', port: 7000 };
  target.connectAirPlay = async () => { connections++; };
  target.handleIap2AirPlayEndpoint(undefined);
  assert.equal(target.airPlayStartSessionReceived, true);
  assert.equal(target.inviteReceived, false);
  assert.equal(connections, 1);
  await target.startControlAdvertisement();
  assert.equal(target.inviteReceived, true);
  assert.equal(connections, 3);
  target.inviteReceived = false;
  target.running = false;
  target.handleIap2AirPlayEndpoint(undefined);
  assert.equal(target.inviteReceived, false);
});

test('new-protocol startup announces availability without probing legacy Wi-Fi', async () => {
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

test('iAP2 hands 0x5703 credentials to Wi-Fi while announcing CarPlay immediately', async () => {
  const Target = loadMethods('session/Iap2SenderSession.ets', 'Iap2SenderSession',
    ['receiveControlMessage'], {
      MESSAGE: { WIFI_CONFIGURATION: 0x5703 },
      formatIap2MessageDiagnostic: () => '',
      encodeUtf8: value => new TextEncoder().encode(value)
    });
  const target = new Target();
  const actions = [];
  target.started = true;
  target.authenticated = true;
  target.log = () => {};
  target.wifiConfigurationTimer = undefined;
  target.wifiConfigurationRescueGeneration = 0;
  target.clearOptionalHandshakeWaits = () => {};
  target.parseWifi = () => ({ ssid: 'CAR_HOTSPOT', password: 'hidden', securityType: 2, channel: 0 });
  target.onWifi = () => { actions.push('join-wifi'); };
  target.sendDeviceAnnouncement = async () => { actions.push('announce-0x4300'); };
  target.startStartSessionWaitTimer = () => { actions.push('wait-0x4301'); };

  await target.receiveControlMessage(0x5703, new Uint8Array([1]));
  assert.deepEqual(actions, ['join-wifi', 'announce-0x4300', 'wait-0x4301']);
});

test('post-MFi startup sends greetings and opens declared EA sessions before Wi-Fi', async () => {
  const timers = [];
  const Target = loadMethods('session/Iap2SenderSession.ets', 'Iap2SenderSession',
    ['startPostAuthenticationSequence'], {
      MESSAGE: { EA_OPEN_SESSION: 0xea00, EA_SESSION_STATUS: 0xea03 },
      concatBytes: (...parts) => Uint8Array.from(parts.flatMap(part => Array.from(part))),
      numberParameter: (id, value, width) => new Uint8Array([id, value, width]),
      stringParameter: (id, value) => new TextEncoder().encode(`${id}:${value}`),
      setTimeout: (callback, delayMs) => {
        timers.push({ callback, delayMs });
        return timers.length;
      }
    });
  const target = new Target();
  const actions = [];
  target.started = true;
  target.authenticated = true;
  target.sessionGeneration = 4;
  target.accessoryEaProtocols = [{ protocolId: 7, name: 'com.example.ea' }];
  target.accessorySendMessages = [0xea03];
  target.log = () => {};
  target.sendDeviceStateGreetings = async () => { actions.push('greetings'); };
  target.sendControl = async messageId => { actions.push(messageId); };

  await target.startPostAuthenticationSequence(4);
  assert.deepEqual(actions, ['greetings', 0xea00]);
  assert.equal(timers[0].delayMs, 500);
});

test('iAP2 StartHID is acknowledged before Wi-Fi configuration begins', async () => {
  const Target = loadMethods('session/Iap2SenderSession.ets', 'Iap2SenderSession',
    ['receiveControlMessage'], {
      MESSAGE: { START_HID: 0x6800, DEVICE_HID_REPORT: 0x6801 },
      formatIap2MessageDiagnostic: () => '',
      clearTimeout: () => {},
      concatBytes: (...parts) => Uint8Array.from(parts.flatMap(part => Array.from(part))),
      numberParameter: (id, value, width) => new Uint8Array([id, value, width])
    });
  const target = new Target();
  const actions = [];
  target.log = () => {};
  target.hidStartWaitTimer = 1;
  target.parameter = (id, value) => new Uint8Array([id, ...value]);
  target.sendControl = async messageId => { actions.push(messageId); };
  target.requestWifiConfiguration = async () => { actions.push('wifi'); };

  await target.receiveControlMessage(0x6800, new Uint8Array(0));
  assert.deepEqual(actions, [0x6801, 'wifi']);
});

test('iAP2 receiver profile matches CardDeck Wi-Fi and MIB3 capability rules', () => {
  const { shouldProbeLegacyWifi, isClassicMib3Profile } = loadEts('session/iap2/Iap2SessionProtocol.ets', {
    '../../protocol/Iap2Codec': {},
    '@ohos.i18n': {},
    '../ProtocolLogger': {}
  });
  assert.equal(shouldProbeLegacyWifi([0x4301], [0x4300]), true);
  assert.equal(shouldProbeLegacyWifi([], []), true);
  assert.equal(shouldProbeLegacyWifi(Array(5).fill(0x4301), Array(5).fill(0x4300)), false);
  assert.equal(shouldProbeLegacyWifi(Array(10).fill(0x4301), undefined), false);
  assert.equal(shouldProbeLegacyWifi(Array(10).fill(0x4301), [0x5702, ...Array(9).fill(0x4300)]), true);
  assert.equal(isClassicMib3Profile('Delphi Audi', [0x4301], [0x4300, 0x4e00]), true);
  assert.equal(isClassicMib3Profile('Delphi Audi', Array(5).fill(0x4301), Array(5).fill(0x4300)), false);
  assert.equal(isClassicMib3Profile('Delphi Audi', [0x4301], undefined), false);
  assert.equal(isClassicMib3Profile('Delphi Buick', [0x4301], [0x4300]), false);
});

test('Bluetooth adapter mode advertises Wireless iAP and holds post-handoff redials', async () => {
  const acceptCallbacks = [];
  const closedClients = [];
  let serviceName = '';
  const bluetoothSocket = {
    SppType: { SPP_RFCOMM: 1 },
    sppListen(name, _options, callback) {
      serviceName = name;
      callback(undefined, 17);
    },
    sppAccept(_serverId, callback) { acceptCallbacks.push(callback); },
    on() {},
    off() {},
    sppCloseClientSocket(clientId) { closedClients.push(clientId); },
    sppCloseServerSocket() {},
    async sppWriteAsync() {}
  };
  const { BluetoothIap2Server, isCarPlayAdapterName } = loadEts('transport/BluetoothIap2Server.ets', {
    '@ohos.bluetooth.socket': bluetoothSocket,
    '../protocol/Iap2Codec': { toArrayBuffer: () => new ArrayBuffer(0) }
  });
  assert.equal(isCarPlayAdapterName('Carlinkit CPC200'), true);
  assert.equal(isCarPlayAdapterName('Audi MMI'), false);

  const server = new BluetoothIap2Server();
  let connections = 0;
  await server.start(() => { connections++; }, () => {}, () => {}, true);
  assert.equal(serviceName, 'Wireless iAP');
  acceptCallbacks.shift()(undefined, 1);
  assert.equal(connections, 1);
  server.setAdapterHandoffCompleted(true);
  acceptCallbacks.shift()(undefined, 2);
  assert.equal(connections, 1);
  assert.deepEqual(closedClients, []);
  server.setAdapterHandoffCompleted(false);
  assert.deepEqual(closedClients, [2]);
  acceptCallbacks.shift()(undefined, 3);
  assert.equal(connections, 2);
  assert.ok(closedClients.includes(1));
  server.stop();
  assert.ok(closedClients.includes(3));
});

test('Bluetooth accept retries back off and deduplicate unchanged adapter errors', () => {
  const callbacks = [];
  const timers = [];
  const failures = [];
  let timerId = 0;
  const Target = loadMethods('transport/BluetoothIap2Server.ets', 'BluetoothIap2Server',
    ['acceptNext', 'scheduleAcceptRetry', 'reportAcceptFailure'], {
      bluetoothSocket: {
        sppAccept(_serverId, callback) { callbacks.push(callback); }
      },
      setTimeout: (callback, delayMs) => {
        timers.push({ callback, delayMs });
        return ++timerId;
      }
    });
  const server = new Target();
  server.serverId = 17;
  server.onFailure = message => failures.push(message);
  server.acceptRetryDelayMs = 500;
  server.acceptRetryTimer = -1;
  server.lastAcceptFailure = '';

  server.acceptNext();
  callbacks.shift()({ code: 2900099, message: 'Bluetooth disabled' });
  assert.equal(failures.length, 1);
  const firstRetry = timers.shift();
  assert.equal(firstRetry.delayMs, 500);
  firstRetry.callback();
  callbacks.shift()({ code: 2900099, message: 'Bluetooth disabled' });
  assert.equal(failures.length, 1);
  const secondRetry = timers.shift();
  assert.equal(secondRetry.delayMs, 1000);
  secondRetry.callback();
  callbacks.shift()({ code: 2900099, message: 'Bluetooth disabled' });
  assert.equal(failures.length, 1);
  assert.equal(timers.shift().delayMs, 2000);
});

test('iAP2 retries 0x5702 after device greetings before falling back to 0x4300', async () => {
  const timers = [];
  let timerId = 0;
  const Target = loadMethods('session/Iap2SenderSession.ets', 'Iap2SenderSession',
    ['startWifiConfigurationTimer'], {
      MESSAGE: { WIFI_REQUEST: 0x5702 },
      setTimeout: (callback, delayMs) => {
        timers.push({ callback, delayMs });
        return ++timerId;
      },
      clearTimeout: () => {}
    });
  const target = new Target();
  const actions = [];
  target.started = true;
  target.authenticated = true;
  target.deviceAnnouncementSent = false;
  target.wifiConfigurationRescueGeneration = 0;
  target.wifiConfigurationDeadline = Date.now() + 60000;
  target.log = () => {};
  target.errorDetails = error => error.message;
  target.sendDeviceStateGreetings = async force => { actions.push(`greetings:${force}`); };
  target.sendControl = async messageId => { actions.push(messageId); };
  target.sendDeviceAnnouncement = async () => { actions.push('announce'); };
  target.startWifiConfigurationTimer('0x5703', true);
  assert.equal(timers[0].delayMs, 1500);

  const runNextTimer = async () => {
    timers.shift().callback();
    for (let turn = 0; turn < 5; turn++) await Promise.resolve();
  };
  await runNextTimer();
  assert.deepEqual(actions, ['greetings:true']);
  assert.equal(timers[0].delayMs, 1300);
  await runNextTimer();
  assert.deepEqual(actions, ['greetings:true', 0x5702]);
  assert.ok(timers[0].delayMs > 50000 && timers[0].delayMs <= 60000);
  await runNextTimer();
  assert.deepEqual(actions, ['greetings:true', 0x5702, 'announce']);
});

test('Buick B233 identity selects strict MFi and encodes two availability groups', async () => {
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
    const result = [];
    for (let offset = 0; offset < bytes.length;) {
      const length = (bytes[offset] << 8) | bytes[offset + 1];
      assert.ok(length >= 4 && offset + length <= bytes.length);
      result.push({ id: (bytes[offset + 2] << 8) | bytes[offset + 3], value: bytes.slice(offset + 4, offset + length) });
      offset += length;
    }
    return result;
  };
  const encodeUtf8 = text => new TextEncoder().encode(text);
  const decodeString = bytes => new TextDecoder().decode(bytes).replace(/\0.*$/s, '');
  const codec = {
    concatBytes,
    decodeIap2Parameters: decodeParameters,
    decodeIap2String: decodeString,
    encodeUtf8,
    encodeIap2Control: () => new Uint8Array(0),
    encodeIap2LinkFrame: () => new Uint8Array(0),
    formatIap2LinkPayloadDiagnostic: () => '',
    formatIap2MessageDiagnostic: () => '',
    formatIap2RawFrameDiagnostic: () => '',
    groupedParameter: (id, children) => encodeParameter(id, concatBytes(...children)),
    Iap2ControlDecoder: class {},
    Iap2LinkDecoder: class {},
    numberParameter: (id, number, width) => {
      const value = new Uint8Array(width);
      for (let index = width - 1; index >= 0; index--) {
        value[index] = number & 0xff;
        number = Math.floor(number / 256);
      }
      return encodeParameter(id, value);
    },
    stringParameter: (id, text) => encodeParameter(id, concatBytes(encodeUtf8(text), new Uint8Array([0])))
  };
  const session = loadEts('session/iap2/Iap2SessionProtocol.ets', {
    '../../protocol/Iap2Codec': codec,
    '@ohos.i18n': { System: { getSystemLanguage: () => 'zh-CN' } },
    '../ProtocolLogger': { formatProtocolEvent: () => '' }
  });
  const identity = 'Buick B233 SAIC General Motors';
  assert.equal(session.isBuickB233Identity(identity), true);
  assert.equal(session.isBuickB233Identity('BUICK_7841 E2LB SAIC General Motors'), true);
  assert.equal(session.isBuickB233Identity('Buick E2LB Other Manufacturer'), false);
  assert.equal(session.isBuickB233Identity('Buick SAIC General Motors'), false);
  assert.equal(session.isBuickB233Identity('B233 SAIC General Motors'), false);
  const NewProtocolTarget = loadMethods('session/Iap2SenderSession.ets', 'Iap2SenderSession',
    ['requestWifiConfiguration'], {
      MESSAGE: { CARPLAY_AVAILABILITY: 0x4300, CARPLAY_START_SESSION: 0x4301,
        WIFI_REQUEST: 0x5702, WIFI_CONFIGURATION: 0x5703 },
      shouldProbeLegacyWifi: session.shouldProbeLegacyWifi
    });
  const newProtocolTarget = new NewProtocolTarget();
  newProtocolTarget.accessorySendMessages = Array(10).fill(0x4301);
  newProtocolTarget.accessoryReceiveMessages = Array(10).fill(0x4300);
  newProtocolTarget.log = () => {};
  let newProtocolAnnouncements = 0;
  newProtocolTarget.sendDeviceAnnouncement = async () => { newProtocolAnnouncements++; };
  newProtocolTarget.sendControl = async () => { throw new Error('complete new-protocol lists must skip 0x5702'); };
  await newProtocolTarget.requestWifiConfiguration();
  assert.equal(newProtocolAnnouncements, 1);

  const deviceIdentifier = '0123456789ABCDEF01234567';
  const bluetoothAddress = 'AA:BB:CC:DD:EE:FF';
  const groups = decodeParameters(session.encodeBuickB233AvailabilityBody(deviceIdentifier, bluetoothAddress));
  assert.deepEqual(groups.map(group => group.id), [0, 1]);
  assert.equal(decodeString(decodeParameters(groups[0].value)[1].value), deviceIdentifier);
  assert.equal(decodeString(decodeParameters(groups[1].value)[1].value), bluetoothAddress);
  assert.throws(() => session.encodeBuickB233AvailabilityBody(deviceIdentifier, '02:00:00:00:00:00'));
  assert.throws(() => session.encodeBuickB233AvailabilityBody(deviceIdentifier, '00:00:00:00:00:00'));

  const normalize = value => value.toLowerCase().replace(/\s+/g, ' ').trim();
  const Target = loadMethods('session/Iap2SenderSession.ets', 'Iap2SenderSession',
    ['chooseChallengeLength', 'prioritizeStoredChallengeLength'], {
      isBuickB233Identity: session.isBuickB233Identity,
      normalizeAccessoryIdentity: normalize,
      readAccessoryIdentity: bytes => new TextDecoder().decode(bytes),
      prioritizeStoredChallengeLength: async () => {}
    });
  const target = new Target();
  target.log = () => {};
  await target.chooseChallengeLength(new TextEncoder().encode(identity));
  assert.deepEqual(Array.from(target.challengeLengths), [32]);
  await target.chooseChallengeLength(new TextEncoder().encode('BUICK_7841 E2LB SAIC General Motors'));
  assert.deepEqual(Array.from(target.challengeLengths), [32]);
  await target.chooseChallengeLength(new TextEncoder().encode('Audi MIB3'));
  assert.deepEqual(Array.from(target.challengeLengths), [20, 32, 16]);

  let digestInput;
  const IdentifierTarget = loadMethods('session/Iap2SenderSession.ets', 'Iap2SenderSession',
    ['buickCarPlayDeviceIdentifier'], {
      cryptoFramework: { createMd: algorithm => {
        assert.equal(algorithm, 'SHA256');
        return {
          update: async ({ data }) => { digestInput = new TextDecoder().decode(data); },
          digest: async () => ({ data: Uint8Array.from({ length: 32 }, (_, index) => index) })
        };
      } },
      encodeUtf8
    });
  const identifierTarget = new IdentifierTarget();
  identifierTarget.deviceAddress = bluetoothAddress.toLowerCase();
  assert.equal(await identifierTarget.buickCarPlayDeviceIdentifier(), '000102030405060708090A0B');
  assert.equal(digestInput, 'CarDeck-CarPlay:AA:BB:CC:DD:EE:FF');
});

test('MFi challenge memory prioritizes and persists a successful length by hashed receiver identity', async () => {
  const stored = new Map();
  const writes = [];
  let flushed = 0;
  const store = {
    get: async (key, fallback) => stored.get(key) ?? fallback,
    put: async (key, value) => { stored.set(key, value); writes.push([key, value]); },
    flush: async () => { flushed++; }
  };
  const Target = loadMethods('session/Iap2SenderSession.ets', 'Iap2SenderSession',
    ['prioritizeStoredChallengeLength', 'persistSuccessfulChallengeLength'], {
      cryptoFramework: { createMd: () => ({
        update: async () => {},
        digest: async () => ({ data: Uint8Array.from({ length: 32 }, (_, index) => index) })
      }) },
      encodeUtf8: text => new TextEncoder().encode(text),
      preferences: { getPreferences: async (_context, name) => {
        assert.equal(name, 'carplayer_mfi_challenge_memory');
        return store;
      } }
    });
  const target = new Target();
  target.context = {};
  target.accessoryIdentity = 'receiver model manufacturer';
  target.challengeLengths = [20, 32, 16];
  target.challengeLength = 20;
  target.buickB233Receiver = false;
  target.log = () => {};
  target.errorDetails = error => error.message;
  stored.set('receiver_000102030405060708090a0b', 32);
  await target.prioritizeStoredChallengeLength();
  assert.deepEqual(Array.from(target.challengeLengths), [32, 20, 16]);
  assert.equal(target.challengeLength, 32);
  await target.persistSuccessfulChallengeLength(32);
  assert.deepEqual(writes, [['receiver_000102030405060708090a0b', 32]]);
  assert.equal(flushed, 1);
});

test('Buick B233 bypasses the legacy Wi-Fi request even with sparse capabilities', async () => {
  const Target = loadMethods('session/Iap2SenderSession.ets', 'Iap2SenderSession',
    ['requestWifiConfiguration'], { shouldProbeLegacyWifi: () => true });
  const target = new Target();
  target.buickB233Receiver = true;
  target.log = () => {};
  target.errorDetails = error => error.message;
  let announcements = 0;
  let controls = 0;
  target.sendDeviceAnnouncement = async () => { announcements++; };
  target.sendControl = async () => { controls++; };
  await target.requestWifiConfiguration();
  assert.equal(announcements, 1);
  assert.equal(controls, 0);
});

test('Buick B233 re-identification is one-shot and buffers an early 0x4301', async () => {
  const Target = loadMethods('session/Iap2SenderSession.ets', 'Iap2SenderSession',
    ['receiveControlMessage'], {
      MESSAGE: { IDENTIFICATION_INFORMATION: 0x1d01, IDENTIFICATION_ACCEPTED: 0x1d02,
        MFI_CERTIFICATE_REQUEST: 0xaa00, CARPLAY_START_SESSION: 0x4301 },
      formatIap2MessageDiagnostic: () => '',
      isBuickB233Identity: value => value.includes('buick') && value.includes('b233') &&
        value.includes('saic general motors'),
      normalizeAccessoryIdentity: value => value.toLowerCase().replace(/\s+/g, ' ').trim(),
      readAccessoryIdentity: bytes => new TextDecoder().decode(bytes),
      readEaProtocols: () => []
    });
  const target = new Target();
  target.log = () => {};
  target.chooseChallengeLength = () => {};
  target.logMfiMessageCapabilities = () => {};
  target.clearMfiChallenge = () => {};
  target.clearMfiCertificateTimer = () => {};
  target.clearBuickStartSessionTimer = () => {};
  target.startMfiCertificateTimer = () => {};
  const sent = [];
  target.sendControl = async messageId => { sent.push(messageId); };
  target.accessoryIdentity = 'buick b233 saic general motors';
  target.buickB233Receiver = true;
  target.buickAvailabilitySent = true;
  target.authenticated = true;

  await target.receiveControlMessage(0x1d01, new TextEncoder().encode(target.accessoryIdentity));
  assert.equal(target.authenticated, true);
  assert.deepEqual(sent, []);
  target.buickWaitingForStartSession = true;
  target.buickReidentificationWindowOpen = false;
  await target.receiveControlMessage(0x1d01, new TextEncoder().encode(target.accessoryIdentity));
  assert.equal(target.authenticated, true);
  assert.deepEqual(sent, []);
  target.buickReidentificationWindowOpen = true;
  await target.receiveControlMessage(0x1d01, new TextEncoder().encode('Audi MIB3'));
  assert.equal(target.authenticated, true);
  assert.deepEqual(sent, []);
  await target.receiveControlMessage(0x1d01, new TextEncoder().encode(target.accessoryIdentity));
  assert.equal(target.buickReauthenticationInProgress, true);
  assert.equal(target.buickReidentificationUsed, true);
  assert.deepEqual(sent, [0x1d02, 0xaa00]);
  await target.receiveControlMessage(0x1d01, new TextEncoder().encode(target.accessoryIdentity));
  assert.deepEqual(sent, [0x1d02, 0xaa00]);
  await target.receiveControlMessage(0x4301, new Uint8Array([1, 2, 3]));
  assert.deepEqual(Array.from(target.pendingBuickStartSession), [1, 2, 3]);
});

test('Buick B233 echoes only the first DETECT marker while waiting for 0x4301', async () => {
  const marker = new Uint8Array([0xff, 0x55, 0x02, 0x00, 0xee, 0x10]);
  const Target = loadMethods('session/Iap2SenderSession.ets', 'Iap2SenderSession',
    ['receiveDetectionMarker'], { LINK_MARKER: marker, formatRawBytesDiagnostic: () => '' });
  const target = new Target();
  const sent = [];
  const logs = [];
  target.log = message => logs.push(message);
  target.sendBytes = async bytes => { sent.push(Array.from(bytes)); };
  target.buickB233Receiver = true;
  target.buickWaitingForStartSession = true;
  target.buickMarkerEchoSent = false;
  target.started = true;
  target.identificationRequested = true;

  await target.receiveDetectionMarker();
  await target.receiveDetectionMarker();
  assert.deepEqual(sent, [Array.from(marker)]);
  assert.equal(target.started, true);
  assert.equal(target.identificationRequested, true);
  assert.equal(target.buickMarkerEchoSent, true);
  assert.ok(logs.some(message => message.includes('忽略重复 DETECT marker')));
});

test('Buick B233 T21 reports a redacted 0x4300 fingerprint and keeps a silent link alive', async () => {
  const timers = [];
  const Target = loadMethods('session/Iap2SenderSession.ets', 'Iap2SenderSession',
    ['startBuickStartSessionWaitTimer', 'clearBuickStartSessionTimer'], {
      setTimeout: (callback, delayMs) => { timers.push({ callback, delayMs }); return timers.length; },
      clearTimeout: () => {}
    });
  const target = new Target();
  const logs = [];
  target.log = message => logs.push(message);
  target.controlAckSnapshot = () => 'link=up outstanding=7 queued=0 window=1 rxSeq=6';
  target.started = true;
  target.sessionGeneration = 4;
  target.buickWaitingForStartSession = true;
  target.buickReidentificationWindowOpen = true;
  target.buickAvailabilitySentAt = Date.now() - 30000;
  target.buickAvailabilityFrameDigest = 'a1b2c3d4e5f60708';
  target.buickMarkerEchoSent = true;

  target.startBuickStartSessionWaitTimer(4);
  assert.equal(timers[0].delayMs, 30000);
  timers[0].callback();
  assert.ok(logs.some(message => message.includes('T21') && message.includes('outstanding=7')));
  assert.ok(logs.some(message => message.includes('frameSHA256prefix=a1b2c3d4e5f60708')));
  assert.equal(target.started, true);
  assert.equal(target.buickWaitingForStartSession, true);
  assert.equal(target.buickReidentificationWindowOpen, false);
});

test('Buick B233 T21 digest failures do not block availability sending', async () => {
  const Target = loadMethods('session/Iap2SenderSession.ets', 'Iap2SenderSession',
    ['controlFrameDigest'], {
      cryptoFramework: { createMd: () => { throw new Error('digest unavailable'); } },
      encodeIap2Control: () => new Uint8Array([0x40, 0x40])
    });
  const target = new Target();
  const logs = [];
  target.log = message => logs.push(message);
  target.errorDetails = error => error.message;
  assert.equal(await target.controlFrameDigest(0x4300, new Uint8Array([1])), 'unavailable');
  assert.ok(logs.some(message => message.includes('不影响发送')));
});

test('Buick B233 announcements use separate initial and recovery message orders', async () => {
  const Target = loadMethods('session/Iap2SenderSession.ets', 'Iap2SenderSession',
    ['sendDeviceAnnouncement', 'sendDeviceStateGreetings'], {
      MESSAGE: { WIRELESS_UPDATE: 0x4e0d, DEVICE_LANGUAGE_UPDATE: 0x4e0a,
        DEVICE_INFORMATION_UPDATE: 0x4e09, DEVICE_TIME_UPDATE: 0x4e0b,
        DEVICE_UUID_UPDATE: 0x4e0c, CARPLAY_AVAILABILITY: 0x4300 },
      concatBytes: (...parts) => Uint8Array.from(parts.flatMap(part => Array.from(part))),
      currentDeviceLanguage: () => 'zh-CN',
      encodeBuickB233AvailabilityBody: () => new Uint8Array([0x43, 0x00]),
      numberParameter: () => new Uint8Array([1]),
      stringParameter: () => new Uint8Array([2]),
      setTimeout: callback => { callback(); return 1; }
    });
  const target = new Target();
  target.started = true;
  target.authenticated = true;
  target.sessionGeneration = 1;
  target.deviceName = 'iPhone';
  target.deviceUuid = 'test-device';
  target.deviceAddress = 'AA:BB:CC:DD:EE:FF';
  target.parameter = (_id, value) => value;
  const logs = [];
  target.log = message => logs.push(message);
  target.waitForControlQueueDrain = async () => true;
  target.controlFrameDigest = async () => '0123456789abcdef';
  target.controlAckSnapshot = () => 'outstanding=none queued=0';
  target.startBuickStartSessionWaitTimer = () => {};
  target.startStartSessionWaitTimer = () => {};
  target.clearBuickStartSessionTimer = () => {};
  target.buickCarPlayDeviceIdentifier = async () => 'A'.repeat(24);
  const sent = [];
  target.sendControl = async messageId => { sent.push(messageId); };
  target.buickB233Receiver = true;

  await target.sendDeviceAnnouncement();
  assert.deepEqual(sent, [0x4e0a, 0x4e09, 0x4e0b, 0x4e0c, 0x4300]);
  assert.equal(target.buickWaitingForStartSession, true);
  assert.equal(target.buickReidentificationWindowOpen, true);
  assert.ok(logs.some(message => message.includes('frameSHA256prefix=0123456789abcdef')));
  sent.length = 0;
  target.deviceAnnouncementSent = false;
  target.deviceStateGreetingsSent = false;
  target.buickReidentificationUsed = true;
  await target.sendDeviceAnnouncement();
  assert.deepEqual(sent, [0x4e0c, 0x4e0a, 0x4e0b, 0x4e09, 0x4300]);
  sent.length = 0;
  target.deviceAnnouncementSent = false;
  target.deviceStateGreetingsSent = false;
  target.buickB233Receiver = false;
  target.buickReidentificationUsed = false;
  await target.sendDeviceAnnouncement();
  assert.deepEqual(sent, [0x4e0d, 0x4e0a, 0x4e09, 0x4e0b, 0x4e0c, 0x4300]);
});

test('wireless startup never publishes an unknown identity as a pairing public key', () => {
  const { makeAirPlayServiceFromEndpoint } = loadEts('session/airplay/AirPlayEndpointFactory.ets', {},
    'makeAirPlayServiceFromEndpoint');
  const endpoint = { addresses: ['192.168.49.1'], port: 7000, deviceIdentifier: 'AA:BB:CC:DD:EE:FF',
    publicKey: '', unrecognizedIdentity: '24e3089a-b9c8-4998-beb2-ae9120b44053', sourceVersion: '450.14' };
  assert.equal(Object.hasOwn(makeAirPlayServiceFromEndpoint(endpoint).txt, 'pk'), false);
  endpoint.publicKey = 'a'.repeat(64);
  assert.equal(makeAirPlayServiceFromEndpoint(endpoint).txt.pk, 'a'.repeat(64));
});

test('wireless startup pairs from a complete iAP2 endpoint without an advertised key and rejects conflicts', () => {
  const { makeAirPlayServiceFromEndpoint } = loadEts('session/airplay/AirPlayEndpointFactory.ets', {},
    'makeAirPlayServiceFromEndpoint');
  const { normalizeDeviceIdentifier } = loadEts('session/airplay/AirPlayEndpointFactory.ets', {},
    'normalizeDeviceIdentifier');
  const { correlateAirPlayIdentity } = loadEts('network/AirPlayIdentityCorrelation.ets');
  const Target = loadMethods('session/SessionController.ets', 'SessionController',
    ['refreshDiscoveredAirPlay', 'makeAirPlayGatewayFallback'], { makeAirPlayServiceFromEndpoint, normalizeDeviceIdentifier,
      correlateAirPlayIdentity });
  const target = new Target();
  target.wifiNetworkLease = {};
  target.events = { onLog() {} };
  target.iap2AirPlayEndpoint = { addresses: ['fe80::1'], port: 7000,
    deviceIdentifier: 'AA:BB:CC:DD:EE:FF', publicKey: '', sourceVersion: '450.14' };
  target.refreshDiscoveredAirPlay();
  assert.equal(target.discoveredAirPlay.host, 'fe80::1');
  assert.equal(target.discoveredAirPlay.port, 7000);
  assert.equal(Object.hasOwn(target.discoveredAirPlay.txt, 'pk'), false);
  target.mdnsAirPlayService = { host: '192.168.49.1', port: 7000, name: 'receiver',
    txt: { deviceid: 'AA:BB:CC:DD:EE:FF' } };
  target.refreshDiscoveredAirPlay();
  assert.equal(target.discoveredAirPlay.host, '192.168.49.1');
  assert.equal(Object.hasOwn(target.discoveredAirPlay.txt, 'pk'), false);
  target.mdnsAirPlayService.txt.pk = 'a'.repeat(64);
  target.refreshDiscoveredAirPlay();
  assert.equal(target.discoveredAirPlay.txt.pk, 'a'.repeat(64));
  target.mdnsAirPlayService.txt.deviceid = '11:22:33:44:55:66';
  target.refreshDiscoveredAirPlay();
  assert.equal(target.discoveredAirPlay.host, 'fe80::1');
  assert.equal(Object.hasOwn(target.discoveredAirPlay.txt, 'pk'), false);
  target.iap2AirPlayEndpoint.publicKey = 'b'.repeat(64);
  target.mdnsAirPlayService.txt.deviceid = 'AA:BB:CC:DD:EE:FF';
  let rejected = false;
  target.rejectAirPlayIdentityConflict = () => { rejected = true; };
  target.refreshDiscoveredAirPlay();
  assert.equal(rejected, true);
});

test('iAP2 Buick EA groups ignore the short language field and parse 16-bit protocol IDs', () => {
  const concatBytes = (...parts) => Uint8Array.from(parts.flatMap(part => [...part]));
  const parameter = (id, value) => {
    const length = value.length + 4;
    return concatBytes(
      Uint8Array.of(length >> 8, length & 0xff, id >> 8, id & 0xff),
      value
    );
  };
  const stringValue = text => new TextEncoder().encode(`${text}\0`);
  const group = (id, protocolId, name) => parameter(id, concatBytes(
    parameter(0, Uint8Array.of(0, protocolId)),
    parameter(1, stringValue(name))
  ));
  const decodeIap2Parameters = bytes => {
    const result = [];
    for (let offset = 0; offset < bytes.length;) {
      const length = (bytes[offset] << 8) | bytes[offset + 1];
      assert.ok(length >= 4 && offset + length <= bytes.length);
      const id = (bytes[offset + 2] << 8) | bytes[offset + 3];
      result.push({ id, value: bytes.slice(offset + 4, offset + length) });
      offset += length;
    }
    return result;
  };
  const { readEaProtocols } = loadEts('session/iap2/Iap2SessionProtocol.ets', {
    '@ohos.i18n': { System: { getSystemLanguage: () => 'en' } },
    '../../protocol/Iap2Codec': {
      concatBytes,
      decodeIap2Parameters,
      decodeIap2String: bytes => new TextDecoder().decode(bytes).split('\0')[0],
      formatIap2LinkPayloadDiagnostic: () => '',
      groupedParameter: parameter,
      numberParameter: parameter,
      stringParameter: (id, value) => parameter(id, stringValue(value))
    },
    '../ProtocolLogger': { formatProtocolEvent: () => '' }
  });
  const body = concatBytes(
    parameter(0x0c, new TextEncoder().encode('zh')),
    group(0x11, 2, 'CinemoBTComponent'),
    group(0x18, 3, 'CinemoWIFIComponent'),
    group(0x12, 1, 'CinemoHIDRemote')
  );

  assert.deepEqual(readEaProtocols(body), [
    { protocolId: 2, name: 'CinemoBTComponent' },
    { protocolId: 3, name: 'CinemoWIFIComponent' },
    { protocolId: 1, name: 'CinemoHIDRemote' }
  ]);
});

test('wireless gateway fallback uses only the selected WLAN route and never invents a pairing key', () => {
  const { makeAirPlayServiceFromEndpoint } = loadEts('session/airplay/AirPlayEndpointFactory.ets', {},
    'makeAirPlayServiceFromEndpoint');
  const Target = loadMethods('session/SessionController.ets', 'SessionController',
    ['refreshDiscoveredAirPlay', 'makeAirPlayGatewayFallback'], { makeAirPlayServiceFromEndpoint });
  const target = new Target();
  target.events = { onLog() {} };
  target.wifiNetworkLease = { defaultGatewayAddress: '192.168.49.1' };
  target.iap2AirPlayEndpoint = { addresses: [], port: 0, deviceIdentifier: 'AA:BB:CC:DD:EE:FF',
    publicKey: '', unrecognizedIdentity: 'untrusted-identity', sourceVersion: '450.14' };
  target.mdnsAirPlayService = undefined;
  target.airPlayIdentityConflict = false;
  target.refreshDiscoveredAirPlay();
  assert.equal(target.discoveredAirPlay.host, '192.168.49.1');
  assert.equal(target.discoveredAirPlay.port, 7000);
  assert.equal(target.discoveredAirPlay.txt.deviceid, 'AA:BB:CC:DD:EE:FF');
  assert.equal(Object.hasOwn(target.discoveredAirPlay.txt, 'pk'), false);

  target.wifiNetworkLease.defaultGatewayAddress = undefined;
  target.iap2AirPlayEndpoint = undefined;
  target.refreshDiscoveredAirPlay();
  assert.equal(target.discoveredAirPlay, undefined);
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
  target.clearWifiConfigurationTimer = () => {};
  target.clearStartSessionWaitTimer = () => {};
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
        return { interfaceName: 'wlan0', linkAddresses: [
          { address: { address: handle.netId === 3 ? '10.36.232.67' : '192.168.1.2' }, prefixLength: 24 },
          ...(handle.netId === 3 ? [{ address: { address: 'fe80::3' }, prefixLength: 64 }] : [])
        ] };
      },
      createNetConnection(specifier, timeout) {
        assert.equal(specifier.bearerPrivateIdentifier, undefined);
        assert.equal(timeout, 15000);
        return { on(name, handler) { handlers[name] = handler; },
          register(callback) { callback(); }, unregister(callback) { unregistered++; callback(); } };
      }
    }
  });
  const lease = new WifiNetworkLease();
  let lost = false;
  assert.equal((await lease.acquire('BUICK_7841', () => { lost = true; }, () => {}, '10.36.232.67')).netId, 3);
  assert.equal(lease.isAirPlayAddressOnSelectedNetwork('10.36.232.98'), true);
  assert.equal(lease.isAirPlayAddressOnSelectedNetwork('10.36.233.98'), false);
  assert.equal(lease.isAirPlayAddressOnSelectedNetwork('fe80::1899:7bff:fe39:e165%wlan0'), true);
  const selectedIpv6Address = lease.localAddresses.ipv6;
  const selectedIpv6PrefixLength = lease.localAddresses.ipv6PrefixLength;
  lease.localAddresses.ipv6 = '2001:db8:1::1';
  lease.localAddresses.ipv6PrefixLength = 64;
  assert.equal(lease.isAirPlayAddressOnSelectedNetwork('2001:db8:1::ab'), true);
  assert.equal(lease.isAirPlayAddressOnSelectedNetwork('2001:db8:2::ab'), false);
  lease.localAddresses.ipv6 = selectedIpv6Address;
  lease.localAddresses.ipv6PrefixLength = selectedIpv6PrefixLength;
  await lease.bindSocket({ async bind(address) {
    socketEvents.push('socket-bind');
    assert.deepEqual(address, { address: '10.36.232.67', family: 1, port: 0 });
  } }, 'test IPv4 TCP');
  await lease.bindSocket({ async bind(address) {
    assert.deepEqual(address, { address: 'fe80::3%wlan0', family: 2, port: 0 });
  } }, 'test IPv6 TCP', 2);
  await lease.bindSocket({ async bind(address) {
    assert.deepEqual(address, { address: '10.36.232.67', family: 1, port: 5353 });
  } }, 'test mDNS multicast', 1, 5353);
  assert.deepEqual(socketEvents, ['socket-bind', 'network-bind', 'network-bind', 'network-bind']);
  assert.equal(bound, 3);
  handlers.netLost(vehicleWifi);
  assert.equal(lost, true);
  await assert.rejects(lease.bindSocket({}), /默认路由/);
  await lease.release();
  assert.equal(unregistered, 1);
});

test('wireless network lease scopes link-local addresses to the selected interface', () => {
  const { WifiNetworkLease, orderAirPlayAddresses, stripIpv6ScopeId } = loadEts('network/WifiNetworkLease.ets', {
    '@ohos.net.connection': {}
  });
  const lease = new WifiNetworkLease();
  lease.localAddresses = { interfaceName: 'wlan0' };
  assert.equal(lease.scopeLinkLocalAddress('fe80::1899:7bff:fe39:e165'),
    'fe80::1899:7bff:fe39:e165%wlan0');
  assert.equal(lease.scopeLinkLocalAddress('fe80::1%wlan0'), 'fe80::1%wlan0');
  assert.equal(lease.scopeLinkLocalAddress('192.168.49.1'), '192.168.49.1');
  assert.equal(stripIpv6ScopeId('fe80::1899:7bff:fe39:e165%wlan0'), 'fe80::1899:7bff:fe39:e165');
  assert.equal(stripIpv6ScopeId('192.168.49.1'), '192.168.49.1');
  assert.deepEqual(orderAirPlayAddresses([
    'fe80::1%wlan0', '2001:db8::1', '192.168.49.2', 'fe80::1', 'receiver.local', '192.168.49.2'
  ]), ['192.168.49.2', '2001:db8::1', 'fe80::1%wlan0', 'receiver.local']);
  lease.localAddresses = {};
  assert.throws(() => lease.scopeLinkLocalAddress('fe80::1'), /interfaceName is unavailable/);
});

test('IPv6 socket uses a wildcard local bind when the selected WLAN has no enumerated IPv6 address', async () => {
  const { WifiNetworkLease } = loadEts('network/WifiNetworkLease.ets', {
    '@ohos.net.connection': {}
  });
  const lease = new WifiNetworkLease();
  const actions = [];
  lease.netHandle = {
    netId: 25,
    async bindSocket() { actions.push('network-bind'); }
  };
  lease.localAddresses = { ipv4: '10.12.82.67', interfaceName: 'wlan0' };
  await lease.bindSocket({
    async bind(address) {
      actions.push({ type: 'local-bind', address });
    }
  }, 'test IPv6 TCP', 2);
  assert.deepEqual(actions, [
    { type: 'local-bind', address: { address: '::', family: 2, port: 0 } },
    'network-bind'
  ]);
});

test('AirPlay RTSP connection strips IPv6 scope IDs before connecting', async () => {
  const attempts = [];
  class StubAirPlayRtspClient {
    constructor() {}
    async connect(host, port) { attempts.push({ host, port }); }
    async close() {}
  }
  const { WifiNetworkLease, orderAirPlayAddresses, stripIpv6ScopeId } = loadEts('network/WifiNetworkLease.ets', {
    '@ohos.net.connection': {}
  });
  const Target = loadMethods('airplay/AirPlayPairingClient.ets', 'AirPlayPairingClient', ['connect'], {
    AirPlayRtspClient: StubAirPlayRtspClient,
    orderAirPlayAddresses,
    stripIpv6ScopeId,
    formatProtocolEvent: (event, ...fields) => `${event}:${fields.join(',')}`
  });
  const lease = new WifiNetworkLease();
  lease.localAddresses = { interfaceName: 'wlan0' };
  const target = new Target();
  target.log = () => {};
  target.onDisconnected = () => {};
  target.wifiNetworkLease = lease;
  await target.connect({
    host: 'fe80::1899:7bff:fe39:e165%wlan0',
    addresses: [],
    port: 7000
  });
  assert.deepEqual(attempts, [{ host: 'fe80::1899:7bff:fe39:e165', port: 7000 }]);
  assert.equal(target.connectedHost, 'fe80::1899:7bff:fe39:e165');
});

test('AirPlay RTSP tries IPv4 endpoint candidates before IPv6 candidates', async () => {
  const attempts = [];
  class StubAirPlayRtspClient {
    constructor() {}
    async connect(host, port) { attempts.push({ host, port }); }
    async close() {}
  }
  const { orderAirPlayAddresses, stripIpv6ScopeId } = loadEts('network/WifiNetworkLease.ets', {
    '@ohos.net.connection': {}
  });
  const Target = loadMethods('airplay/AirPlayPairingClient.ets', 'AirPlayPairingClient', ['connect'], {
    AirPlayRtspClient: StubAirPlayRtspClient,
    orderAirPlayAddresses,
    stripIpv6ScopeId,
    formatProtocolEvent: (event, ...fields) => `${event}:${fields.join(',')}`
  });
  const target = new Target();
  target.log = () => {};
  target.onDisconnected = () => {};
  target.wifiNetworkLease = {};
  await target.connect({
    host: 'fe80::1899:7bff:fe39:e165',
    addresses: ['2001:db8::2', '192.168.49.8'],
    port: 7000
  });
  assert.deepEqual(attempts, [{ host: '192.168.49.8', port: 7000 }]);
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

test('wireless discovery and ctrl advertisement start only after network selection', async () => {
  const Target = loadMethods('session/SessionController.ets', 'SessionController', ['joinVehicleWifi']);
  const target = new Target();
  const actions = [];
  target.running = true;
  target.wifiJoinGeneration = 0;
  target.wifiReconnectTimer = -1;
  target.wifiReconnectAttempts = 0;
  target.clearWifiReconnectTimer = () => {};
  target.scheduleWifiReconnect = () => {};
  target.deviceAddress = '40:06:34:E5:ED:EA';
  target.adapterMode = false;
  target.bluetooth = { setAdapterHandoffCompleted() {} };
  target.credentials = { ssid: 'BUICK_7841', password: 'test-password', securityType: 3, channel: 149 };
  target.iap2 = { isAuthenticationComplete: true, async onWifiConnected() { actions.push('iap2'); } };
  target.events = { onLog() {}, onStatus() {} };
  target.requestPermissions = async () => {};
  target.wifi = { async connect() { return { ssid: 'BUICK_7841', ipAddress: '10.36.232.67' }; } };
  target.startControlAdvertisement = async (reannounce) => {
    actions.push(reannounce ? 'reannounce' : 'advertise');
  };
  target.startAirPlayDiscovery = () => { actions.push('discovery'); };
  target.startAirPlayPrerequisiteWait = () => {};
  let finishNetwork;
  target.wifiNetworkLease = { acquire() {
    actions.push('network');
    return new Promise(resolve => { finishNetwork = resolve; });
  } };
  target.refreshDiscoveredAirPlay = () => { actions.push('refresh'); };
  target.connectAirPlay = async () => { actions.push('pair'); };
  const joining = target.joinVehicleWifi();
  for (let turn = 0; turn < 20 && !finishNetwork; turn++) await Promise.resolve();
  assert.deepEqual(actions, ['iap2', 'network']);
  assert.notEqual(target.vehicleWifiConnected, true);
  finishNetwork({ netId: 3 });
  await joining;
  assert.equal(target.vehicleWifiConnected, true);
  assert.deepEqual(actions, ['iap2', 'network', 'refresh', 'discovery', 'reannounce', 'pair']);
  assert.equal(actions.at(-1), 'pair');
  const diagnostics = [];
  target.vehicleWifiConnected = false;
  target.events.onLog = message => diagnostics.push(message);
  target.startControlAdvertisement = async () => { throw new Error('mDNS registration failed'); };
  target.wifiNetworkLease.acquire = async () => ({ netId: 3 });
  await target.joinVehicleWifi();
  assert.equal(target.vehicleWifiConnected, true);
  assert.equal(actions.filter(action => action === 'pair').length, 2);
  assert.ok(diagnostics.some(message => /WARN:.*控制广播不可用.*mDNS registration failed/.test(message)));
  target.vehicleWifiConnected = false;
  target.wifiNetworkLease.acquire = async () => { throw new Error('no matching WLAN'); };
  await assert.rejects(target.joinVehicleWifi(), /无法确认 WLAN 选路/);
  assert.equal(target.vehicleWifiConnected, false);
  assert.equal(actions.filter(action => action === 'pair').length, 2);
});

test('selected WLAN loss cleans up AirPlay and schedules a bounded Wi-Fi rejoin', async () => {
  const timers = [];
  let timerId = 0;
  const Target = loadMethods('session/SessionController.ets', 'SessionController',
    ['handleVehicleWifiLost', 'scheduleWifiReconnect'], {
      setTimeout: (callback, delayMs) => {
        timers.push({ callback, delayMs });
        return ++timerId;
      },
      clearTimeout: () => {}
    });
  const target = new Target();
  const actions = [];
  let rejoins = 0;
  target.running = true;
  target.credentials = { ssid: 'CAR_HOTSPOT', password: 'hidden' };
  target.wifiReconnectTimer = -1;
  target.wifiReconnectAttempts = 0;
  target.wifiLostCleanupInProgress = false;
  target.clearWifiReconnectTimer = () => {};
  target.clearPendingStartSessionTimer = () => {};
  target.airPlayGeneration = 0;
  target.airPlayConnectAttempted = true;
  target.airPlayConnectInProgress = true;
  target.vehicleWifiConnected = true;
  target.bluetooth = { setAdapterHandoffCompleted() {} };
  target.inviteReceived = true;
  target.events = { onStatus() {}, onLog() {} };
  target.clearAirPlayTimers = () => {};
  target.stopProjection = async () => { actions.push('projection'); };
  target.wifiNetworkLease = { release: async () => { actions.push('lease'); } };
  target.activePairing = {
    stopMediaSession: async () => { actions.push('media'); },
    close: async () => { actions.push('pairing'); }
  };
  target.discovery = { stop: () => { actions.push('discovery'); } };
  target.ctrlAdvertiser = { stop: async () => { actions.push('advertiser'); } };
  target.joinVehicleWifi = async () => { rejoins++; };

  await target.handleVehicleWifiLost('selected network lost');
  assert.equal(target.vehicleWifiConnected, false);
  assert.equal(target.inviteReceived, false);
  assert.deepEqual(actions, ['media', 'projection', 'pairing', 'discovery', 'advertiser', 'lease']);
  assert.equal(timers[0].delayMs, 1000);
  timers.shift().callback();
  for (let turn = 0; turn < 5; turn++) await Promise.resolve();
  assert.equal(rejoins, 1);
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
  const contentSource = fs.readFileSync(path.join(sourceRoot, 'pages/ProjectionDashboardContent.ets'), 'utf8');
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
  const { ProjectionTouchRouter } = loadEts('pages/ProjectionTouchRouter.ets');
  const Target = vm.runInNewContext(`${javascript}\nTarget`, {
    AppStorage: {
      setOrCreate: (name, value) => stored.set(name, value),
      get: key => stored.get(key)
    },
    HOME_APP: { appId: 'shell-home', uri: 'carplay-client://v1/shell/home', category: 'home' },
    PROJECTION_MAP_URI: 'carplay-client://v1/apps/amap/launch',
    ProjectionTouchRouter
  });
  const target = new Target();
  target.touchRouter = new ProjectionTouchRouter();
  target.activeAppUri = 'carplay-client://v1/apps/amap/launch';
  target.activeAppLabel = 'Amap';
  target.onHomeClick = () => { throw new Error('must not release navigation on preview'); };
  target.onAppClick = () => { throw new Error('must not relaunch navigation on expansion'); };
  target.selectApp({ appId: 'shell-home', uri: 'carplay-client://v1/shell/home', category: 'home' });
  assert.equal(target.navigationPreview, true);
  assert.equal(stored.get('carplayNavigationPreview'), true);
  target.setNavigationPreview(false);
  assert.equal(stored.get('carplayNavigationPreview'), false);
  assert.equal((contentSource.match(/surfaceName: 'projectionAppSurface'/g) || []).length, 1);
});

test('home selects a map preview and shows HTML-style music and weather cards', async () => {
  const source = fs.readFileSync(path.join(sourceRoot, 'pages/ProjectionDashboard.ets'), 'utf8');
  const contentSource = fs.readFileSync(path.join(sourceRoot, 'pages/ProjectionDashboardContent.ets'), 'utf8');
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
  const { ProjectionTouchRouter } = loadEts('pages/ProjectionTouchRouter.ets');
  const Target = vm.runInNewContext(`${javascript}\nTarget`, {
    AppStorage: {
      setOrCreate: (name, value) => stored.set(name, value),
      get: key => stored.get(key)
    },
    HOME_APP: { appId: 'shell-home', uri: 'carplay-client://v1/shell/home', category: 'home' },
    PROJECTION_MAP_URI: map.uri,
    discoverProjectionApps: () => [map],
    projectionAppCatalog: () => [map],
    isProjectionAppLaunchable: app => app.launchState === 'VERIFIED' && !!app.launchTarget,
    ProjectionTouchRouter
  });
  const target = new Target();
  target.touchRouter = new ProjectionTouchRouter();
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
  assert.match(contentSource, /private DashboardSidebar\(\)/);
  const sidebarSource = fs.readFileSync(path.join(sourceRoot, 'pages/ProjectionMediaSidebar.ets'), 'utf8');
  const musicCardEnd = sidebarSource.indexOf("Stack({ alignContent: Alignment.TopStart })");
  const musicCardSource = sidebarSource.slice(0, musicCardEnd);
  assert.doesNotMatch(musicCardSource, /projection_album_art|Image\(/);
  assert.equal((sidebarSource.match(/\.border\(\{ width: 1, color: this\.cardStrokeColor \}\)/g) || []).length, 2);
  assert.match(musicCardSource, /Text\(this\.title\)/);
  assert.match(musicCardSource, /Text\(this\.lyric \|\| '暂无歌词'\)/);
  assert.match(musicCardSource, /this\.MediaControl\('playPrevious'/);
  assert.match(musicCardSource, /this\.MediaControl\('playNext'/);
  assert.match(musicCardSource, /this\.progressPercent\(\)/);
  assert.match(sidebarSource, /app\.media\.projection_weather_sun/);
  assert.match(sidebarSource, /Text\('上海'\)/);
  assert.doesNotMatch(contentSource, /在手机打开地图/);
  assert.ok(!contentSource.includes('this.navigationPreview ? 0.7'), 'preview uses actual layout, not a floating scaled page');
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

test('Audio RTP selects TaskPool encryption for its per-packet synchronous ChaCha work', () => {
  const source = fs.readFileSync(path.join(sourceRoot, 'audio/AudioRtpSender.ets'), 'utf8');
  assert.match(source, /new MediaPacketCipher\(session\.streamKey,\s*true,\s*this\.log\)/);
});

function videoSenderFixture(send, split = data => [data]) {
  const sent = [];
  const encrypted = [];
  const legacyCryptoCalls = [];
  let keyFrameRequests = 0;
  const concatBytes = (...parts) => {
    const result = new Uint8Array(parts.reduce((total, part) => total + part.length, 0));
    let offset = 0;
    for (const part of parts) { result.set(part, offset); offset += part.length; }
    return result;
  };
  const api = loadEts('airplay/AirPlayVideoStream.ets', {
    '@ohos.security.cryptoFramework': {
      CryptoMode: { ENCRYPT_MODE: 0 },
      createSymKeyGenerator: () => ({ async convertKey(key) { return key; } }),
      createCipher: algorithm => ({
        async init(mode, key, params) { legacyCryptoCalls.push({ algorithm, mode, key, params }); },
        async update(data) {
          legacyCryptoCalls.push({ update: data.data.slice() });
          return { data: data.data.slice() };
        },
        async doFinal(data) {
          legacyCryptoCalls.push({ doFinal: data });
          return { data: new Uint8Array(0) };
        }
      })
    },
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
  return {
    sender,
    VideoSender: api.AirPlayVideoStreamSender,
    VideoEncryptionMode: api.AirPlayVideoEncryptionMode,
    sent,
    encrypted,
    event,
    sps,
    pps,
    frame,
    configure,
    keyFrameRequests: () => keyFrameRequests, legacyCryptoCalls };
}

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
    ['activateDock', 'isDashboardHome', 'activeAppHasCategory', 'isDockItemSelected',
      'categoryApp', 'launchableCategoryApp', 'dockItems'], {
      HOME_APP: { uri: 'home' },
      PROJECTION_MAP_URI: 'amap',
      findLaunchableProjectionApp,
      isProjectionAppLaunchable
    });
  const dashboardSource = fs.readFileSync(path.join(sourceRoot, 'pages/ProjectionDashboard.ets'), 'utf8');
  const dockSource = fs.readFileSync(path.join(sourceRoot, 'pages/ProjectionDock.ets'), 'utf8');
  const dockMenuSource = fs.readFileSync(path.join(sourceRoot, 'pages/ProjectionDockMenu.ets'), 'utf8');
  assert.match(dockSource, /Scroll\(this\.scroller\)/);
  assert.match(dockSource, /\.width\(vertical \? '100%' : 64\)/);
  assert.match(dockSource, /\.height\(vertical \? 48 : '100%'\)/);
  const dockItemStart = dockSource.indexOf('private DockItem');
  const dockItemEnd = dockSource.indexOf('@Builder', dockItemStart + 1);
  assert.doesNotMatch(dockSource.slice(dockItemStart, dockItemEnd), /\.layoutWeight\(1\)/);
  assert.match(dockMenuSource, /accessibilityText\(this\.mapOnPhone \? '切换地图到虚拟屏' : '切换地图到手机'\)/);
  assert.match(dockMenuSource, /'maps', 'toggleDisplay', newArea, \(\): void => this\.onToggleMapDisplay\(\)/);
  assert.match(dockMenuSource, /this\.onToggleAppDisplay\(\)/);
  const dockTarget = new Target();
  dockTarget.isDockItemSelected = (id) => id === 'music';
  assert.equal(JSON.stringify(dockTarget.dockItems().map(item => [item.id, item.selected])), JSON.stringify([
    ['home', false], ['apps', false], ['map', false], ['music', true], ['split', false], ['settings', false]
  ]));
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
  target.navigationPreview = true;
  target.activeAppUri = 'amap';
  assert.equal(target.isDockItemSelected('home'), true);
  assert.equal(target.isDockItemSelected('map'), false);
  target.navigationPreview = false;
  target.activeAppLabel = 'Map';
  assert.equal(target.isDockItemSelected('home'), false);
  assert.equal(target.isDockItemSelected('map'), true);
  target.activeAppUri = 'otherMusic';
  target.activeAppLabel = 'Music';
  target.selectedMusicUri = 'music';
  assert.equal(target.isDockItemSelected('music'), true,
    'highlight follows the running music app rather than the previous selection');
  target.dashboardView = 'maps';
  assert.equal(target.isDockItemSelected('map'), true);
  assert.equal(target.isDockItemSelected('music'), false);
  target.dashboardView = 'split';
  assert.equal(target.isDockItemSelected('split'), true);
  assert.equal(target.isDockItemSelected('map'), false);
  target.dashboardView = 'home';
  target.activeAppUri = '';
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

test('Dock selection follows the active app and current dashboard view', () => {
  const Target = loadMethods('pages/ProjectionDashboard.ets', 'ProjectionDashboard', [
    'isDashboardHome', 'activeAppHasCategory', 'isDockItemSelected'
  ]);
  const target = new Target();
  target.apps = [
    { uri: 'map-a', category: 'map' },
    { uri: 'music-a', category: 'music' },
    { uri: 'music-b', category: 'music' }
  ];
  target.dashboardView = 'home';
  target.activeAppLabel = '音乐';
  target.activeAppUri = 'music-b';
  target.navigationPreview = false;
  assert.equal(target.isDockItemSelected('music'), true);
  assert.equal(target.isDockItemSelected('map'), false);

  target.activeAppUri = 'map-a';
  assert.equal(target.isDockItemSelected('map'), true);
  target.navigationPreview = true;
  assert.equal(target.isDockItemSelected('home'), true);
  assert.equal(target.isDockItemSelected('map'), false);

  target.dashboardView = 'music';
  assert.equal(target.isDockItemSelected('music'), true);
  target.dashboardView = 'split';
  assert.equal(target.isDockItemSelected('split'), true);
  assert.equal(target.isDockItemSelected('music'), false);
});

test('active projection apps are observable and both Dock layouts invalidate selected item nodes', () => {
  const homeSource = fs.readFileSync(path.join(sourceRoot, 'pages/ProjectionHome.ets'), 'utf8');
  assert.match(homeSource, /@State private activeApp: ProjectionApp \| undefined = undefined/);
  assert.match(homeSource, /@State private mapApp: ProjectionApp \| undefined = undefined/);
  assert.match(homeSource, /activeAppUri: this\.activeApp\?\.uri \?\? ''/);
  assert.match(homeSource, /mapAppUri: this\.mapApp\?\.uri \?\? ''/);
  const dockSource = fs.readFileSync(path.join(sourceRoot, 'pages/ProjectionDock.ets'), 'utf8');
  const parsed = ts.createSourceFile('Dock.ts', dockSource, ts.ScriptTarget.Latest, true);
  const keys = [];
  function visit(node) {
    if (ts.isCallExpression(node) && node.expression.getText(parsed) === 'ForEach') {
      keys.push(node.arguments[2].getText(parsed));
    }
    ts.forEachChild(node, visit);
  }
  visit(parsed);
  assert.equal(keys.length, 2);
  for (const keySource of keys) {
    const javascript = ts.transpileModule(`const key = ${keySource}; key;`, {
      compilerOptions: { target: ts.ScriptTarget.ES2020 }
    }).outputText;
    const key = vm.runInNewContext(javascript);
    for (const id of ['home', 'map', 'music', 'apps', 'split', 'settings']) {
      assert.notEqual(key({ id, selected: true }), key({ id, selected: false }));
      assert.equal(key({ id, selected: true }), key({ id, selected: true }));
    }
  }
  const Target = loadMethods('pages/ProjectionDashboardContent.ets', 'ProjectionDashboardContent', ['isActiveMap']);
  const target = new Target();
  target.apps = [{ uri: 'amap', category: 'map' }, { uri: 'music', category: 'music' }];
  for (const [uri, expected] of [['', false], ['amap', true], ['music', false], ['amap', true]]) {
    target.activeAppUri = uri;
    assert.equal(target.isActiveMap(), expected);
  }
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

test('split dashboard exposes ratio controls and requires an opened music app', () => {
  const source = fs.readFileSync(path.join(sourceRoot, 'pages/ProjectionDashboard.ets'), 'utf8');
  const contentSource = fs.readFileSync(path.join(sourceRoot, 'pages/ProjectionDashboardContent.ets'), 'utf8');
  const displaySource = fs.readFileSync(path.join(sourceRoot, 'pages/ProjectionDisplaySettingsPane.ets'), 'utf8');
  assert.match(source, /splitMapRatio/);
  assert.match(source, /splitMusicRatio/);
  assert.match(displaySource, /TextInput\(\{[\s\S]*splitMapRatioInput/);
  assert.match(contentSource, /\.layoutWeight\(this\.splitMapRatio\)/);
  assert.match(contentSource, /\.layoutWeight\(this\.splitMusicRatio\)/);
  assert.equal((contentSource.match(/\.layoutWeight\(this\.splitMapRatio\)/g) || []).length, 3);
  assert.equal((contentSource.match(/\.layoutWeight\(this\.splitMusicRatio\)/g) || []).length, 1);
  const mediaSidebar = fs.readFileSync(path.join(sourceRoot, 'pages/ProjectionMediaSidebar.ets'), 'utf8');
  assert.match(mediaSidebar, /\.layoutWeight\(this\.splitMusicRatio\)/);
  assert.doesNotMatch(source, /\.width\('22%'\)/);
  const splitStart = contentSource.indexOf('SplitPage()');
  const splitEnd = contentSource.indexOf('private DashboardSidebar()', splitStart);
  const splitSource = contentSource.slice(splitStart, splitEnd);
  assert.match(splitSource, /\.layoutWeight\(this\.splitMapRatio\)\s*\.height\('100%'\)/);
  assert.match(splitSource, /\.layoutWeight\(this\.splitMusicRatio\)\s*\.height\('100%'\)/);
  assert.match(splitSource, /surfaceName: 'projectionSplitMapSurface'[\s\S]*?\.width\('100%'\)\s*\.height\('100%'\)/);
  assert.doesNotMatch(splitSource, /surfaceName: 'projectionSplitMapSurface'[\s\S]*?\.aspectRatio\(/);
  const mainPanelStart = contentSource.indexOf('private MainPanel()');
  const mainPanelEnd = contentSource.indexOf('build()', mainPanelStart);
  const mainPanelSource = contentSource.slice(mainPanelStart, mainPanelEnd);
  assert.match(mainPanelSource, /surfaceName: 'projectionAppSurface'[\s\S]*?\.width\('100%'\)\s*\.height\('100%'\)/);
  assert.doesNotMatch(mainPanelSource, /surfaceName: 'projectionAppSurface'[\s\S]*?\.aspectRatio\(/);
  assert.doesNotMatch(source, /\b[345] : 1\b/);
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
  const catalog = loadEts('pages/ProjectionAppCatalog.ets');
  const { launchProjectionApp } = loadEts('pages/ProjectionAppLauncher.ets', {
    './ProjectionAppCatalog': {
      isProjectionAppLaunchable: catalog.isProjectionAppLaunchable,
      projectionAppLaunchTarget: catalog.projectionAppLaunchTarget
    }
  });
  const source = fs.readFileSync(path.join(sourceRoot, 'pages/ProjectionHome.ets'), 'utf8');
  assert.match(source, /launchProjectionApp\([\s\S]*app,\s*displayId,\s*preserveExistingInstance/);
  const calls = [];
  const hostContext = {
    async startAbility(want, options) { calls.push(JSON.parse(JSON.stringify({ want, options }))); }
  };
  await launchProjectionApp(() => hostContext, {
    appId: 'verified-music',
    uri: 'carplay-client://v1/apps/verified-music/launch',
    label: 'Verified Music',
    launchState: 'VERIFIED',
    launchTarget: { kind: 'appLink', uri: 'verified-music-link://' }
  }, 12);
  assert.deepEqual(calls, [{ want: { action: 'ohos.want.action.viewData', uri: 'verified-music-link://' },
    options: { displayId: 12 } }]);
  await launchProjectionApp(() => hostContext, {
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
  await launchProjectionApp(() => hostContext, amap, 18);
  assert.deepEqual(calls[2], {
    want: { action: 'ohos.want.action.viewData', uri: 'amapuri://' },
    options: { displayId: 18 }
  });
  await launchProjectionApp(() => hostContext, amap, 19, true);
  assert.deepEqual(calls[3], {
    want: { bundleName: 'com.amap.hmapp', moduleName: 'entry', abilityName: 'EntryAbility' },
    options: { displayId: 19 }
  });
  const nonSingletonAmap = {
    ...amap,
    launchTarget: { ...amap.launchTarget, isSingleton: false }
  };
  await assert.rejects(launchProjectionApp(() => hostContext, nonSingletonAmap, 20, true), /拒绝重新启动/);
  let contextRequests = 0;
  await assert.rejects(launchProjectionApp(() => {
    contextRequests++;
    return hostContext;
  }, {
    appId: 'amap',
    uri: 'carplay-client://v1/apps/amap/launch',
    label: 'Amap',
    launchState: 'UNVERIFIED'
  }, 17), /启动入口尚未验证/);
  assert.equal(contextRequests, 0);
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
  target.appContentWidth = 1200;
  target.appContentHeight = 700;
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
  const repositioned = { ...surface, left: 100 };
  await target.updateAppSurface(repositioned);
  assert.equal(target.appDisplayId, 23);
  assert.equal(published, repositioned);
  assert.equal(calls.length, 1);
  await target.updateAppSurface({ ...repositioned, surfaceId: 'broken' });
  assert.equal(target.appDisplayId, 23);
  assert.equal(published, repositioned);
  assert.equal(target.activeAppSurface, repositioned);
  assert.match(target.launchMessage, /surface unavailable/);
  await target.updateAppSurface(undefined);
  assert.equal(target.appDisplayId, 23);
  assert.equal(published, undefined);
  await target.updateAppSurface(repositioned);
  assert.equal(target.appDisplayId, 23);
  assert.equal(published, repositioned);
  assert.deepEqual(calls, [[23, 'new'], [23, 'new']]);
  assert.equal(target.launchMessage, '');
  const pending = target.updateAppSurface({ ...repositioned, surfaceId: 'delayed' });
  await target.updateAppSurface(undefined);
  releaseSurface();
  await pending;
  assert.equal(published, undefined, 'late binding must not restore a detached touch target');
  assert.equal(target.appSurfaceAttached, false);
});

test('resizing an app surface recreates its virtual screen with matching dimensions', async () => {
  const Target = loadMethods('pages/ProjectionHome.ets', 'ProjectionHome', ['updateAppSurface'], {
    AppStorage: { get: key => key === 'carplayProjectionDensity' ? 2 : undefined },
    projectionContentDisplayConfig: (width, height, density) => ({
      width: width * 2, height: height * 2, density: density * 2, scale: 2
    }),
    display: {
      async createVirtualScreen(options) {
        events.push(['create', options.width, options.height, options.density]);
        return 31;
      },
      async setVirtualScreenSurface(id, surfaceId) { events.push(['surface', id, surfaceId]); },
      async makeUnique(id) { events.push(['unique', id]); }
    }
  });
  const events = [];
  const target = new Target();
  target.appDisplayId = 23;
  target.appContentWidth = 1200;
  target.appContentHeight = 700;
  target.appDisplayGeneration = 0;
  target.appSurfaceGeneration = 0;
  target.activeAppSurface = { surfaceId: 'old', width: 1200, height: 700 };
  target.activeApp = { appId: 'music' };
  target.activeAppMoveExistingInstance = false;
  target.appOnPhone = false;
  target.appSwitching = false;
  target.launchMessage = '';
  target.logProjection = () => {};
  target.releaseAppDisplay = async () => {
    events.push(['release', target.appDisplayId]);
    target.appDisplayId = -1;
    target.appContentWidth = 0;
    target.appContentHeight = 0;
    target.activeAppSurface = undefined;
    target.appSurfaceAttached = false;
  };
  target.launchApp = async (_app, id) => events.push(['launch', id]);
  target.publishAppTouchBounds = surface => events.push(['publish', surface.width, surface.height]);
  await target.updateAppSurface({
    surfaceId: 'resized', left: 80, top: 10, width: 800, height: 640
  });
  assert.deepEqual(events, [
    ['release', 23],
    ['create', 1600, 1280, 4],
    ['surface', 31, 'resized'],
    ['unique', 31],
    ['launch', 31],
    ['publish', 800, 640]
  ]);
  assert.equal(target.appContentWidth, 1600);
  assert.equal(target.appContentHeight, 1280);
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
    projectionContentDisplayConfig: (width, height, density) => ({
      width: width * 2, height: height * 2, density: density * 2, scale: 2
    }),
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
    ['release', false], ['create', 1600, 800], ['surface', 24, 'map-surface'], ['unique', 24], ['launch', 'amap', 24]
  ]);
});

test('selecting map from split promotes it to the content display without a phone handoff', async () => {
  const Target = loadMethods('pages/ProjectionHome.ets', 'ProjectionHome', ['selectApp'], {
    AppStorage: { get: () => 'home' },
    isProjectionAppLaunchable: app => app.launchState === 'VERIFIED' && !!app.launchTarget
  });
  const target = new Target();
  const events = [];
  target.logProjection = () => {};
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
  target.videoStreamSender = {
    async flush() { order.push('drain'); await blocked; },
    async finish() {}
  };
  target.videoWriteQueue = blocked;
  await target.stop(true);
  assert.deepEqual(order, ['close', 'drain']);
  assert.equal(target.videoDataSocket, undefined);
  assert.equal(target.videoStreamSender, undefined);
  assert.equal(target.recorded, false);
});

test('embedded app and map hit rectangles use the actual window density, not the requested virtual density', () => {
  const Target = loadMethods('pages/ProjectionDashboard.ets', 'ProjectionDashboard', [
    'handleAppSurfaceChange', 'handleMapSurfaceChange'
  ]);
  const target = new Target();
  target.getUIContext = () => ({ vp2px: value => value * 3, px2vp: value => value / 3 });
  const area = {
    globalPosition: { x: 70, y: 8 }, width: 300, height: 200
  };
  let app;
  let map;
  target.onAppSurfaceChange = surface => { app = JSON.parse(JSON.stringify(surface)); };
  target.onMapSurfaceChange = surface => { map = JSON.parse(JSON.stringify(surface)); };
  target.handleAppSurfaceChange('app', area, true);
  target.handleMapSurfaceChange('map', area, true);
  assert.deepEqual(app, { surfaceId: 'app', left: 210, top: 24, width: 900, height: 600 });
  assert.deepEqual(map, { ...app, surfaceId: 'map' });
  assert.ok(120 < app.left, 'a Dock touch must stay outside the embedded app');
});

test('CarPlay tap hit testing tolerates small finger drift by targeting the contact midpoint', () => {
  const Target = loadMethods('pages/ProjectionDashboard.ets', 'ProjectionDashboard', [
    'touchHandler', 'canvasPixelToContentPoint', 'screenToContentPoint'
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
  const routerSource = fs.readFileSync(path.join(sourceRoot, 'pages/ProjectionTouchRouter.ets'), 'utf8');
  assert.match(routerSource, /area\.group === 'dock'/);
  assert.match(routerSource, /area\.group === 'grid' && dashboardView !== 'apps'/);
  const Target = loadMethods('pages/ProjectionDashboard.ets', 'ProjectionDashboard', [
    'touchHandler', 'screenToContentPoint', 'canvasPixelToContentPoint'
  ], {
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
  const { ProjectionMediaCoordinator } = loadEts('pages/ProjectionMediaCoordinator.ets', {
    '@ohos.abilityAccessCtrl': {},
    '@ohos.app.ability.common': {},
    '../session/MediaSessionBridge': {
      EMPTY_PROJECTION_MEDIA: { title: '', artist: '', lyric: '', positionMs: 0, durationMs: 0,
        isPlaying: false, commands: [], queue: [], message: '' }
    },
    './ProjectionAppCatalog': { includeMediaSessionApp: apps => apps }
  });
  const commands = [];
  let state = { commands: ['play'], isPlaying: false };
  const target = new ProjectionMediaCoordinator({
    getSnapshot: () => state,
    onSnapshot: snapshot => { state = snapshot; },
    getApps: () => [],
    onAppsChanged: () => {},
    onActionMessage: () => {},
    onLog: () => {},
    getContext: () => ({})
  });
  target.bridge = {
    async send(command) { commands.push(command); },
    async refresh() { return state; }
  };
  await target.send('playNext');
  await target.send('play');
  assert.deepEqual(commands, ['play']);
});

test('split dashboard has independent navigation and app surfaces', () => {
  const source = fs.readFileSync(path.join(sourceRoot, 'pages/ProjectionDashboard.ets'), 'utf8');
  const contentSource = fs.readFileSync(path.join(sourceRoot, 'pages/ProjectionDashboardContent.ets'), 'utf8');
  const shellSource = fs.readFileSync(path.join(sourceRoot, 'pages/ProjectionDashboardShell.ets'), 'utf8');
  assert.match(contentSource, /surfaceName: 'projectionSplitMapSurface'/);
  assert.match(contentSource, /surfaceName: 'projectionSplitMusicSurface'/);
  assert.doesNotMatch(contentSource, /Text\('导航 APP'\)|Text\('音乐 APP'\)/);
  assert.match(contentSource, /this\.dashboardView === 'split'/);
  assert.match(contentSource, /this\.hasActiveMusicApp\(\)/);
  assert.match(shellSource, /this\.DockPanel\(false\)/);
  assert.match(shellSource, /this\.DockPanel\(true\)/);
  assert.match(source, /showDashboardView/);
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
  const Target = loadMethods('pages/ProjectionDashboard.ets', 'ProjectionDashboard', [
    'scrollControllerAt', 'handleTouchReport', 'screenToContentPoint', 'canvasPixelToContentPoint'
  ], {
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

test('wireless network lease exposes only the selected network default gateway', async () => {
  let ipv6Only = false;
  const { WifiNetworkLease } = loadEts('network/WifiNetworkLease.ets', {
    '@ohos.net.connection': {
      NetBearType: { BEARER_WIFI: 1 },
      async getNetCapabilities() { return { bearerTypes: [1] }; },
      async getConnectionProperties() {
        return {
          interfaceName: 'wlan0',
          linkAddresses: [
            { address: { address: '10.36.232.67' } },
            { address: { address: 'fe80::2' } }
          ],
          routes: ipv6Only ? [
            { isDefaultRoute: true, hasGateway: true, gateway: { address: 'fe80::1' } }
          ] : [
            { isDefaultRoute: false, hasGateway: true, gateway: { address: '10.36.232.1' } },
            { isDefaultRoute: true, hasGateway: true, gateway: { address: '10.36.232.1' } },
            { isDefaultRoute: true, hasGateway: false, gateway: { address: 'fe80::1' } }
          ]
        };
      }
    }
  });
  const lease = new WifiNetworkLease();
  const addresses = await lease.getMatchingLocalAddresses({ netId: 3 }, '10.36.232.67');
  lease.localAddresses = addresses;
  assert.equal(lease.defaultGatewayAddress, '10.36.232.1');
  const ipv6OnlyLease = new WifiNetworkLease();
  ipv6Only = true;
  ipv6OnlyLease.localAddresses = await ipv6OnlyLease.getMatchingLocalAddresses({ netId: 3 }, '10.36.232.67');
  assert.equal(ipv6OnlyLease.defaultGatewayAddress, 'fe80::1%wlan0');
});