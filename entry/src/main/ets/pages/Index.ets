import common from '@ohos.app.ability.common';
import { SessionController } from '../session/SessionController';
import { ProtocolLogger, ProtocolLogLevel } from '../session/ProtocolLogger';
import { diagnosticLogArchive } from '../session/DiagnosticLogArchive';
import { CarPlayerSettings, CarPlayerSettingsStore } from '../settings/CarPlayerSettingsStore';
import { MfiTrustPromptInfo } from '../iap2/MfiVerifier';
import { IndexStatusLabel, IndexStatusDescription, IndexStatusEyebrow, IndexStatusIcon,
  IndexStatusColor, IndexRingColor } from './IndexStatus';
import { IndexHost } from './IndexHost';
import { IndexRootView } from './IndexRootView';
import * as indexSessionActions from './IndexSessionActions';
import * as indexSessionEvents from './IndexSessionEvents';
import * as indexSettingsActions from './IndexSettingsActions';
import * as indexDiagnosticsActions from './IndexDiagnosticsActions';

@Entry
@Component
struct Index {
  @State status: string = 'closed';
  @State statusMessage: string = '';
  @State page: string = 'home';
  @State showMenu: boolean = false;
  @State showWelcome: boolean = false;
  @State acceptedTerms: boolean = false;
  @State documentPage: string = '';
  @State settingsReady: boolean = false;
  @State settingsError: string = '';
  @State isSessionActive: boolean = false;
  @State isStarting: boolean = false;
  @State isStopping: boolean = false;
  @State skipMfiChallengeVerification: boolean = false;
  @State wifiJoinInProgress: boolean = false;
  @State deviceName: string = 'Harmony CarPlayer';
  @State bluetoothAddress: string = '';
  @State deviceUuid: string = '';
  @State trustedMfiFingerprints: string[] = [];
  @State logs: string[] = [];
  @State projectionDisplayId: number = -1;
  @State connectionDuration: string = '00:00';
  connectionStartedAt: number = 0;
  connectionTimer: number = -1;
  controller?: SessionController;
  readonly settingsStore: CarPlayerSettingsStore = new CarPlayerSettingsStore();
  protocolLogger?: ProtocolLogger;
  pendingUiLogLines: string[] = [];
  uiLogFlushTimer: number = -1;
  logSessionId: string = '';
  connectionAttempt: number = 0;
  lastConnectionSummary: string = '';

  aboutToAppear(): void {
    this.logSessionId = this.createLogSessionId();
    this.protocolLogger = new ProtocolLogger((line: string): void => this.addLog(line));
    this.protocolLogger.setContext({ sessionId: this.logSessionId, attempt: this.connectionAttempt });
    this.flushPendingUiLogLines();
    this.logs = diagnosticLogArchive.readRecentLines();
    this.logProtocol('session', 'CarPlayer 手机端初始化');
    void this.loadSettings();
  }

  build() {
    Stack() {
      IndexRootView({
      status: this.status,
      statusLabel: IndexStatusLabel(this.status),
      statusDescription: IndexStatusDescription(this.status),
      statusEyebrow: IndexStatusEyebrow(this.status),
      statusIcon: IndexStatusIcon(this.status),
      statusColor: IndexStatusColor(this.status),
      ringColor: IndexRingColor(this.status),
      connectionDuration: this.connectionDuration,
      page: this.page,
      showMenu: this.showMenu,
      showWelcome: this.showWelcome,
      acceptedTerms: this.acceptedTerms,
      documentPage: this.documentPage,
      settingsReady: this.settingsReady,
      settingsError: this.settingsError,
      isSessionActive: this.isSessionActive,
      deviceName: this.deviceName,
      bluetoothAddress: this.bluetoothAddress,
      skipMfiChallengeVerification: this.skipMfiChallengeVerification,
      trustedMfiFingerprints: this.trustedMfiFingerprints,
      logs: this.logs,
      statusMessage: this.statusMessage,
      logSessionId: this.logSessionId,
      connectionAttempt: this.connectionAttempt,
      onMainAction: (): void => this.onMainAction(),
      onMenuToggle: (): void => { this.showMenu = !this.showMenu; },
      onMenuDismiss: (): void => { this.showMenu = false; },
      onNavigate: (destination: string): void => {
        if (destination === 'logs') {
          this.flushPendingUiLogLines();
          const restoredLogs = diagnosticLogArchive.readRecentLines();
          if (restoredLogs.length > 0) {
            this.logs = restoredLogs;
          }
        }
        this.page = destination;
        this.showMenu = false;
      },
      onExport: (): void => { this.showMenu = false; void this.exportLogs(); },
      onClear: (): void => { this.showMenu = false; void this.clearLogs(); },
      onToggleTerms: (): void => { this.acceptedTerms = !this.acceptedTerms; },
      onOpenDocument: (page: string): void => { this.documentPage = page; },
      onAccept: (): void => { void this.acceptAgreement(); },
      onDocumentBack: (): void => { this.documentPage = ''; },
      onNavigateHome: (): void => this.navigateHome(),
      onDeviceNameChange: (value: string): void => { this.deviceName = value; },
      onBluetoothAddressChange: (value: string): void => { this.bluetoothAddress = value.trim(); },
      onSaveSettings: (): void => { void this.saveSettings(); },
      onSkipMfiChange: (enabled: boolean): void => { void this.setSkipMfiChallengeVerification(enabled); },
      onRevokeFingerprint: (fingerprint: string): void => { void this.revokeMfiFingerprint(fingerprint); },
      onRetrySettings: (): void => { void this.loadSettings(); }
      })
    }.width('100%').height('100%')
  }

