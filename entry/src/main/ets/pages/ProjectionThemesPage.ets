import { PROJECTION_ACCENTS, PROJECTION_THEMES, ProjectionTheme } from '../video/ProjectionSettings';

@Component
export struct ProjectionThemesPage {
  @Prop theme: string = 'aurora';
  @Prop accent: string = '#0A84FF';
  @Prop primaryTextColor: string = '#FFFFFF';
  @Prop secondaryTextColor: string = '#9EFFFFFF';
  @Prop mapBackgroundColor: string = '#1D2230';
  @Prop panelColor: string = '#1E1E26';
  @Prop strokeColor: string = '#38FFFFFF';
  wallpaperResource: (themeId: string) => Resource = (_themeId: string): Resource =>
    $r('app.media.projection_aurora');
  onThemeChange: (themeId: string) => void = (_themeId: string): void => {};
  onAccentChange: (color: string) => void = (_color: string): void => {};
  onTouchAreaChange: (key: string, area: Area, action: () => void) => void =
    (_key: string, _area: Area, _action: () => void): void => {};
  onBoundsChange: (area: Area) => void = (_area: Area): void => {};
  onScrollerReady: (scroller: Scroller) => void = (_scroller: Scroller): void => {};
  private readonly scroller: Scroller = new Scroller();

  aboutToAppear(): void {
    this.onScrollerReady(this.scroller);
  }

  build() {
    Scroll(this.scroller) {
      Column({ space: 16 }) {
        Text('主题').fontSize(16).fontColor(this.primaryTextColor)
        Row({ space: 10 }) {
          ForEach(PROJECTION_THEMES, (theme: ProjectionTheme) => {
            Column({ space: 6 }) {
              Button({ type: ButtonType.Normal }) {
                Image(this.wallpaperResource(theme.id))
                  .width('100%')
                  .height('100%')
                  .objectFit(ImageFit.Cover)
              }
              .width(84)
              .height(58)
              .padding(0)
              .borderRadius(14)
              .backgroundColor(Color.Transparent)
              .border({
                width: this.theme === theme.id ? 2 : 1,
                color: this.theme === theme.id ? this.primaryTextColor : this.strokeColor
              })
              .clip(true)
              .onClick((): void => this.onThemeChange(theme.id))
              .onAreaChange((_oldArea, newArea) => this.onTouchAreaChange(
                theme.id, newArea, (): void => this.onThemeChange(theme.id)))
              .accessibilityText(theme.label)
              Text(theme.label).fontSize(12).fontColor(this.primaryTextColor)
            }
            .width(84)
          }, (theme: ProjectionTheme) => theme.id)
        }
        Text('强调色').fontSize(12).fontColor(this.secondaryTextColor)
        Row({ space: 12 }) {
          ForEach(PROJECTION_ACCENTS, (color: string) => {
            Button({ type: ButtonType.Circle }) {
              if (this.accent === color) {
                SymbolGlyph($r('sys.symbol.checkmark')).fontSize(16).fontColor([this.mapBackgroundColor])
              }
            }
            .width(30).height(30).backgroundColor(color)
            .border({
              width: this.accent === color ? 2 : 0,
              color: this.accent === color ? this.primaryTextColor : Color.Transparent
            })
            .onClick((): void => this.onAccentChange(color))
            .onAreaChange((_oldArea, newArea) => this.onTouchAreaChange(
              color, newArea, (): void => this.onAccentChange(color)))
            .accessibilityText(`强调色 ${color}`)
          }, (color: string) => color)
        }
      }
      .width('100%').padding(16)
    }
    .width('100%').height('100%')
    .backgroundColor(this.panelColor)
    .border({ width: 1, color: this.strokeColor })
    .borderRadius(22)
    .clip(true)
    .onAreaChange((_oldArea, newArea) => this.onBoundsChange(newArea))
  }
}
