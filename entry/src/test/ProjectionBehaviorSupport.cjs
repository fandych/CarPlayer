const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { test } = require('node:test');
const sdk = process.env.DEVECO_SDK_HOME || 'C:/Program Files/Huawei/DevEco Studio/sdk';
const ts = require(path.join(sdk, 'default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
const sourceRoot = path.resolve(__dirname, '../main/ets');

const { createAudioSenderFixture } = require('./ProjectionBehaviorAudioSupport.cjs');

function audioSenderFixture() {
  return createAudioSenderFixture(loadEts);
}

const { createEtsLoader } = require('./ProjectionBehaviorLoaderSupport.cjs');
const loadEts = createEtsLoader({ assert, fs, path, vm, ts, sourceRoot });

function loadMethods(relativePath, className, names, globals = {}) {
  const sourceFiles = [{ path: relativePath, className }];
  const projectionDashboardControllers = className === 'ProjectionDashboard'
    ? loadProjectionDashboardControllers(globals)
    : undefined;
  if (projectionDashboardControllers) {
    sourceFiles.push(
      { path: 'pages/ProjectionDashboardAppController.ets', className: 'ProjectionDashboardAppController' },
      { path: 'pages/ProjectionDashboardMediaController.ets', className: 'ProjectionDashboardMediaController' },
      { path: 'pages/ProjectionDashboardPresentationController.ets',
        className: 'ProjectionDashboardPresentationController' },
      { path: 'pages/ProjectionDashboardTouchController.ets', className: 'ProjectionDashboardTouchController' }
    );
  }
  const indexActionModules = [
    'pages/IndexSessionActions.ets',
    'pages/IndexSessionEvents.ets',
    'pages/IndexSettingsActions.ets',
    'pages/IndexDiagnosticsActions.ets'
  ];
  if (className === 'Index') {
    for (const helperPath of indexActionModules) {
      sourceFiles.push({ path: helperPath });
    }
  }
  if (className === 'Iap2SenderSession') {
    sourceFiles.push({
      path: 'session/iap2/Iap2SenderSessionFlow.ets',
      className: 'Iap2SenderSessionFlow'
    }, {
      path: 'session/iap2/Iap2SenderSessionState.ets',
      className: 'Iap2SenderSessionState'
    }, {
      path: 'session/iap2/Iap2SenderSessionAuthenticationFlow.ets',
      className: 'Iap2SenderSessionAuthenticationFlow'
    }, {
      path: 'session/iap2/Iap2SenderSessionPostAuthenticationFlow.ets',
      className: 'Iap2SenderSessionPostAuthenticationFlow'
    }, {
      path: 'session/iap2/Iap2SenderSessionAnnouncements.ets',
      className: 'Iap2SenderSessionAnnouncements'
    }, {
      path: 'session/iap2/Iap2SenderSessionMfiMessages.ets',
      className: 'Iap2SenderSessionMfiMessages'
    }, {
      path: 'session/iap2/Iap2SenderSessionMessages.ets',
      className: 'Iap2SenderSessionMessages'
    }, {
      path: 'session/iap2/Iap2SenderSessionTransport.ets',
      className: 'Iap2SenderSessionTransport'
    });
  }
  if (className === 'SessionController') {
    sourceFiles.push(...[
      ['session/SessionControllerProjectionFlow.ets', 'SessionControllerProjectionFlow'],
      ['session/SessionControllerAirPlayControl.ets', 'SessionControllerAirPlayControl'],
      ['session/SessionControllerWifiFlow.ets', 'SessionControllerWifiFlow'],
      ['session/SessionControllerShutdown.ets', 'SessionControllerShutdown'],
      ['session/SessionControllerBluetoothLifecycle.ets', 'SessionControllerBluetoothLifecycle'],
      ['session/SessionControllerAirPlayReconnectFlow.ets', 'SessionControllerAirPlayReconnectFlow'],
      ['session/SessionControllerAirPlaySessionFlow.ets', 'SessionControllerAirPlaySessionFlow'],
      ['session/SessionControllerAirPlayPrerequisiteFlow.ets', 'SessionControllerAirPlayPrerequisiteFlow'],
      ['session/SessionControllerAirPlayDiscoveryFlow.ets', 'SessionControllerAirPlayDiscoveryFlow'],
      ['session/SessionControllerIap2Flow.ets', 'SessionControllerIap2Flow'],
      ['session/SessionControllerConnectionFlow.ets', 'SessionControllerConnectionFlow']
    ].map(([path, className]) => ({ path, className })));
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
    if (className === 'Index') {
      for (const sourceFile of parsedSources.slice(1)) {
        const declaration = sourceFile.parsed.statements.find(statement =>
          ts.isFunctionDeclaration(statement) && statement.name?.text === name);
        if (declaration) {
          const parameters = declaration.parameters.slice(1)
            .map(parameter => parameter.getText(sourceFile.parsed).replace(/\bhost\./g, 'this.'));
          const body = declaration.body.getText(sourceFile.parsed).replace(/\bhost\./g, 'this.');
          const prefix = declaration.modifiers?.some(modifier => modifier.kind === ts.SyntaxKind.AsyncKeyword)
            ? 'async '
            : '';
          return {
            member: {
              getText: () => `${prefix}${name}(${parameters.join(', ')}) ${body}`
            },
            parsed: sourceFile.parsed
          };
        }
      }
    }
    for (const sourceFile of parsedSources) {
      if (className === 'Index' && sourceFile !== parsedSources[0]) {
        continue;
      }
      const { parsed } = sourceFile;
      const declaration = parsed.statements.find(statement =>
        ts.isClassDeclaration(statement) && statement.name?.text === sourceFile.className);
      if (!declaration) {
        continue;
      }
      const member = declaration.members.find(candidate => candidate.name?.text === name &&
        !candidate.modifiers?.some(modifier => modifier.kind === ts.SyntaxKind.AbstractKeyword));
      if (member) {
        return { member, parsed, className: sourceFile.className };
      }
    }
    return undefined;
  });
  assert.ok(methods.every(Boolean), `Missing methods: ${names.filter((_, index) => !methods[index]).join(', ')}`);
  const helperMethods = className === 'Iap2SenderSession' && names.includes('receiveControlMessage')
    ? ['handleMfiAuthenticationMessage', 'parseWifi'].map(name => {
      for (const sourceFile of parsedSources) {
        const declaration = sourceFile.parsed.statements.find(statement =>
          ts.isClassDeclaration(statement) && statement.name?.text === sourceFile.className);
        const member = declaration?.members.find(candidate => candidate.name?.text === name);
        if (member) {
          return { member, parsed: sourceFile.parsed };
        }
      }
      return undefined;
    })
    : [];
  assert.ok(helperMethods.every(Boolean), `Missing helper methods: ${helperMethods.map(method =>
    method ? '' : 'receiveControlMessage dependency').filter(Boolean).join(', ')}`);
  const selectedMethods = [...methods, ...helperMethods];
  const constructor = className === 'ProjectionDashboard'
    ? `constructor() {
        this.touchRouter = new ProjectionTouchRouter();
        this.getStorage = key => AppStorage?.get(key);
        this.setStorage = (key, value) => AppStorage?.setOrCreate(key, value);
        this.appController = new DashboardAppController();
        this.mediaController = new DashboardMediaController();
        this.presentationController = new DashboardPresentationController();
        this.touchController = new DashboardTouchController();
        this.settingsController = new DashboardSettingsController();
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
  const dashboardControllerMethod = method => {
    const owner = method.className;
    if (!projectionDashboardControllers || !owner || owner === className) {
      return method.member.getText(method.parsed);
    }
    const member = method.member;
    const parameters = member.parameters;
    const stateFirst = ![
      'ProjectionDashboardPresentationController.wallpaperResource',
      'ProjectionDashboardPresentationController.colorWithAlpha',
      'ProjectionDashboardMediaController.formatMediaTime',
      'ProjectionDashboardTouchController.areaBounds'
    ].includes(`${owner}.${member.name.text}`);
    const actualParameters = stateFirst ? parameters.slice(1) : parameters;
    const declarations = actualParameters.map(parameter => parameter.getText(method.parsed));
    const args = actualParameters.map(parameter => parameter.name.getText(method.parsed));
    const controllerName = {
      ProjectionDashboardAppController: 'appController',
      ProjectionDashboardMediaController: 'mediaController',
      ProjectionDashboardPresentationController: 'presentationController',
      ProjectionDashboardTouchController: 'touchController'
    }[owner];
    let forwardedArgs = stateFirst ? ['this', ...args] : args;
    if (owner === 'ProjectionDashboardTouchController' && member.name.text === 'setDisplayBrightnessFromTouch') {
      forwardedArgs = ['this', 'this.settingsController', ...args];
    }
    const asyncPrefix = member.modifiers?.some(modifier => modifier.kind === ts.SyntaxKind.AsyncKeyword)
      ? 'async '
      : '';
    return `${asyncPrefix}${member.name.text}(${declarations.join(', ')}) { ` +
      `return this.${controllerName}.${member.name.text}(${forwardedArgs.join(', ')}); }`;
  };
  const javascript = ts.transpileModule(
    `class Target { ${constructor}\n${selectedMethods.map(dashboardControllerMethod).join('\n')} }`, {
    compilerOptions: { target: ts.ScriptTarget.ES2020 }
  }).outputText;
  const executionGlobals = { ...globals };
  if (className === 'ProjectionDashboard') {
    executionGlobals.ProjectionTouchRouter = loadEts('pages/ProjectionTouchRouter.ets').ProjectionTouchRouter;
    Object.assign(executionGlobals, projectionDashboardControllers);
  }
  return vm.runInNewContext(`${javascript}\nTarget`, executionGlobals);
}

function loadProjectionDashboardControllers(globals) {
  const settings = { ...loadEts('video/ProjectionSettings.ets'), ...globals };
  const appCatalog = loadEts('pages/ProjectionAppCatalog.ets');
  const dashboardCatalog = { ...appCatalog, ...globals };
  const discovery = loadEts('pages/ProjectionDashboardAppDiscovery.ets', {
    '@ohos.bundle.bundleManager': { canOpenLink: () => false },
    './ProjectionAppCatalog': dashboardCatalog
  });
  const settingsControllerModule = loadEts('pages/ProjectionDashboardSettingsController.ets', {
    '../video/ProjectionSettings': settings
  });
  const dashboardApp = loadEts('pages/ProjectionDashboardAppController.ets', {
    '@kit.PerformanceAnalysisKit': { hilog: globals.hilog || { warn() {}, error() {} } },
    '@ohos.promptAction': { showToast() {} },
    './ProjectionAppCatalog': dashboardCatalog,
    './ProjectionDashboardAppDiscovery': {
      ...discovery,
      discoverProjectionApps: globals.discoverProjectionApps || discovery.discoverProjectionApps
    }
  });
  const dashboardMedia = loadEts('pages/ProjectionDashboardMediaController.ets', {
    '@kit.PerformanceAnalysisKit': { hilog: globals.hilog || { error() {} } },
    '@ohos.batteryInfo': globals.batteryInfo || { batterySOC: 0 },
    '@ohos.telephony.radio': globals.radio || { getPrimarySlotId: async () => 0, getSignalInformation: async () => [] },
    './ProjectionMediaCoordinator': { ProjectionMediaCoordinator: class {} }
  });
  const dashboardPresentation = loadEts('pages/ProjectionDashboardPresentationController.ets', {
    '../video/ProjectionSettings': settings
  });
  const dashboardTouch = loadEts('pages/ProjectionDashboardTouchController.ets', {
    './ProjectionDashboardSettingsController': settingsControllerModule
  });
  return {
    DashboardAppController: dashboardApp.ProjectionDashboardAppController,
    DashboardMediaController: dashboardMedia.ProjectionDashboardMediaController,
    DashboardPresentationController: dashboardPresentation.ProjectionDashboardPresentationController,
    DashboardTouchController: dashboardTouch.ProjectionDashboardTouchController,
    DashboardSettingsController: settingsControllerModule.ProjectionDashboardSettingsController
  };
}

function loadProjectionSettingsController(overrides = {}) {
  const settings = loadEts('video/ProjectionSettings.ets');
  const { ProjectionDashboardSettingsController } = loadEts(
    'pages/ProjectionDashboardSettingsController.ets',
    { '../video/ProjectionSettings': { ...settings, ...overrides } }
  );
  return new ProjectionDashboardSettingsController();
}

const { createVideoSenderFixture } = require('./ProjectionBehaviorVideoSupport.cjs');

function videoSenderFixture(send, split = data => [data]) {
  return createVideoSenderFixture(loadEts, send, split);
}

module.exports = { assert, fs, path, vm, test, ts, sourceRoot, audioSenderFixture, loadEts, loadMethods,
  loadProjectionSettingsController, videoSenderFixture };
