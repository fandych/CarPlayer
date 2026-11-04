export interface ProjectionDockItem {
  id: string;
  label: string;
  icon: string;
  selected: boolean;
}

@Component
export struct ProjectionSignalIndicator {
  @Prop signalLevel: number = 0;
  @Prop networkLabel: string = '网络';
  @Prop primaryTextColor: string = '#FFFFFF';
  @Prop mutedTextColor: string = '#8E8E93';

  build() {
    Row({ space: 2 }) {
      Column().width(3).height(5)
        .backgroundColor(this.signalLevel >= 1 ? this.primaryTextColor : this.mutedTextColor)
      Column().width(3).height(8)
        .backgroundColor(this.signalLevel >= 2 ? this.primaryTextColor : this.mutedTextColor)
      Column().width(3).height(11)
        .backgroundColor(this.signalLevel >= 3 ? this.primaryTextColor : this.mutedTextColor)
      Column().width(3).height(14)
        .backgroundColor(this.signalLevel >= 4 ? this.primaryTextColor : this.mutedTextColor)
    }
    .height(16)
    .alignItems(VerticalAlign.Bottom)
    .accessibilityText(`${this.networkLabel}信号 ${this.signalLevel}/4`)
  }
}

@Component
export struct ProjectionBatteryIndicator {
  @Prop batteryPercent: number = 0;
  @Prop accent: string = '#0A84FF';
  @Prop secondaryTextColor: string = '#9EFFFFFF';

  build() {
    Row({ space: 3 }) {
      Stack({ alignContent: Alignment.TopStart }) {
        Column()
          .width(21)
          .height(11)
          .borderRadius(3)
          .border({ width: 1, color: this.secondaryTextColor })
        Row()
          .width(Math.max(2, 17 * this.batteryPercent / 100))
          .height(7)
          .margin({ left: 2, top: 2 })
          .borderRadius(1)
          .backgroundColor(this.batteryPercent <= 20 ? '#E0785E' : this.accent)
      }
      .width(21)
      .height(11)
      Column().width(2).height(5).borderRadius(1).backgroundColor(this.secondaryTextColor)
    }
    .alignItems(VerticalAlign.Center)
    .accessibilityText(`电量 ${this.batteryPercent}%`)
  }
}

@Component
export struct ProjectionDock {
  @Prop vertical: boolean = true;
  @Prop items: ProjectionDockItem[] = [];
  @Prop signalLevel: number = 0;
  @Prop networkLabel: string = '网络';
  @Prop batteryPercent: number = 0;
  @Prop accent: string = '#0A84FF';
  @Prop dockIconSize: number = 30;
  @Prop dockHint: string = '';
  @Prop primaryTextColor: string = '#FFFFFF';
  @Prop secondaryTextColor: string = '#A1A1AA';
  @Prop mutedTextColor: string = '#8E8E93';
  @Prop surfaceColor: string = '#262630';
  @Prop strokeColor: string = '#38FFFFFF';
  onAction: (id: string, longPress: boolean) => void = (_id: string, _longPress: boolean): void => {};
  onHintChange: (hint: string) => void = (_hint: string): void => {};
  iconResource: (icon: string, selected: boolean) => Resource =
    (_icon: string, _selected: boolean): Resource => $r('app.media.ic_house');
  onTouchAreaChange: (
    key: string, area: Area, action: () => void, longPress?: () => void
  ) => void = (_key: string, _area: Area, _action: () => void, _longPress?: () => void): void => {};
  onBoundsChange: (area: Area) => void = (_area: Area): void => {};
  onScrollerReady: (scroller: Scroller) => void = (_scroller: Scroller): void => {};
  private readonly scroller: Scroller = new Scroller();

  aboutToAppear(): void {
    this.onScrollerReady(this.scroller);
  }

