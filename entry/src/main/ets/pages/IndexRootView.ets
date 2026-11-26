import { AboutPage } from './AboutPage';
import { HelpPage } from './HelpPage';
import { HomePage } from './HomePage';
import { LogsPage } from './LogsPage';
import { SettingsPage } from './SettingsPage';
import { IndexDocumentOverlay, IndexMenuOverlay, IndexWelcomeOverlay } from './IndexOverlays';

@Component
export struct IndexRootView {
  @Prop status: string = 'closed';
  @Prop statusLabel: string = '';
  @Prop statusDescription: string = '';
  @Prop statusEyebrow: string = '';
  @Prop statusIcon: string = '';
  @Prop statusColor: string = '';
  @Prop ringColor: string = '';
  @Prop connectionDuration: string = '00:00';
  @Prop page: string = 'home';
  @Prop showMenu: boolean = false;
  @Prop showWelcome: boolean = false;
  @Prop acceptedTerms: boolean = false;
  @Prop documentPage: string = '';
  @Prop settingsReady: boolean = false;
  @Prop settingsError: string = '';
  @Prop isSessionActive: boolean = false;
  @Prop deviceName: string = '';
  @Prop bluetoothAddress: string = '';
  @Prop skipMfiChallengeVerification: boolean = false;
  @Prop trustedMfiFingerprints: string[] = [];
  @Prop logs: string[] = [];
  @Prop statusMessage: string = '';
  @Prop logSessionId: string = '';
  @Prop connectionAttempt: number = 0;
  onMainAction: () => void = (): void => {};
  onMenuToggle: () => void = (): void => {};
  onMenuDismiss: () => void = (): void => {};
  onNavigate: (destination: string) => void = (_destination: string): void => {};
  onExport: () => void = (): void => {};
  onClear: () => void = (): void => {};
  onToggleTerms: () => void = (): void => {};
  onOpenDocument: (page: string) => void = (_page: string): void => {};
  onAccept: () => void = (): void => {};
  onDocumentBack: () => void = (): void => {};
  onNavigateHome: () => void = (): void => {};
  onDeviceNameChange: (value: string) => void = (_value: string): void => {};
  onBluetoothAddressChange: (value: string) => void = (_value: string): void => {};
  onSaveSettings: () => void = (): void => {};
  onSkipMfiChange: (enabled: boolean) => void = (_enabled: boolean): void => {};
  onRevokeFingerprint: (fingerprint: string) => void = (_fingerprint: string): void => {};
  onRetrySettings: () => void = (): void => {};

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
          statusLabel: this.statusLabel,
          statusDescription: this.statusDescription,
          statusEyebrow: this.statusEyebrow,
          statusIcon: this.statusIcon,
          statusColor: this.statusColor,
          ringColor: this.ringColor,
          connectionDuration: this.connectionDuration,
          onAction: (): void => this.onMainAction()
        })
      }
      .width('100%')
      .height('100%')
      .backgroundColor(Color.Transparent)

      if (this.page !== 'home') {
        this.PageSheet()
      }
      if (this.showMenu) {
        IndexMenuOverlay({
          logsPage: this.page === 'logs',
          onDismiss: (): void => this.onMenuDismiss(),
          onNavigate: (destination: string): void => this.onNavigate(destination),
          onExport: (): void => this.onExport(),
          onClear: (): void => this.onClear()
        })
      }
      if (this.showWelcome) {
        IndexWelcomeOverlay({
          acceptedTerms: this.acceptedTerms,
          onToggleTerms: (): void => this.onToggleTerms(),
          onOpenDocument: (page: string): void => this.onOpenDocument(page),
          onAccept: (): void => this.onAccept()
        })
      }
      if (this.documentPage !== '') {
        IndexDocumentOverlay({
          page: this.documentPage,
          onBack: (): void => this.onDocumentBack()
        })
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
  private Header() {
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
          .onClick((): void => this.onMenuToggle())
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
  private ActivePage() {
    if (this.page === 'help') {
      HelpPage()
    } else if (this.page === 'settings') {
      SettingsPage({
        isSessionActive: this.isSessionActive,
        deviceName: this.deviceName,
        bluetoothAddress: this.bluetoothAddress,
        skipMfiChallengeVerification: this.skipMfiChallengeVerification,
        trustedMfiFingerprints: this.trustedMfiFingerprints,
        onDeviceNameChange: (value: string): void => this.onDeviceNameChange(value),
        onBluetoothAddressChange: (value: string): void => this.onBluetoothAddressChange(value),
        onSave: (): void => this.onSaveSettings(),
        onSkipMfiChange: (enabled: boolean): void => this.onSkipMfiChange(enabled),
        onRevokeFingerprint: (fingerprint: string): void => this.onRevokeFingerprint(fingerprint)
      })
    } else if (this.page === 'logs') {
      LogsPage({
        logs: this.logs,
        statusMessage: this.statusMessage || this.statusLabel,
        connectionDuration: this.connectionDuration,
        sessionId: this.logSessionId,
        attempt: this.connectionAttempt
      })
    } else {
      AboutPage({
        onOpenSoftware: (): void => this.onOpenDocument('software'),
        onOpenTerms: (): void => this.onOpenDocument('terms')
      })
    }
  }

  @Builder
  private PageSheet() {
    Stack({ alignContent: Alignment.Bottom }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#66000000')
        .onClick((): void => this.onNavigateHome())
      Column() {
        Row() {
          Text(this.pageTitle())
            .fontSize(24)
            .fontWeight(FontWeight.Bold)
            .fontColor('#FFFFFF')
          Blank()
          if (this.page === 'logs') {
            Button('⋯')
              .width(42)
              .height(34)
              .fontSize(21)
              .fontColor('#FFFFFF')
              .backgroundColor('#FFFFFF20')
              .borderRadius(17)
              .margin({ right: 8 })
              .accessibilityText('日志操作')
              .onClick((): void => this.onMenuToggle())
          }
          Button({ type: ButtonType.Circle }) {
            SymbolGlyph($r('sys.symbol.xmark')).fontSize(16).fontColor(['#FFFFFF'])
          }
          .width(34)
          .height(34)
          .backgroundColor('#FFFFFF20')
          .accessibilityText('关闭')
          .onClick((): void => this.onNavigateHome())
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

  private pageTitle(): string {
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

  @Builder
  private LoadingLayer() {
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
  private SettingsErrorLayer() {
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
          .onClick((): void => this.onRetrySettings())
      }
      .width('84%')
      .padding(20)
      .borderRadius(16)
      .backgroundColor('#FFFFFF')
    }
    .width('100%')
    .height('100%')
  }
}
