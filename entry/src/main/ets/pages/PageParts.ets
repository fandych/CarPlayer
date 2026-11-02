@Component
export struct SectionHeading {
  title: string = '';
  subtitle: string = '';

  build() {
    Column({ space: 6 }) {
      Text(this.title)
        .fontSize(25)
        .fontWeight(FontWeight.Bold)
        .fontColor('#18221D')
      Text(this.subtitle)
        .fontSize(13)
        .fontColor('#77817B')
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
        .fontColor('#243129')
      Text(this.body)
        .fontSize(13)
        .fontColor('#6B756F')
        .lineHeight(20)
    }
    .width('100%')
    .padding(16)
    .borderRadius(14)
    .backgroundColor('#FFFFFF')
  }
}