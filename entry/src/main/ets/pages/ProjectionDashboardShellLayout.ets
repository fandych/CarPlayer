import { ProjectionDock, ProjectionDockItem } from './ProjectionDock';

@Component
export struct ProjectionDashboardShellLayout {
  @Prop theme: string = 'aurora';
  @Prop wallpaperResource: (themeId: string) => Resource = (_themeId: string): Resource =>
    $r('app.media.projection_aurora');
  @Prop lightAppearance: boolean = false;
  @Prop dockPosition: string = 'left';
  @Prop safeInsetTop: number = 0;
  @Prop safeInsetRight: number = 0;
  @Prop safeInsetBottom: number = 0;
  @Prop safeInsetLeft: number = 0;
  @Prop contentScalePercent: number = 100;
  @Prop contentOffsetXPercent: number = 0;
  @Prop contentOffsetYPercent: number = 0;
  @Prop themeBackgroundColor: string = '#10101C';
  @Prop displayBrightness: number = 80;
  @Prop dockItems: ProjectionDockItem[] = [];
  @Prop signalLevel: number = 0;
  @Prop networkLabel: string = '网络';
  @Prop batteryPercent: number = 0;
  @Prop accent: string = '#0A84FF';
  @Prop dockIconSize: number = 30;
  @Prop dockHint: string = '';
  @Prop primaryTextColor: string = '#FFFFFF';
  @Prop secondaryTextColor: string = '#9EFFFFFF';
  @Prop mutedTextColor: string = '#80FFFFFF';
  @Prop glassSurfaceColor: string = '#9E1E1E26';
  @Prop glassStrokeColor: string = '#38FFFFFF';
  @Prop dockIconResource: (icon: string, selected: boolean) => Resource =
    (_icon: string, _selected: boolean): Resource => $r('app.media.ic_house');
  @Prop onDockAction: (id: string, longPress: boolean) => void = (_id: string, _longPress: boolean): void => {};
  @Prop onDockHintChange: (hint: string) => void = (_hint: string): void => {};
  @Prop onTouchAreaChange: (
    group: string, key: string, area: Area, action: () => void, longPress?: () => void,
    drag?: (pointX: number) => void
  ) => void = (_group: string, _key: string, _area: Area, _action: () => void,
    _longPress?: () => void, _drag?: (pointX: number) => void): void => {};
  @Prop onDockScrollerReady: (scroller: Scroller) => void = (_scroller: Scroller): void => {};
  @Prop onTouchBoundsChange: (group: string, area: Area) => void =
    (_group: string, _area: Area): void => {};
  @Prop onViewportAreaChange: (area: Area) => void = (_area: Area): void => {};
  @BuilderParam content: () => void = this.EmptyContent;

  @Builder
  private EmptyContent() {}

  @Builder
  private DockPanel(vertical: boolean) {
    ProjectionDock({
      vertical: vertical,
      items: this.dockItems,
      signalLevel: this.signalLevel,
      networkLabel: this.networkLabel,
      batteryPercent: this.batteryPercent,
      accent: this.accent,
      dockIconSize: this.dockIconSize,
      dockHint: this.dockHint,
      primaryTextColor: this.primaryTextColor,
      secondaryTextColor: this.secondaryTextColor,
      mutedTextColor: this.mutedTextColor,
      surfaceColor: this.glassSurfaceColor,
      strokeColor: this.glassStrokeColor,
      onAction: this.onDockAction,
      onHintChange: this.onDockHintChange,
      iconResource: this.dockIconResource,
      onTouchAreaChange: (key: string, area: Area, action: () => void, longPress?: () => void): void =>
        this.onTouchAreaChange('dock', key, area, action, longPress),
      onScrollerReady: this.onDockScrollerReady,
      onBoundsChange: (area: Area): void => this.onTouchBoundsChange('dock', area)
    })
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Image(this.wallpaperResource(this.theme))
        .width('100%').height('100%').objectFit(ImageFit.Cover)
      if (this.lightAppearance) {
        Column().width('100%').height('100%').backgroundColor('#6BFFFFFF')
      }
      if (this.dockPosition === 'bottom') {
        Column({ space: 8 }) {
          this.content()
          this.DockPanel(false)
        }
        .width('100%').height('100%')
        .padding({
          top: `${this.safeInsetTop}%`, right: `${this.safeInsetRight}%`,
          bottom: `${this.safeInsetBottom}%`, left: `${this.safeInsetLeft}%`
        })
        .scale({ x: this.contentScalePercent / 100, y: this.contentScalePercent / 100 })
        .translate({ x: `${this.contentOffsetXPercent}%`, y: `${this.contentOffsetYPercent}%` })
      } else {
        Row({ space: 8 }) {
          this.DockPanel(true)
          this.content()
        }
        .width('100%').height('100%')
        .padding({
          top: `${this.safeInsetTop}%`, right: `${this.safeInsetRight}%`,
          bottom: `${this.safeInsetBottom}%`, left: `${this.safeInsetLeft}%`
        })
        .scale({ x: this.contentScalePercent / 100, y: this.contentScalePercent / 100 })
        .translate({ x: `${this.contentOffsetXPercent}%`, y: `${this.contentOffsetYPercent}%` })
      }
    }
    .width('100%').height('100%').padding(8).clip(true)
    .backgroundColor(this.themeBackgroundColor)
    .brightness(0.5 + this.displayBrightness / 200)
    .onAreaChange((_oldArea, newArea) => this.onViewportAreaChange(newArea))
  }
}
