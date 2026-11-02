@Component
export struct HomePage {
  @Prop status: string = 'closed';
  @Prop statusLabel: string = '';
  @Prop statusDescription: string = '';
  @Prop statusEyebrow: string = '';
  @Prop statusIcon: string = '';
  @Prop statusColor: string = '#79847D';
  @Prop ringColor: string = '#E7EBE7';
  @Prop projectionActive: boolean = false;
  onAction: () => void = (): void => {};
  onReturnToProjectionHome: () => void = (): void => {};

  build() {
    Column() {
      Row() {
        Column()
          .width(7)
          .height(7)
          .borderRadius(4)
          .backgroundColor(this.statusColor)
        Text(this.statusEyebrow)
          .fontSize(11)
          .fontWeight(FontWeight.Medium)
          .fontColor('#68736D')
      }
      .height(28)
      .padding({ left: 12, right: 12 })
      .borderRadius(14)
      .backgroundColor('#EAEEE9')
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)

      Stack({ alignContent: Alignment.Center }) {
        Column()
          .width(258)
          .height(258)
          .borderRadius(129)
          .backgroundColor(this.ringColor)
        Column()
          .width(218)
          .height(218)
          .borderRadius(109)
          .backgroundColor('#F8FAF7')
          .border({ width: 1, color: this.statusColor })
        Column({ space: 9 }) {
          Text(this.statusIcon)
            .fontSize(48)
            .fontColor(this.statusColor)
            .fontWeight(FontWeight.Lighter)
          Text(this.status === 'closed' ? '开启 CarPlayer' :
            (this.status === 'connected' ? '断开连接' : '关闭 CarPlayer'))
            .fontSize(13)
            .fontColor('#66716B')
        }
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      }
      .width(270)
      .height(270)
      .onClick(() => this.onAction())
      .accessibilityText(this.statusLabel + '，' + this.statusDescription)

      Column({ space: 8 }) {
        Text(this.statusLabel)
          .fontSize(28)
          .fontWeight(FontWeight.Bold)
          .fontColor('#18221D')
        Text(this.statusDescription)
          .fontSize(14)
          .fontColor('#6B756F')
      }
      .width('100%')
      .alignItems(HorizontalAlign.Center)
      .margin({ top: 22 })
      if (this.projectionActive) {
        Button('返回车机首页')
          .margin({ top: 16 })
          .onClick(() => this.onReturnToProjectionHome())
      }
      Blank()
    }
    .width('100%')
    .layoutWeight(1)
    .padding({ left: 26, right: 26, top: 24, bottom: 20 })
    .alignItems(HorizontalAlign.Center)
    .justifyContent(FlexAlign.Start)
  }
}