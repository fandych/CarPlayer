import { InfoCard } from './PageParts';

@Component
export struct LogsPage {
  @Prop logs: string[] = [];

  build() {
    Scroll() {
      Column({ space: 18 }) {
        if (this.logs.length === 0) {
          InfoCard({
            title: '暂无会话日志',
            body: '启动监听后，RFCOMM、iAP2、MFi、Wi-Fi、mDNS 和 AirPlay 阶段会在此持续记录。'
          })
        } else {
          Text(this.logs.join('\n'))
            .width('100%')
            .fontSize(10)
            .fontColor('#34443A')
            .lineHeight(16)
            .padding(12)
            .borderRadius(8)
            .backgroundColor('#FFFFFF')
        }
      }
      .width('100%')
      .padding({ left: 22, right: 22, top: 24, bottom: 30 })
    }
    .width('100%')
    .layoutWeight(1)
    .scrollBar(BarState.Off)
  }
}