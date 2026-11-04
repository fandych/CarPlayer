@Component
export struct ProjectionSettingsDropdown {
  @Prop label: string = '';
  @Prop dropdownKey: string = '';
  @Prop options: string[] = [];
  @Prop selectedIndex: number = 0;
  @Prop controlEnabled: boolean = true;
  @Prop expanded: boolean = false;
  @Prop accent: string = '#0A84FF';
  @Prop primaryTextColor: string = '#FFFFFF';
  @Prop secondaryTextColor: string = '#9EFFFFFF';
  @Prop glassStrokeColor: string = '#38FFFFFF';
  @Prop glassSecondaryColor: string = '#14FFFFFF';
  @Prop glassPanelColor: string = '#75262630';
  @Prop settingsSeparatorColor: string = '#1FFFFFFF';
  onToggle: () => void = (): void => {};
  onSelect: (index: number) => void = (_index: number): void => {};
  onTouchAreaChange: (key: string, area: Area, action: () => void) => void =
    (_key: string, _area: Area, _action: () => void): void => {};

  private colorWithAlpha(color: string, alpha: string): string {
    return `#${alpha}${color.slice(1)}`;
  }

  build() {
    Column() {
      Row({ space: 16 }) {
        Text(this.label).fontSize(14).fontColor(this.primaryTextColor).layoutWeight(1)
        Button({ type: ButtonType.Normal }) {
          Row({ space: 8 }) {
            Text(this.options[this.selectedIndex] ?? '暂无可用选项')
              .fontSize(13)
              .fontColor(this.primaryTextColor)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
            Text('⌄').fontSize(16).fontColor(this.secondaryTextColor)
          }
          .width('100%')
        }
        .width(180)
        .height(42)
        .padding({ left: 12, right: 12 })
        .borderRadius(12)
        .backgroundColor(this.glassSecondaryColor)
        .border({ width: 1, color: this.glassStrokeColor })
        .enabled(this.controlEnabled)
        .accessibilityText(`${this.label}：${this.options[this.selectedIndex] ?? '暂无可用选项'}`)
        .onClick((): void => {
          if (this.controlEnabled) {
            this.onToggle();
          }
        })
        .onAreaChange((_oldArea, newArea) => this.onTouchAreaChange(
          `dropdown-${this.dropdownKey}-trigger`, newArea, (): void => {
            if (this.controlEnabled) {
              this.onToggle();
            }
          }))
      }
      .width('100%')
      .height(64)
      .padding(14)

      if (this.expanded) {
        Row() {
          Blank()
          Column({ space: 4 }) {
            ForEach(this.options, (option: string, index: number) => {
              Button({ type: ButtonType.Normal }) {
                Row() {
                  Text(option).fontSize(13).fontColor(this.primaryTextColor).layoutWeight(1)
                  if (this.selectedIndex === index) {
                    SymbolGlyph($r('sys.symbol.checkmark')).fontSize(14).fontColor([this.accent])
                  }
                }
                .width('100%')
              }
              .width('100%')
              .height(40)
              .padding({ left: 10, right: 10 })
              .borderRadius(10)
              .backgroundColor(this.selectedIndex === index
                ? this.colorWithAlpha(this.accent, '38') : Color.Transparent)
              .onClick((): void => this.onSelect(index))
              .onAreaChange((_oldArea, newArea) => this.onTouchAreaChange(
                `dropdown-${this.dropdownKey}-option-${index}`, newArea, (): void => this.onSelect(index)))
            }, (option: string): string => `${this.dropdownKey}-${option}`)
          }
          .width(180)
          .padding(6)
          .borderRadius(14)
          .backgroundColor(this.glassPanelColor)
          .border({ width: 1, color: this.glassStrokeColor })
          .shadow({ radius: 18, color: '#50000000', offsetX: 0, offsetY: 8 })
        }
        .width('100%')
        .padding({ left: 14, right: 14, bottom: 8 })
      }
    }
    .width('100%')
    .border({ width: { top: 1 }, color: this.settingsSeparatorColor })
  }
}
