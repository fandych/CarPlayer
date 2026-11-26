const { assert, fs, path, vm, test, ts, sourceRoot, audioSenderFixture, loadEts, loadMethods,
  loadProjectionSettingsController, videoSenderFixture } = require('../ProjectionBehaviorSupport.cjs');

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
  const bindingsSource = fs.readFileSync(
    path.join(sourceRoot, 'pages/ProjectionDashboardShellBindings.ets'), 'utf8'
  );
  const dropdownSource = fs.readFileSync(path.join(sourceRoot, 'pages/ProjectionSettingsDropdown.ets'), 'utf8');
  const connectionSource = fs.readFileSync(
    path.join(sourceRoot, 'pages/ProjectionConnectionSettingsPane.ets'), 'utf8'
  );
  assert.match(shellSource, /onDropdownToggle: \(key: string\)/);
  assert.match(shellSource, /onDropdownSelect: \(key: string, index: number\)/);
  assert.match(connectionSource, /dropdownKey: 'encoderFps'/);
  assert.match(connectionSource, /dropdownKey: 'captureFps'/);
  assert.match(bindingsSource, /onDropdownSelect:/);
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
  const source = fs.readFileSync(path.join(sourceRoot, 'pages/ProjectionHomeAppDisplay.ets'), 'utf8');
  assert.doesNotMatch(source, /setLaunchMessage\(`[^`]*请求已受理/);
  assert.match(source, /this\.callbacks\.logProjection\(\s*`应用启动请求已受理/);
  assert.match(source, /const message = `应用链接打开失败/);
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
  const docs = path.resolve(__dirname, '../../../../docs');
  const html = fs.readFileSync(path.join(docs, 'carplay.html'), 'utf8').toLowerCase();
  const styles = fs.readFileSync(path.join(docs, 'carplay.css'), 'utf8').toLowerCase();
  const scripts = fs.readFileSync(path.join(docs, 'carplay.js'), 'utf8').toLowerCase();
  const reference = `${html}\n${styles}\n${scripts}`;
  assert.match(html, /href="carplay\.css"/);
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
      assert.ok(reference.includes(color), `HTML prototype is missing ${color}`);
      assert.ok(asset.includes(color), `${id} wallpaper is missing ${color}`);
    }
  }
  for (const color of PROJECTION_ACCENTS) {
    assert.ok(reference.includes(color.toLowerCase()), `HTML prototype is missing accent ${color}`);
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
