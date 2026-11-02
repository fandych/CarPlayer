@Component
export struct AboutPage {
  @StorageProp('carplayMapApprovalNumber') mapApprovalNumber: string = '';
  onOpenSoftware: () => void = (): void => {};
  onOpenTerms: () => void = (): void => {};

  build() {
    Scroll() {
      Column({ space: 18 }) {
        Column({ space: 6 }) {
          Text('关于 CarPlayer')
            .fontSize(25)
            .fontWeight(FontWeight.Bold)
            .fontColor('#18221D')
          Text('HarmonyOS 无线 CarPlay 发送端')
            .fontSize(13)
            .fontColor('#77817B')
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        Column({ space: 14 }) {
          Text('CarPlayer')
            .fontSize(22)
            .fontWeight(FontWeight.Bold)
            .fontColor('#18221D')
          Text('实验性发送端实现。iAP2、MFi 和 AirPlay 会话仍需在真实车机上验证；虚拟屏需要设备系统授权。')
            .fontSize(14)
            .fontColor('#68736D')
            .lineHeight(22)
          Row() {
            Text('版本')
              .fontSize(14)
              .fontColor('#68736D')
            Blank()
            Text('1.0.0')
              .fontSize(14)
              .fontColor('#27332C')
          }
          .width('100%')
          if (this.mapApprovalNumber) {
            Text(`地图审图号：${this.mapApprovalNumber}`)
              .fontSize(12)
              .fontColor('#68736D')
          }
        }
        .width('100%')
        .padding(18)
        .borderRadius(16)
        .backgroundColor('#FFFFFF')
        Button('软件说明')
          .width('100%')
          .height(50)
          .fontSize(15)
          .fontColor('#20372D')
          .backgroundColor('#E8EEE8')
          .borderRadius(12)
          .onClick(() => this.onOpenSoftware())
        Button('用户协议')
          .width('100%')
          .height(50)
          .fontSize(15)
          .fontColor('#20372D')
          .backgroundColor('#E8EEE8')
          .borderRadius(12)
          .onClick(() => this.onOpenTerms())
      }
      .width('100%')
      .padding({ left: 22, right: 22, top: 24, bottom: 30 })
    }
    .width('100%')
    .layoutWeight(1)
    .scrollBar(BarState.Off)
  }
}