  @Builder
  private DockItem(item: ProjectionDockItem, vertical: boolean) {
    Stack({ alignContent: Alignment.Center }) {
      Image(this.iconResource(item.icon, item.selected))
        .width(this.dockIconSize)
        .height(this.dockIconSize)
        .objectFit(ImageFit.Contain)
        .borderRadius(8)
    }
    .width(vertical ? '100%' : 64)
    .height(vertical ? 48 : '100%')
    .borderRadius(16)
    .backgroundColor(item.selected ? this.colorWithAlpha(this.accent, 'D9') : Color.Transparent)
    .border({ width: 1, color: item.selected ? '#55FFFFFF' : Color.Transparent })
    .gesture(GestureGroup(GestureMode.Exclusive,
      LongPressGesture({ duration: 550 }).onAction((): void => {
        if (item.id === 'map' || item.id === 'music') {
          this.onAction(item.id, true);
        }
      }),
      TapGesture().onAction((): void => this.onAction(item.id, false))))
    .accessibilityText(item.label)
    .onAreaChange((_oldArea, newArea) => this.onTouchAreaChange(
      item.id, newArea,
      (): void => this.onAction(item.id, false),
      (): void => {
        if (item.id === 'map' || item.id === 'music') {
          this.onAction(item.id, true);
        }
      }))
    .bindPopup(this.dockHint === item.label, { message: item.label })
    .onHover((hovered: boolean): void => this.onHintChange(hovered ? item.label : ''))
  }

  private colorWithAlpha(color: string, alpha: string): string {
    return `#${alpha}${color.slice(1)}`;
  }

  build() {
    if (this.vertical) {
      Scroll(this.scroller) {
        Column({ space: 4 }) {
          Column({ space: 3 }) {
            ProjectionSignalIndicator({
              signalLevel: this.signalLevel,
              networkLabel: this.networkLabel,
              primaryTextColor: this.primaryTextColor,
              mutedTextColor: this.mutedTextColor
            })
            ProjectionBatteryIndicator({
              batteryPercent: this.batteryPercent,
              accent: this.accent,
              secondaryTextColor: this.secondaryTextColor
            })
          }
          .height(32)
          .justifyContent(FlexAlign.Center)
          .padding({ left: 2, right: 2 })
          ForEach(this.items, (item: ProjectionDockItem) => this.DockItem(item, true),
            (item: ProjectionDockItem) => `${item.id}:${item.selected}`)
        }
        .width('100%')
        .height('100%')
        .constraintSize({ minHeight: 320 })
        .padding({ top: 8, bottom: 8, left: 5, right: 5 })
        .alignItems(HorizontalAlign.Center)
        .backgroundColor(this.surfaceColor)
        .border({ width: 1, color: this.strokeColor })
        .borderRadius(24)
        .clip(true)
      }
      .width('8%').constraintSize({ minWidth: 64, maxWidth: 92 }).height('100%')
      .scrollable(ScrollDirection.Vertical).scrollBar(BarState.Off)
      .borderRadius(24).clip(true)
      .onAreaChange((_oldArea, newArea) => this.onBoundsChange(newArea))
    } else {
      Scroll(this.scroller) {
        Row({ space: 4 }) {
          Column({ space: 2 }) {
            ProjectionSignalIndicator({
              signalLevel: this.signalLevel,
              networkLabel: this.networkLabel,
              primaryTextColor: this.primaryTextColor,
              mutedTextColor: this.mutedTextColor
            })
            ProjectionBatteryIndicator({
              batteryPercent: this.batteryPercent,
              accent: this.accent,
              secondaryTextColor: this.secondaryTextColor
            })
          }
          .width(36)
          .height('100%')
          .justifyContent(FlexAlign.Center)
          ForEach(this.items, (item: ProjectionDockItem) => this.DockItem(item, false),
            (item: ProjectionDockItem) => `${item.id}:${item.selected}`)
        }
        .width('100%').height('100%').constraintSize({ minWidth: 396 })
        .padding({ left: 8, right: 8, top: 4, bottom: 4 })
        .justifyContent(FlexAlign.Center)
        .backgroundColor(this.surfaceColor)
        .border({ width: 1, color: this.strokeColor })
        .borderRadius(18)
        .clip(true)
      }
      .width('100%').height(64)
      .scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off)
      .borderRadius(18).clip(true)
      .onAreaChange((_oldArea, newArea) => this.onBoundsChange(newArea))
    }
  }
}
