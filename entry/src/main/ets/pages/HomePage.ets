@Component
export struct HomePage {
  @Prop status: string = 'closed';
  @Prop statusLabel: string = '';
  @Prop statusDescription: string = '';
  @Prop statusEyebrow: string = '';
  @Prop statusIcon: string = '';
  @Prop statusColor: string = '#79847D';
  @Prop ringColor: string = '#E7EBE7';
  @Prop connectionDuration: string = '00:00';
  onAction: () => void = (): void => {};

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column() {
        Row({ space: 10 }) {
          Column()
            .width(10)
            .height(10)
            .borderRadius(5)
            .backgroundColor(this.statusColor)
            .shadow({ radius: this.status === 'connected' ? 8 : 0, color: this.statusColor,
              offsetX: 0, offsetY: 0 })
          Text(this.statusLabel)
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor('#FFFFFF')
        }
        .height(30)
        .margin({ top: 46 })
        .alignItems(VerticalAlign.Center)

        if (this.statusDescription.length > 0) {
          Text(this.statusDescription)
            .fontSize(14)
            .fontColor('#FFFFFFA6')
            .margin({ top: 8 })
        }

        Stack({ alignContent: Alignment.Center }) {
          Column()
            .width(260)
            .height(260)
            .borderRadius(130)
            .border({ width: 2, color: this.status === 'waiting' ? '#0A84FFAA' : '#FFFFFF40' })
            .scale({
              x: this.status === 'waiting' ? 1.08 : 1,
              y: this.status === 'waiting' ? 1.08 : 1
            })
            .animation({ duration: 700, curve: Curve.EaseOut })
          Column()
            .width(232)
            .height(232)
            .borderRadius(116)
            .border({ width: 1, color: this.status === 'connected' ? '#32D74B66' : '#FFFFFF26' })
          Button({ type: ButtonType.Circle }) {
            Stack({ alignContent: Alignment.Center }) {
              Column()
                .width(210)
                .height(210)
                .borderRadius(105)
                .backgroundColor(this.statusColor)
                .border({ width: 1, color: '#FFFFFF66' })
                .shadow({ radius: 32, color: this.statusColor, offsetX: 0, offsetY: 18 })
              Column({ space: 12 }) {
                if (this.status === 'connecting' || this.status === 'waiting') {
                  LoadingProgress()
                    .width(54)
                    .height(54)
                    .color('#FFFFFF')
                } else {
                  Text(this.statusIcon)
                    .fontSize(58)
                    .fontColor('#FFFFFF')
                    .fontWeight(FontWeight.Lighter)
                }
                Text(this.status === 'closed' ? '开启' :
                  (this.status === 'connected' ? '断开连接' : '关闭'))
                  .fontSize(19)
                  .fontWeight(FontWeight.Bold)
                  .fontColor('#FFFFFF')
              }
              .justifyContent(FlexAlign.Center)
              .alignItems(HorizontalAlign.Center)
            }
            .width(210)
            .height(210)
          }
          .width(210)
          .height(210)
          .padding(0)
          .backgroundColor(Color.Transparent)
          .onClick(() => this.onAction())
          .accessibilityText(this.status === 'closed' ? '开启 CarPlayer' :
            (this.status === 'connected' ? '断开连接' : '关闭 CarPlayer'))
        }
        .width(270)
        .height(270)
        .margin({ top: 62 })

        if (this.statusEyebrow.length > 0) {
          Text(this.statusEyebrow)
            .fontSize(13)
            .fontColor('#FFFFFF80')
            .textAlign(TextAlign.Center)
            .lineHeight(20)
            .padding({ left: 38, right: 38 })
            .margin({ top: 40 })
        }

        Blank().layoutWeight(1)

        if (this.status === 'connected') {
          Column() {
            Row() {
              Text('车辆').fontSize(14).fontColor('#FFFFFF9C')
              Blank()
              Text('无线 CarPlay').fontSize(14).fontColor('#FFFFFF')
            }
            .width('100%')
            .height(48)
            Row() {
              Text('连接时长').fontSize(14).fontColor('#FFFFFF9C')
              Blank()
              Text(this.connectionDuration).fontSize(14).fontColor('#FFFFFF')
            }
            .width('100%')
            .height(48)
            .border({ width: { top: 1 }, color: '#FFFFFF1F' })
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 4, bottom: 4 })
          .borderRadius(24)
          .backgroundColor('#6B282832')
          .border({ width: 1, color: '#FFFFFF30' })
          .shadow({ radius: 24, color: '#50000000', offsetX: 0, offsetY: 10 })
          .margin({ left: 20, right: 20, bottom: 26 })
        }
      }
      .width('100%')
      .height('100%')
      .padding({ left: 20, right: 20, bottom: 10 })
      .alignItems(HorizontalAlign.Center)
    }
    .width('100%')
    .height('100%')
    .layoutWeight(1)
  }
}