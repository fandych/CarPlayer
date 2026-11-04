import { ProjectionMediaCommand } from '../session/MediaSessionBridge';

@Component
export struct ProjectionMediaSidebar {
  @Prop title: string = '';
  @Prop lyric: string = '';
  @Prop positionMs: number = 0;
  @Prop durationMs: number = 0;
  @Prop isPlaying: boolean = false;
  @Prop commands: ProjectionMediaCommand[] = [];
  @Prop splitMusicRatio: number = 2;
  @Prop accent: string = '#0A84FF';
  @Prop primaryTextColor: string = '#FFFFFF';
  @Prop secondaryTextColor: string = '#9EFFFFFF';
  @Prop panelColor: string = '#1E1E26';
  @Prop cardStrokeColor: string = '#20FFFFFF';
  @Prop secondaryButtonColor: string = '#14FFFFFF';
  onOpenMediaApp: () => void = (): void => {};
  onSendMediaCommand: (command: ProjectionMediaCommand) => void = (_command: ProjectionMediaCommand): void => {};
  onTouchAreaChange: (key: string, area: Area, action: () => void) => void =
    (_key: string, _area: Area, _action: () => void): void => {};
  onBoundsChange: (area: Area) => void = (_area: Area): void => {};

  private progressPercent(): number {
    if (this.durationMs <= 0) {
      return 0;
    }
    return Math.max(0, Math.min(100, this.positionMs / this.durationMs * 100));
  }

  @Builder
  private MediaControl(command: ProjectionMediaCommand, label: string, symbol: Resource) {
    Button({ type: ButtonType.Normal }) {
      SymbolGlyph(symbol).fontSize(18).fontColor([
        command === 'play' || command === 'pause' ? '#FFFFFF' : this.primaryTextColor
      ])
    }
    .layoutWeight(1).height(46).borderRadius(14)
    .backgroundColor(command === 'play' || command === 'pause'
      ? `#48${this.accent.slice(1)}` : this.secondaryButtonColor)
    .enabled(this.commands.includes(command))
    .accessibilityText(label)
    .onClick((): void => this.onSendMediaCommand(command))
    .onAreaChange((_oldArea, newArea) => this.onTouchAreaChange(
      command === 'play' || command === 'pause' ? 'playPause' : command,
      newArea,
      (): void => this.onSendMediaCommand(command === 'play' || command === 'pause'
        ? (this.isPlaying ? 'pause' : 'play') : command)
    ))
  }

  build() {
    Column({ space: 10 }) {
      Column({ space: 8 }) {
        Column({ space: 3 }) {
          Text(this.title).fontSize(16).fontWeight(FontWeight.Bold).fontColor(this.primaryTextColor)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .width('100%').alignItems(HorizontalAlign.Start)
        .onClick((): void => this.onOpenMediaApp())
        .onAreaChange((_oldArea, newArea) => this.onTouchAreaChange(
          'open', newArea, (): void => this.onOpenMediaApp()))
        Text(this.lyric || '暂无歌词')
          .fontSize(12).fontColor(this.secondaryTextColor)
          .width('100%').layoutWeight(1)
          .textAlign(TextAlign.Start).maxLines(3)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Progress({ value: this.progressPercent(), total: 100 })
          .width('100%').height(4).color('#FFFFFF')
        Row({ space: 4 }) {
          this.MediaControl('playPrevious', '上一首', $r('sys.symbol.backward_end_fill'))
          this.MediaControl(this.isPlaying ? 'pause' : 'play', this.isPlaying ? '暂停' : '播放',
            this.isPlaying ? $r('sys.symbol.pause_fill') : $r('sys.symbol.play_fill'))
          this.MediaControl('playNext', '下一首', $r('sys.symbol.forward_end_fill'))
        }
        .width('100%')
      }
      .layoutWeight(1.25).width('100%').padding(16).borderRadius(24)
      .backgroundColor(this.panelColor)
      .border({ width: 1, color: this.cardStrokeColor })
      .clip(true)

      Stack({ alignContent: Alignment.TopStart }) {
        Image($r('app.media.projection_weather_card'))
          .width('100%').height('100%').objectFit(ImageFit.Cover)
        Column({ space: 10 }) {
          Text('上海').fontSize(14).fontWeight(FontWeight.Medium).fontColor('#FFFFFF')
            .width('100%').textAlign(TextAlign.Start)
          Row() {
            Column({ space: 6 }) {
              Text('24°').fontSize(42).fontWeight(FontWeight.Lighter).fontColor('#FFFFFF')
              Text('晴 · 27° / 18°').fontSize(12).fontColor('#D9FFFFFF')
            }
            .alignItems(HorizontalAlign.Start)
            Blank()
            Image($r('app.media.projection_weather_sun')).width(34).height(34).objectFit(ImageFit.Contain)
          }
          .width('100%').layoutWeight(1).alignItems(VerticalAlign.Center)
        }
        .width('100%').height('100%').padding(16)
      }
      .layoutWeight(1).width('100%').borderRadius(24)
      .border({ width: 1, color: this.cardStrokeColor })
      .clip(true)
    }
    .layoutWeight(this.splitMusicRatio).height('100%')
    .onAreaChange((_oldArea, newArea) => this.onBoundsChange(newArea))
  }
}
