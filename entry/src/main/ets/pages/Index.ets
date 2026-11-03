import common from '@ohos.app.ability.common';
import fileFs from '@ohos.file.fs';
import picker from '@ohos.file.picker';
import avSession from '@ohos.multimedia.avsession';
import promptAction from '@ohos.promptAction';
import { AirPlayMediaSessionInfo } from '../airplay/AirPlayMediaSession';
import { MfiTrustPromptInfo } from '../iap2/MfiVerifier';
import { AirPlayService } from '../network/AirPlayMdnsDiscovery';
import { SessionController, SessionEvents } from '../session/SessionController';
import { ProtocolLogger, ProtocolLogLevel } from '../session/ProtocolLogger';
import { MAX_CONNECTION_LOG_LINES } from '../session/ConnectionLogBuffer';
import { diagnosticLogArchive } from '../session/DiagnosticLogArchive';
import { formatLocalTimestamp } from '../session/LogTimestamp';
import { WifiCredentials } from '../session/Iap2SenderSession';
import { CarPlayerSettings, CarPlayerSettingsStore } from '../settings/CarPlayerSettingsStore';
import { AboutPage } from './AboutPage';
import { HelpPage } from './HelpPage';
import { HomePage } from './HomePage';
import { LogsPage } from './LogsPage';
import { SettingsPage } from './SettingsPage';

