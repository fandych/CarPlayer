@Component
export struct SectionHeading {
  title: string = '';
  subtitle: string = '';

  build() {
    Column({ space: 6 }) {
      Text(this.title)
        .fontSize(25)
        .fontWeight(FontWeight.Bold)
        .fontColor('#F5F5F7')
      Text(this.subtitle)
        .fontSize(13)
        .fontColor('#FFFFFF99')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .margin({ bottom: 4 })
  }
}

@Component
export struct InfoCard {
  title: string = '';
  body: string = '';

  build() {
    Column({ space: 7 }) {
      Text(this.title)
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor('#F5F5F7')
      Text(this.body)
        .fontSize(13)
        .fontColor('#FFFFFFA6')
        .lineHeight(20)
    }
    .width('100%')
    .padding(16)
    .borderRadius(18)
    .backgroundColor('#24FFFFFF')
    .border({ width: 1, color: '#FFFFFF26' })
  }
}