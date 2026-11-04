@Component
export struct IndexMenuOverlay {
  @Prop logsPage: boolean = false;
  onDismiss: () => void = (): void => {};
  onNavigate: (destination: string) => void = (_destination: string): void => {};
  onExport: () => void = (): void => {};
  onClear: () => void = (): void => {};

  @Builder
  private MenuItem(title: string, destination: string) {
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
    .onClick((): void => this.onNavigate(destination))
  }

  build() {
    Stack({ alignContent: Alignment.TopEnd }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#00000000')
        .onClick((): void => this.onDismiss())
      if (this.logsPage) {
        Column({ space: 2 }) {
          Button('导出')
            .width('100%')
            .height(46)
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor('#28352D')
            .backgroundColor('#FFFFFF')
            .onClick((): void => this.onExport())
          Button('清空')
            .width('100%')
            .height(46)
            .fontSize(14)
            .fontColor('#A14D34')
            .backgroundColor('#FFFFFF')
            .onClick((): void => this.onClear())
        }
        .width(116)
        .padding(4)
        .margin({ top: 58, right: 18 })
        .borderRadius(8)
        .backgroundColor('#FFFFFF')
        .shadow({ radius: 18, color: '#22000000', offsetX: 0, offsetY: 7 })
      } else {
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
    }
    .width('100%')
    .height('100%')
  }
}

@Component
export struct IndexWelcomeOverlay {
  @Prop acceptedTerms: boolean = false;
  onToggleTerms: () => void = (): void => {};
  onOpenDocument: (page: string) => void = (_page: string): void => {};
  onAccept: () => void = (): void => {};

  build() {
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
            .onClick((): void => this.onOpenDocument('software'))
          Button('用户协议  ›')
            .layoutWeight(1)
            .height(44)
            .fontSize(13)
            .fontColor('#244632')
            .backgroundColor('#EFF3EE')
            .borderRadius(11)
            .onClick((): void => this.onOpenDocument('terms'))
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
            .onClick((): void => this.onToggleTerms())
          Text('我已阅读并同意')
            .fontSize(12)
            .fontColor('#59655E')
          Text('《用户协议》')
            .fontSize(12)
            .fontColor('#245641')
            .onClick((): void => this.onOpenDocument('terms'))
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
          .onClick((): void => this.onAccept())
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
}

@Component
export struct IndexDocumentOverlay {
  @Prop page: string = '';
  onBack: () => void = (): void => {};

  build() {
    Column() {
      Row() {
        Button('‹')
          .width(42)
          .height(42)
          .fontSize(34)
          .fontColor('#18221D')
          .backgroundColor('#FFFFFF')
          .borderRadius(21)
          .onClick((): void => this.onBack())
        Blank()
        Text(this.page === 'terms' ? '用户协议' : '软件说明')
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
          Text(this.page === 'terms' ? '用户协议' : '关于 CarPlayer')
            .fontSize(25)
            .fontWeight(FontWeight.Bold)
            .fontColor('#18221D')
          Text(this.page === 'terms'
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
}