interface ApiErrorDetails {
  code?: number;
  message?: string;
}

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
  private connectionStartedAt: number = 0;
  private connectionTimer: number = -1;
  private controller?: SessionController;
  private readonly settingsStore: CarPlayerSettingsStore = new CarPlayerSettingsStore();
  private protocolLogger?: ProtocolLogger;
  private pendingUiLogLines: string[] = [];
  private uiLogFlushTimer: number = -1;

  aboutToAppear(): void {
    this.protocolLogger = new ProtocolLogger((line: string): void => this.addLog(line));
    this.flushPendingUiLogLines();
    this.logs = diagnosticLogArchive.readRecentLines();
    this.logProtocol('session', 'CarPlayer 手机端初始化');
    void this.loadSettings();
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      if (this.status === 'connected') {
        Image($r('app.media.phone_background_connected'))
          .width('100%').height('100%').objectFit(ImageFit.Cover)
      } else if (this.status === 'waiting' || this.status === 'connecting') {
        Image($r('app.media.phone_background_waiting'))
          .width('100%').height('100%').objectFit(ImageFit.Cover)
      } else {
        Image($r('app.media.phone_background_off'))
          .width('100%').height('100%').objectFit(ImageFit.Cover)
      }
      Column() {
        this.Header()
        HomePage({
          status: this.status,
          statusLabel: this.statusLabel(),
          statusDescription: this.statusDescription(),
          statusEyebrow: this.statusEyebrow(),
          statusIcon: this.statusIcon(),
          statusColor: this.statusColor(),
          ringColor: this.ringColor(),
          connectionDuration: this.connectionDuration,
          onAction: (): void => this.onMainAction()
        })
      }
      .width('100%')
      .height('100%')
      .backgroundColor(Color.Transparent)

      if (this.showMenu && this.page !== 'logs') {
        this.MenuLayer()
      }
      if (this.showMenu && this.page === 'logs') {
        this.LogMenuLayer()
      }
      if (this.page !== 'home') {
        this.PageSheet()
      }
      if (this.showWelcome) {
        this.WelcomeLayer()
      }
      if (this.documentPage !== '') {
        this.DocumentLayer()
      }
      if (!this.settingsReady) {
        this.LoadingLayer()
      }
      if (this.settingsReady && this.settingsError.length > 0) {
        this.SettingsErrorLayer()
      }
    }
    .height('100%')
    .width('100%')
    .backgroundColor('#101014')
  }

  @Builder
  Header() {
    Stack({ alignContent: Alignment.Center }) {
      Row({ space: 8 }) {
        Image($r('app.media.ic_car_front')).width(22).height(22).objectFit(ImageFit.Contain)
        Text('CarPlayer')
          .fontSize(19)
          .fontWeight(FontWeight.Bold)
          .fontColor('#FFFFFF')
      }
      .alignItems(VerticalAlign.Center)

      Row({ space: 8 }) {
        Blank().width(42).height(42)
        Blank()
        Button('⋯')
          .width(42)
          .height(42)
          .fontSize(21)
          .fontColor('#FFFFFF')
          .backgroundColor('#66282832')
          .borderRadius(20)
          .border({ width: 1, color: '#FFFFFF30' })
          .onClick(() => {
            this.showMenu = !this.showMenu;
          })
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceBetween)
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .height(58)
    .padding({ left: 20, right: 20, top: 6 })
  }

  @Builder
  ActivePage() {
    if (this.page === 'help') {
      HelpPage()
    } else if (this.page === 'settings') {
      SettingsPage({
        isSessionActive: this.isSessionActive,
        deviceName: this.deviceName,
        bluetoothAddress: this.bluetoothAddress,
        skipMfiChallengeVerification: this.skipMfiChallengeVerification,
        trustedMfiFingerprints: this.trustedMfiFingerprints,
        onDeviceNameChange: (value: string): void => { this.deviceName = value; },
        onBluetoothAddressChange: (value: string): void => { this.bluetoothAddress = value.trim(); },
        onSave: (): void => { void this.saveSettings(); },
        onSkipMfiChange: (enabled: boolean): void => { void this.setSkipMfiChallengeVerification(enabled); },
        onRevokeFingerprint: (fingerprint: string): void => { void this.revokeMfiFingerprint(fingerprint); }
      })
    } else if (this.page === 'logs') {
      LogsPage({ logs: this.logs })
    } else {
      AboutPage({
        onOpenSoftware: (): void => { this.documentPage = 'software'; },
        onOpenTerms: (): void => { this.documentPage = 'terms'; }
      })
    }
  }

  @Builder
  PageSheet() {
    Stack({ alignContent: Alignment.Bottom }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#66000000')
        .onClick((): void => this.navigateHome())
      Column() {
        Row() {
          Text(this.pageTitle())
            .fontSize(24)
            .fontWeight(FontWeight.Bold)
            .fontColor('#FFFFFF')
          Blank()
          Button({ type: ButtonType.Circle }) {
            SymbolGlyph($r('sys.symbol.xmark')).fontSize(16).fontColor(['#FFFFFF'])
          }
          .width(34)
          .height(34)
          .backgroundColor('#FFFFFF20')
          .accessibilityText('关闭')
          .onClick((): void => this.navigateHome())
        }
        .width('100%')
        .height(46)
        .margin({ bottom: 8 })
        this.ActivePage()
      }
      .width('100%')
      .height('92%')
      .padding({ left: 20, right: 20, top: 20 })
      .backgroundColor('#F01E1E28')
      .border({ width: 1, color: '#FFFFFF30' })
      .borderRadius({ topLeft: 32, topRight: 32 })
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  MenuLayer() {
    Stack({ alignContent: Alignment.TopEnd }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#00000000')
        .onClick(() => {
          this.showMenu = false;
        })
      Column({ space: 2 }) {
        this.MenuItem('帮助', 'help')
        this.MenuItem('设置', 'settings')
        this.MenuItem('日志', 'logs')
        this.MenuItem('关于', 'about')
      }
      .width(142)
      .padding(4)
      .margin({ top: 58, right: 20 })
      .borderRadius(18)
      .backgroundColor('#D9282832')
      .border({ width: 1, color: '#FFFFFF30' })
      .shadow({ radius: 22, color: '#60000000', offsetX: 0, offsetY: 9 })
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  LogMenuLayer() {
    Stack({ alignContent: Alignment.TopEnd }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#00000000')
        .onClick(() => {
          this.showMenu = false;
        })
      Column({ space: 2 }) {
        Button('导出')
          .width('100%')
          .height(46)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor('#28352D')
          .backgroundColor('#FFFFFF')
          .onClick(() => {
            this.showMenu = false;
            void this.exportLogs();
          })
        Button('清空')
          .width('100%')
          .height(46)
          .fontSize(14)
          .fontColor('#A14D34')
          .backgroundColor('#FFFFFF')
          .onClick(() => {
            this.showMenu = false;
            void this.clearLogs();
          })
      }
      .width(116)
      .padding(4)
      .margin({ top: 58, right: 18 })
      .borderRadius(8)
      .backgroundColor('#FFFFFF')
      .shadow({ radius: 18, color: '#22000000', offsetX: 0, offsetY: 7 })
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  MenuItem(title: string, destination: string) {
    Button({ type: ButtonType.Normal }) {
      Row({ space: 12 }) {
        if (destination === 'settings') {
          SymbolGlyph($r('sys.symbol.gearshape')).fontSize(19).fontColor(['#FFFFFFB3'])
        } else if (destination === 'help') {
          Image($r('app.media.phone_help')).width(19).height(19).objectFit(ImageFit.Contain)
        } else if (destination === 'logs') {
          Image($r('app.media.phone_log')).width(19).height(19).objectFit(ImageFit.Contain)
        } else {
          Image($r('app.media.phone_info')).width(19).height(19).objectFit(ImageFit.Contain)
        }
        Text(title).fontSize(15).fontColor('#FFFFFF').layoutWeight(1)
      }
      .width('100%')
    }
      .width('100%')
      .height(46)
      .padding({ left: 12, right: 12 })
      .backgroundColor(Color.Transparent)
      .borderRadius(12)
      .onClick(() => {
        if (destination === 'logs') {
          this.flushPendingUiLogLines();
          const restoredLogs = diagnosticLogArchive.readRecentLines();
          if (restoredLogs.length > 0) {
            this.logs = restoredLogs;
          }
        }
        this.page = destination;
        this.showMenu = false;
      })
  }

  @Builder
  WelcomeLayer() {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#990D1712')
      Column({ space: 17 }) {
        Stack({ alignContent: Alignment.Center }) {
          Column()
            .width(58)
            .height(58)
            .borderRadius(29)
            .backgroundColor('#E8EEE8')
          Text('C')
            .fontSize(26)
            .fontWeight(FontWeight.Bold)
            .fontColor('#245641')
        }
        .width(58)
        .height(58)

        Column({ space: 7 }) {
          Text('欢迎使用 CarPlayer')
            .fontSize(21)
            .fontWeight(FontWeight.Bold)
            .fontColor('#18221D')
          Text('CarPlayer 用于管理手机与车机之间的 CarPlay 连接。使用前，请阅读软件说明和用户协议。')
            .fontSize(13)
            .fontColor('#68736D')
            .lineHeight(20)
            .textAlign(TextAlign.Center)
        }
        .width('100%')
        .alignItems(HorizontalAlign.Center)

        Row({ space: 10 }) {
          Button('软件说明  ›')
            .layoutWeight(1)
            .height(44)
            .fontSize(13)
            .fontColor('#244632')
            .backgroundColor('#EFF3EE')
            .borderRadius(11)
            .onClick(() => {
              this.documentPage = 'software';
            })
          Button('用户协议  ›')
            .layoutWeight(1)
            .height(44)
            .fontSize(13)
            .fontColor('#244632')
            .backgroundColor('#EFF3EE')
            .borderRadius(11)
            .onClick(() => {
              this.documentPage = 'terms';
            })
        }
        .width('100%')

        Row({ space: 9 }) {
          Button(this.acceptedTerms ? '✓' : '')
            .width(22)
            .height(22)
            .fontSize(14)
            .fontColor('#FFFFFF')
            .backgroundColor(this.acceptedTerms ? '#245641' : '#FFFFFF')
            .border({ width: 1, color: this.acceptedTerms ? '#245641' : '#B8C1BA' })
            .borderRadius(6)
            .onClick(() => {
              this.acceptedTerms = !this.acceptedTerms;
            })
          Text('我已阅读并同意')
            .fontSize(12)
            .fontColor('#59655E')
          Text('《用户协议》')
            .fontSize(12)
            .fontColor('#245641')
            .onClick(() => {
              this.documentPage = 'terms';
            })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

        Button('同意并继续')
          .width('100%')
          .height(50)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor('#FFFFFF')
          .backgroundColor(this.acceptedTerms ? '#245641' : '#B8C1BA')
          .borderRadius(13)
          .enabled(this.acceptedTerms)
          .onClick(() => {
            void this.acceptAgreement();
          })
        Button('退出')
          .width('100%')
          .height(38)
          .fontSize(13)
          .fontColor('#77817B')
          .backgroundColor('#00000000')
      }
      .width('88%')
      .padding({ left: 22, right: 22, top: 25, bottom: 16 })
      .borderRadius(22)
      .backgroundColor('#FFFFFF')
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  DocumentLayer() {
    Column() {
      Row() {
        Button('‹')
          .width(42)
          .height(42)
          .fontSize(34)
          .fontColor('#18221D')
          .backgroundColor('#FFFFFF')
          .borderRadius(21)
          .onClick(() => {
            this.documentPage = '';
          })
        Blank()
        Text(this.documentPage === 'terms' ? '用户协议' : '软件说明')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor('#18221D')
        Blank()
        Blank()
          .width(42)
      }
      .width('100%')
      .height(58)
      .padding({ left: 20, right: 20 })
      Scroll() {
        Column({ space: 14 }) {
          Text(this.documentPage === 'terms' ? '用户协议' : '关于 CarPlayer')
            .fontSize(25)
            .fontWeight(FontWeight.Bold)
            .fontColor('#18221D')
          Text(this.documentPage === 'terms'
            ? '本应用为实验性 CarPlay 发送端，未经 Apple 或车厂认证。协议协商、配对、投屏及音频均可能失败或中断。仅在停车时测试，驾驶员不得在行驶中操作手机。用户确认后，设备身份和 MFi 指纹可保存在本机；热点密码仅保留在当前会话，不写入协议日志。'
            : 'CarPlayer 使用手机作为无线 CarPlay 发送端。点击主界面按钮后会监听 RFCOMM/iAP2，并按车机能力尝试 MFi、热点确认、mDNS 邀请及 AirPlay 配对。兼容性仍需真实车机验证。')
            .fontSize(14)
            .fontColor('#68736D')
            .lineHeight(23)
        }
        .width('100%')
        .padding({ left: 24, right: 24, top: 24, bottom: 30 })
      }
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F4F6F2')
  }

  statusLabel(): string {
    return this.status === 'closed' ? '已关闭' : '已开启';
  }

  statusDescription(): string {
    if (this.status === 'waiting') {
      return '等待连接车机…';
    }
    if (this.status === 'connecting') {
      return '正在连接车机…';
    }
    if (this.status === 'connected') {
      return '已连接到车机';
    }
    return '';
  }

  statusEyebrow(): string {
    if (this.status === 'waiting') {
      return '请确认车机蓝牙 / Wi-Fi 已开启，靠近车辆后将自动连接';
    }
    if (this.status === 'connecting') {
      return '正在建立 CarPlay 会话，请稍候';
    }
    if (this.status === 'connected') {
      return '';
    }
    return '点击按钮开启 CarPlay 服务';
  }

  statusIcon(): string {
    if (this.status === 'waiting') {
      return '⌁';
    }
    if (this.status === 'connecting') {
      return '↗';
    }
    if (this.status === 'connected') {
      return '✓';
    }
    return '⏻';
  }

  statusColor(): string {
    if (this.status === 'waiting') {
      return '#0A84FF';
    }
    if (this.status === 'connecting') {
      return '#0A84FF';
    }
    if (this.status === 'connected') {
      return '#32D74B';
    }
    return '#8E8E93';
  }

  ringColor(): string {
    if (this.status === 'waiting') {
      return '#0A84FF55';
    }
    if (this.status === 'connecting') {
      return '#0A84FF55';
    }
    if (this.status === 'connected') {
      return '#32D74B55';
    }
    return '#FFFFFF25';
  }

  pageTitle(): string {
    if (this.page === 'help') {
      return '帮助';
    }
    if (this.page === 'settings') {
      return '设置';
    }
    if (this.page === 'logs') {
      return '日志';
    }
    return '关于';
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

  private syncConnectionDuration(): void {
    if (this.status === 'connected') {
      if (this.connectionTimer >= 0) {
        return;
      }
      this.connectionStartedAt = Date.now();
      this.connectionDuration = '00:00';
      this.connectionTimer = setInterval((): void => {
        const elapsed = Math.max(0, Math.floor((Date.now() - this.connectionStartedAt) / 1000));
        const minutes = `${Math.floor(elapsed / 60)}`.padStart(2, '0');
        const seconds = `${elapsed % 60}`.padStart(2, '0');
        this.connectionDuration = `${minutes}:${seconds}`;
      }, 1000);
      return;
    }
    if (this.connectionTimer >= 0) {
      clearInterval(this.connectionTimer);
      this.connectionTimer = -1;
    }
    this.connectionStartedAt = 0;
    this.connectionDuration = '00:00';
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

  @Builder
  LoadingLayer() {
    Stack({ alignContent: Alignment.Center }) {
      Column({ space: 12 }) {
        LoadingProgress()
          .width(32)
          .height(32)
        Text('正在读取 CarPlayer 设置…')
          .fontSize(14)
          .fontColor('#68736D')
      }
      .width('100%')
      .alignItems(HorizontalAlign.Center)
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  SettingsErrorLayer() {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#F4F6F2')
      Column({ space: 14 }) {
        Text('设置读取失败')
          .fontSize(21)
          .fontWeight(FontWeight.Bold)
          .fontColor('#18221D')
        Text(this.settingsError)
          .fontSize(13)
          .fontColor('#68736D')
        Button('重试')
          .width('100%')
          .height(46)
          .onClick(() => {
            void this.loadSettings();
          })
      }
      .width('84%')
      .padding(20)
      .borderRadius(16)
      .backgroundColor('#FFFFFF')
    }
    .width('100%')
    .height('100%')
  }

  private async loadSettings(): Promise<void> {
    this.settingsReady = false;
    this.settingsError = '';
    try {
      const settings = await this.settingsStore.load(this.getAppContext());
      this.acceptedTerms = settings.agreementAccepted;
      this.showWelcome = !settings.agreementAccepted;
      this.deviceName = settings.deviceName;
      this.bluetoothAddress = settings.bluetoothAddress;
      this.deviceUuid = settings.deviceUuid || this.createDeviceUuid();
      this.trustedMfiFingerprints = settings.trustedMfiFingerprints;
      this.skipMfiChallengeVerification = settings.skipMfiChallengeVerification;
      if (!settings.deviceUuid) {
        await this.persistSettings();
      }
      this.logProtocol('settings', '本地设置读取完成');
    } catch (error) {
      this.settingsError = this.errorMessage(error);
      this.logProtocol('settings', this.settingsError, 'ERROR');
    } finally {
      this.settingsReady = true;
    }
  }

  private getAppContext(): common.UIAbilityContext {
    const context = this.getUIContext().getHostContext();
    if (!context) {
      throw new Error('无法获取应用上下文');
    }
    return context as common.UIAbilityContext;
  }

  private collectSettings(agreementAccepted: boolean = this.acceptedTerms): CarPlayerSettings {
    return {
      agreementAccepted,
      deviceName: this.deviceName.trim() || 'Harmony CarPlayer',
      bluetoothAddress: this.bluetoothAddress.trim().toUpperCase(),
      deviceUuid: this.deviceUuid,
      trustedMfiFingerprints: this.trustedMfiFingerprints.slice(),
      skipMfiChallengeVerification: this.skipMfiChallengeVerification
    };
  }

  private async persistSettings(agreementAccepted: boolean = this.acceptedTerms): Promise<void> {
    await this.settingsStore.save(this.getAppContext(), this.collectSettings(agreementAccepted));
  }

  private async acceptAgreement(): Promise<void> {
    try {
      await this.persistSettings(true);
      this.acceptedTerms = true;
      this.showWelcome = false;
      this.logProtocol('ui', '用户已同意首次使用协议');
    } catch (error) {
      this.showError(error);
    }
  }

  private async saveSettings(): Promise<void> {
    try {
      if (this.isSessionActive) {
        throw new Error('请先停止监听，再修改发送端身份');
      }
      await this.persistSettings();
      this.logProtocol('settings', '发送端身份设置已保存');
      await promptAction.showToast({ message: '设置已保存' });
    } catch (error) {
      this.showError(error);
    }
  }

  private async startSession(): Promise<void> {
    if (this.isStarting || this.isSessionActive) {
      this.logProtocol('session', '忽略重复启动请求', 'WARN');
      return;
    }
    const address = this.bluetoothAddress.trim().toUpperCase();
    this.isStarting = true;
    this.isSessionActive = true;
    this.status = 'connecting';
    this.syncConnectionDuration();
    this.statusMessage = '正在请求蓝牙权限并启动 RFCOMM 监听';
    this.logProtocol(
      'bluetooth',
      `启动 RFCOMM/iAP2 监听，发送端 MAC ${address.length > 0 ? '已配置' : '未配置（可稍后补充）'}`
    );
    try {
      await this.ensureController().start();
    } catch (error) {
      this.isSessionActive = false;
      this.status = 'closed';
      this.syncConnectionDuration();
      this.showError(error);
    } finally {
      this.isStarting = false;
    }
  }

  private ensureController(): SessionController {
    if (this.controller) {
      return this.controller;
    }
    const events: SessionEvents = {
      onStatus: (status: string): void => this.applyProtocolStatus(status),
      onLog: (message: string): void => this.logProtocol(this.protocolStage(message), message),
      onWifiCredentials: (credentials: WifiCredentials): void => {
        this.logProtocol(
          'wifi',
          `收到车机热点配置：SSID=${credentials.ssid}，安全类型=${credentials.securityType}，密码已隐藏`
        );
        void this.joinVehicleWifi();
      },
      onAirPlayService: (service: AirPlayService): void => {
        this.logProtocol('mdns', `解析 AirPlay 服务：${service.name} ${service.host}:${service.port}`);
      },
      onAirPlayMediaSession: (info: AirPlayMediaSessionInfo): void => {
        this.applyProtocolStatus('AirPlay RTSP RECORD 已完成');
        this.logProtocol(
          'airplay',
          `RTSP RECORD 完成：videoPort=${info.videoDataPort}, audioPort=${info.audioSession?.dataPort ?? 0}`
        );
      },
      onProjectionReady: async (displayId: number, width: number, height: number): Promise<void> => {
        this.projectionDisplayId = displayId;
        this.logProtocol('projection', `虚拟屏已建立：id=${displayId}, size=${width}x${height}`);
        try {
          this.logProtocol(
            'projection',
            `请求启动投影页：bundle=com.fandy.carplayer, ability=ProjectionHomeAbility, displayId=${displayId}`
          );
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
          this.logProtocol('projection', `startAbility 返回成功：ProjectionHomeAbility, displayId=${displayId}`);
        } catch (error) {
          const message = this.errorMessage(error);
          this.logProtocol('projection', `投影首页启动失败：${message}`, 'ERROR');
          throw new Error(`CarPlay 虚拟屏已创建，但投影首页启动失败：${message}`);
        }
      },
      onProjectionStopping: (): Promise<void> => this.pauseActiveMediaOnProjectionStop(),
      onProjectionStopped: (): void => {
        this.projectionDisplayId = -1;
        AppStorage.setOrCreate('carplayProjectionActiveModeId', '');
      },
      requestMfiTrust: (info: MfiTrustPromptInfo): Promise<boolean> => this.confirmMfiTrust(info),
      persistMfiFingerprint: (fingerprint: string): Promise<void> => this.persistMfiFingerprint(fingerprint)
    };
    this.controller = new SessionController(
      this.getAppContext(),
      events,
      this.bluetoothAddress.trim().toUpperCase(),
      this.deviceName.trim() || 'Harmony CarPlayer',
      this.deviceUuid,
      false,
      false,
      this.trustedMfiFingerprints,
      this.skipMfiChallengeVerification
    );
    return this.controller;
  }

  private async pauseActiveMediaOnProjectionStop(): Promise<void> {
    const descriptors = await avSession.getAllSessionDescriptors();
    const activeSession = descriptors.find((descriptor: avSession.AVSessionDescriptor): boolean =>
      descriptor.isTopSession && descriptor.isActive && descriptor.type === 'audio') ??
      descriptors.find((descriptor: avSession.AVSessionDescriptor): boolean =>
        descriptor.isActive && descriptor.type === 'audio');
    if (!activeSession) {
      return;
    }

    const mediaController = await avSession.createController(activeSession.sessionId);
    try {
      const playbackState = await mediaController.getAVPlaybackState();
      if (playbackState.state !== avSession.PlaybackState.PLAYBACK_STATE_PLAY) {
        return;
      }
      const commands = await mediaController.getValidCommands();
      if (!commands.includes('pause')) {
        this.logProtocol('media',
          `离车时无法暂停音乐：${activeSession.elementName.bundleName} 未开放 pause 控制`, 'WARN');
        return;
      }
      await mediaController.sendControlCommand({ command: 'pause' });
      this.logProtocol('media',
        `离车时已暂停音乐：${activeSession.elementName.bundleName}/${activeSession.elementName.abilityName}`);
    } finally {
      try {
        await mediaController.destroy();
      } catch (error) {
        this.logProtocol('media',
          `释放离车媒体控制器失败：${error instanceof Error ? error.message : String(error)}`, 'WARN');
      }
    }
  }

  private async disconnectAirPlay(): Promise<void> {
    try {
      await this.controller?.disconnectAirPlay();
      this.status = this.isSessionActive ? 'waiting' : 'closed';
      this.syncConnectionDuration();
      this.logProtocol('airplay', '用户请求断开 AirPlay；iAP2 监听保持活动');
    } catch (error) {
      this.showError(error);
    }
  }

  private async retryAirPlay(): Promise<void> {
    try {
      this.status = 'connecting';
      this.syncConnectionDuration();
      this.statusMessage = '正在重试 AirPlay';
      await this.controller?.retryAirPlay();
    } catch (error) {
      this.showError(error);
    }
  }

  private async joinVehicleWifi(): Promise<void> {
    if (this.wifiJoinInProgress) {
      return;
    }
    this.wifiJoinInProgress = true;
    this.status = 'connecting';
    this.syncConnectionDuration();
    this.statusMessage = '正在自动连接车机 Wi-Fi';
    try {
      await this.controller?.joinVehicleWifi();
    } catch (error) {
      this.showError(error);
    } finally {
      this.wifiJoinInProgress = false;
    }
  }

  private async stopSession(): Promise<void> {
    if (this.isStopping) {
      return;
    }
    this.isStopping = true;
    this.isSessionActive = false;
    this.logProtocol('session', '用户请求停止 CarPlayer，会清理全部连接资源', 'WARN');
    try {
      await this.controller?.stop();
      this.status = 'closed';
      this.syncConnectionDuration();
      this.statusMessage = '监听已关闭';
    } catch (error) {
      this.showError(error);
    } finally {
      this.controller = undefined;
      this.wifiJoinInProgress = false;
      this.projectionDisplayId = -1;
      this.isStopping = false;
    }
  }

  private applyProtocolStatus(message: string): void {
    this.statusMessage = message;
    this.logProtocol(this.protocolStage(message), `状态：${message}`);
    if (message === '已停止' || message.startsWith('已停止，但')) {
      this.status = 'closed';
      this.isSessionActive = false;
    } else if (message.includes('实时投屏已启动') || message.includes('AirPlay 控制已连接') ||
      message.includes('RTSP RECORD 已完成')) {
      this.status = 'connected';
    } else if (/失败|错误|异常/.test(message)) {
      this.status = this.isSessionActive ? 'waiting' : 'closed';
    } else if (this.isSessionActive) {
      this.status = /配对|AirPlay|RTSP|连接中|自动连接|请求系统确认连接/.test(message)
        ? 'connecting'
        : 'waiting';
    }
    this.syncConnectionDuration();
  }

  private async confirmMfiTrust(info: MfiTrustPromptInfo): Promise<boolean> {
    this.logProtocol(
      'mfi',
      `系统 PKIX 未建立信任：fingerprint=${info.fingerprint}, subject=${info.subject}, ` +
        `issuer=${info.issuer}, reason=${info.pkixFailure}；等待用户明确确认`,
      'WARN'
    );
    try {
      this.logProtocol('mfi', '正在打开首次使用 MFi 证书信任确认框');
      const result = await promptAction.showDialog({
        title: '确认信任此 MFi 证书？',
        message: `仅固定当前叶证书 SHA-256 指纹，不会修改系统信任库。仍需每次验证 challenge 签名。\n\nSubject: ${info.subject}\nIssuer: ${info.issuer}\nSHA-256: ${info.fingerprint}\nPKIX: ${info.pkixFailure}`,
        buttons: [
          { text: '拒绝', color: '#68736D' },
          { text: '信任此指纹', color: '#A14D34' }
        ]
      });
      this.logProtocol(
        'mfi',
        `用户${result.index === 1 ? '同意' : '拒绝'}固定本次证书指纹`,
        result.index === 1 ? 'WARN' : 'INFO'
      );
      return result.index === 1;
    } catch (error) {
      this.logProtocol('mfi', `信任确认未完成，按拒绝处理：${this.errorDetails(error)}`, 'ERROR');
      return false;
    }
  }

  private async persistMfiFingerprint(fingerprint: string): Promise<void> {
    const normalized = fingerprint.toLowerCase();
    if (!/^[0-9a-f]{64}$/.test(normalized)) {
      throw new Error('MFi 指纹不是有效 SHA-256，拒绝保存');
    }
    if (this.trustedMfiFingerprints.includes(normalized)) {
      return;
    }
    const previous = this.trustedMfiFingerprints;
    this.trustedMfiFingerprints = [...previous, normalized];
    try {
      this.logProtocol('mfi', 'challenge 签名已通过，开始持久化 MFi 指纹');
      await this.persistSettings();
      this.logProtocol('mfi', 'challenge 签名验证成功后已保存 MFi 指纹');
    } catch (error) {
      this.trustedMfiFingerprints = previous;
      this.logProtocol('mfi', `保存 MFi 指纹失败，已恢复内存状态：${this.errorDetails(error)}`, 'ERROR');
      throw error instanceof Error ? error : new Error(String(error));
    }
  }

  private async revokeMfiFingerprint(fingerprint: string): Promise<void> {
    const previous = this.trustedMfiFingerprints;
    this.trustedMfiFingerprints = previous.filter((value: string) => value !== fingerprint);
    try {
      await this.persistSettings();
      this.logProtocol('mfi', '已撤销本地固定的 MFi 指纹', 'WARN');
    } catch (error) {
      this.trustedMfiFingerprints = previous;
      this.showError(error);
    }
  }

  private async setSkipMfiChallengeVerification(enabled: boolean): Promise<void> {
    const previous = this.skipMfiChallengeVerification;
    this.skipMfiChallengeVerification = enabled;
    try {
      await this.persistSettings();
      this.logProtocol(
        'mfi',
        enabled
          ? '诊断模式已启用：跳过 MFi challenge 验签；不会将跳过记录为验证通过'
          : '诊断模式已关闭：恢复 MFi challenge 签名验证',
        enabled ? 'WARN' : 'INFO'
      );
    } catch (error) {
      this.skipMfiChallengeVerification = previous;
      this.showError(error instanceof Error ? error : new Error(String(error)));
    }
  }

  private addLog(line: string): void {
    diagnosticLogArchive.append(line);
    this.pendingUiLogLines.push(line);
    if (this.uiLogFlushTimer < 0) {
      this.uiLogFlushTimer = setTimeout((): void => this.flushPendingUiLogLines(), 250);
    }
  }

  private flushPendingUiLogLines(): void {
    if (this.uiLogFlushTimer >= 0) {
      clearTimeout(this.uiLogFlushTimer);
      this.uiLogFlushTimer = -1;
    }
    if (this.pendingUiLogLines.length === 0) {
      return;
    }
    const newestFirst = this.pendingUiLogLines.reverse();
    this.pendingUiLogLines = [];
    this.logs = [...newestFirst, ...this.logs].slice(0, MAX_CONNECTION_LOG_LINES);
  }

  private async clearLogs(): Promise<void> {
    try {
      const result = await promptAction.showDialog({
        title: '清空日志？',
        message: '将删除本机最近 10 天的日志文件。此操作不可撤销。',
        buttons: [
          { text: '取消', color: '#68736D' },
          { text: '清空', color: '#A14D34' }
        ]
      });
      if (result.index !== 1) {
        return;
      }
      diagnosticLogArchive.clear();
      if (this.uiLogFlushTimer >= 0) {
        clearTimeout(this.uiLogFlushTimer);
        this.uiLogFlushTimer = -1;
      }
      this.pendingUiLogLines = [];
      this.logs = [];
    } catch (error) {
      this.showError(error instanceof Error ? error : new Error(String(error)));
    }
  }

  private async exportLogs(): Promise<void> {
    let openedFile: fileFs.File | undefined;
    try {
      const savedUris = await new picker.DocumentViewPicker(this.getAppContext()).save({
        newFileNames: [`CarPlayer-logs-${formatLocalTimestamp().replace(/[:.]/g, '-')}.log`]
      });
      const savedUri = savedUris[0];
      if (!savedUri) {
        return;
      }
      openedFile = await fileFs.open(
        savedUri,
        fileFs.OpenMode.WRITE_ONLY | fileFs.OpenMode.CREATE | fileFs.OpenMode.TRUNC
      );
      const contents = diagnosticLogArchive.readAllText() || this.logs.slice().reverse().join('\n');
      await fileFs.write(openedFile.fd, `${contents}\n`);
      await promptAction.showToast({ message: '最近 10 天日志已导出' });
    } catch (error) {
      this.showError(error instanceof Error ? error : new Error(String(error)));
    } finally {
      if (openedFile) {
        try {
          await fileFs.close(openedFile);
        } catch (error) {
          this.logProtocol('diagnostics', `关闭导出日志文件失败：${this.errorMessage(error)}`, 'ERROR');
        }
      }
    }
  }

  private logProtocol(stage: string, message: string, level: ProtocolLogLevel = 'INFO'): void {
    if (!this.protocolLogger) {
      this.protocolLogger = new ProtocolLogger((line: string): void => this.addLog(line));
    }
    this.protocolLogger.write(stage, message, level);
  }

  private protocolStage(message: string): string {
    if (/MFi|certificate|证书|challenge/i.test(message)) {
      return 'mfi';
    }
    if (/Bluetooth|RFCOMM|iAP2|0x[0-9a-f]{4}/i.test(message)) {
      return 'iap2';
    }
    if (/Wi-?Fi|热点|SSID/i.test(message)) {
      return 'wifi';
    }
    if (/mDNS|Bonjour|邀请/i.test(message)) {
      return 'mdns';
    }
    if (/AirPlay|RTSP|pair-|配对|RECORD/i.test(message)) {
      return 'airplay';
    }
    return 'session';
  }

  private showError(error: Error | Object): void {
    const message = this.errorMessage(error);
    this.statusMessage = message;
    this.logProtocol(this.protocolStage(message), message, 'ERROR');
    void promptAction.showToast({ message });
  }

  private errorMessage(error: Error | Object): string {
    if (error instanceof Error) {
      return error.message;
    }
    const details = error as ApiErrorDetails;
    const parts: string[] = [];
    if (details.code !== undefined) {
      parts.push(`code=${details.code}`);
    }
    if (details.message) {
      parts.push(details.message);
    }
    return parts.length > 0 ? parts.join(': ') : JSON.stringify(error) || String(error);
  }

  private errorDetails(error: Error | Object): string {
    if (error instanceof Error) {
      return error.stack ? `${error.message}\n${error.stack}` : error.message;
    }
    return this.errorMessage(error);
  }

  private createDeviceUuid(): string {
    const randomPart = Math.floor(Math.random() * 0xffffffff).toString(16).padStart(8, '0');
    return `HOS-${Date.now().toString(16)}-${randomPart}`;
  }
}