  onMainAction(): void {
    if (this.status === 'closed') {
      void this.startSession();
    } else if (this.status === 'connected') {
      void this.disconnectAirPlay();
    } else {
      void this.stopSession();
    }
  }

  syncConnectionDuration(): void {
    indexSessionActions.syncConnectionDuration(this as IndexHost);
  }

  onBackPress(): boolean {
    if (this.documentPage.length > 0) {
      this.documentPage = '';
      return true;
    }
    if (this.showMenu) {
      this.showMenu = false;
      return true;
    }
    if (this.page !== 'home') {
      this.navigateHome();
      return true;
    }
    return false;
  }

  private navigateHome(): void {
    this.page = 'home';
  }

  async loadSettings(): Promise<void> {
    return indexSettingsActions.loadSettings(this as IndexHost);
  }

  getAppContext(): common.UIAbilityContext {
    const context = this.getUIContext().getHostContext();
    if (!context) {
      throw new Error('无法获取应用上下文');
    }
    return context as common.UIAbilityContext;
  }

  collectSettings(agreementAccepted: boolean = this.acceptedTerms): CarPlayerSettings {
    return indexSettingsActions.collectSettings(this as IndexHost, agreementAccepted);
  }

  async persistSettings(agreementAccepted: boolean = this.acceptedTerms): Promise<void> {
    return indexSettingsActions.persistSettings(this as IndexHost, agreementAccepted);
  }

  async acceptAgreement(): Promise<void> {
    return indexSettingsActions.acceptAgreement(this as IndexHost);
  }

  async saveSettings(): Promise<void> {
    return indexSettingsActions.saveSettings(this as IndexHost);
  }

  async startProjectionAbility(displayId: number): Promise<void> {
    const uiAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
    await uiAbilityContext.startAbility(
      {
        deviceId: '',
        bundleName: 'com.fandy.carplayer',
        moduleName: 'entry',
        abilityName: 'ProjectionHomeAbility'
      },
      { displayId }
    );
  }

  async startSession(): Promise<void> {
    return indexSessionActions.startSession(this as IndexHost);
  }

  ensureController(): SessionController {
    return indexSessionActions.ensureController(this as IndexHost);
  }

  async pauseActiveMediaOnProjectionStop(): Promise<void> {
    return indexSessionEvents.pauseActiveMediaOnProjectionStop(this as IndexHost);
  }

  async disconnectAirPlay(): Promise<void> {
    return indexSessionActions.disconnectAirPlay(this as IndexHost);
  }

  async retryAirPlay(): Promise<void> {
    return indexSessionActions.retryAirPlay(this as IndexHost);
  }

  async joinVehicleWifi(): Promise<void> {
    return indexSessionActions.joinVehicleWifi(this as IndexHost);
  }

  async stopSession(): Promise<void> {
    return indexSessionActions.stopSession(this as IndexHost);
  }

  applyProtocolStatus(message: string): void {
    indexSessionEvents.applyProtocolStatus(this as IndexHost, message);
  }

  logConnectionSummary(message: string): void {
    indexSessionEvents.logConnectionSummary(this as IndexHost, message);
  }

  async confirmMfiTrust(info: MfiTrustPromptInfo): Promise<boolean> {
    return indexSessionEvents.confirmMfiTrust(this as IndexHost, info);
  }

  async persistMfiFingerprint(fingerprint: string): Promise<void> {
    return indexSettingsActions.persistMfiFingerprint(this as IndexHost, fingerprint);
  }

  async revokeMfiFingerprint(fingerprint: string): Promise<void> {
    return indexSettingsActions.revokeMfiFingerprint(this as IndexHost, fingerprint);
  }

  async setSkipMfiChallengeVerification(enabled: boolean): Promise<void> {
    return indexSettingsActions.setSkipMfiChallengeVerification(this as IndexHost, enabled);
  }

  addLog(line: string): void {
    indexDiagnosticsActions.addLog(this as IndexHost, line);
  }

  flushPendingUiLogLines(): void {
    indexDiagnosticsActions.flushPendingUiLogLines(this as IndexHost);
  }

  async clearLogs(): Promise<void> {
    return indexDiagnosticsActions.clearLogs(this as IndexHost);
  }

  async exportLogs(): Promise<void> {
    return indexDiagnosticsActions.exportLogs(this as IndexHost);
  }

  logProtocol(stage: string, message: string, level: ProtocolLogLevel = 'INFO'): void {
    indexDiagnosticsActions.logProtocol(this as IndexHost, stage, message, level);
  }

  createLogSessionId(): string {
    return indexDiagnosticsActions.createLogSessionId(this as IndexHost);
  }

  resolveProtocolLogLevel(message: string, requested: ProtocolLogLevel): ProtocolLogLevel {
    return indexDiagnosticsActions.resolveProtocolLogLevel(this as IndexHost, message, requested);
  }

  protocolStage(message: string): string {
    return indexDiagnosticsActions.protocolStage(this as IndexHost, message);
  }

  showError(error: Error | Object): void {
    indexDiagnosticsActions.showError(this as IndexHost, error);
  }

  errorMessage(error: Error | Object): string {
    return indexDiagnosticsActions.errorMessage(this as IndexHost, error);
  }

  errorDetails(error: Error | Object): string {
    return indexDiagnosticsActions.errorDetails(this as IndexHost, error);
  }

  createDeviceUuid(): string {
    return indexSettingsActions.createDeviceUuid(this as IndexHost);
  }
}
