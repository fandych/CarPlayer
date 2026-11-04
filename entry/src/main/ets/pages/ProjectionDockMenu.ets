import { ProjectionApp, isProjectionAppLaunchable, PROJECTION_MAP_URI } from './ProjectionAppCatalog';
import { ProjectionAppIcon } from './ProjectionAppsPage';

@Component
export struct ProjectionDockMenu {
  @Prop dashboardView: string = 'maps';
  @Prop apps: ProjectionApp[] = [];
  @Prop selectedMapUri: string = '';
  @Prop selectedMusicUri: string = '';
  @Prop mediaBundleName: string = '';
  @Prop activeAppLabel: string = '';
  @Prop activeAppUri: string = '';
  @Prop activeAppOnPhone: boolean = false;
  @Prop mapAppLabel: string = '';
  @Prop mapAppUri: string = '';
  @Prop mapOnPhone: boolean = false;
  @Prop dockActionMessage: string = '';
  @Prop accent: string = '#0A84FF';
  @Prop primaryTextColor: string = '#FFFFFF';
  @Prop secondaryTextColor: string = '#9EFFFFFF';
  @Prop glassSecondaryColor: string = '#14FFFFFF';
  @Prop glassPanelColor: string = '#75262630';
  @Prop glassStrokeColor: string = '#38FFFFFF';
  @Prop cardStrokeColor: string = '#20FFFFFF';
  onHome: () => void = (): void => {};
  onSelectApp: (app: ProjectionApp) => void = (_app: ProjectionApp): void => {};
  onToggleAppDisplay: () => void = (): void => {};
  onToggleMapDisplay: () => void = (): void => {};
  onTouchAreaChange: (group: string, key: string, area: Area, action: () => void) => void =
    (_group: string, _key: string, _area: Area, _action: () => void): void => {};
  onBoundsChange: (area: Area) => void = (_area: Area): void => {};
  onScrollerReady: (scroller: Scroller) => void = (_scroller: Scroller): void => {};
  private readonly scroller: Scroller = new Scroller();

  aboutToAppear(): void {
    this.onScrollerReady(this.scroller);
  }

  private categoryApp(category: 'map' | 'music'): ProjectionApp | undefined {
    const selectedUri = category === 'map' ? this.selectedMapUri : this.selectedMusicUri;
    return this.apps.find((app: ProjectionApp): boolean =>
      app.category === category && app.uri === selectedUri) ??
      this.apps.find((app: ProjectionApp): boolean =>
        app.category === category &&
        (category === 'map' ? app.uri === PROJECTION_MAP_URI : app.bundleName === this.mediaBundleName)) ??
      this.apps.find((app: ProjectionApp): boolean => app.category === category);
  }

  build() {
    Column({ space: 12 }) {
      Row() {
        Blank()
        Button({ type: ButtonType.Circle }) {
          SymbolGlyph($r('sys.symbol.xmark')).fontSize(18).fontColor([this.primaryTextColor])
        }
        .width(36).height(36).backgroundColor(this.glassSecondaryColor).borderRadius(12)
        .onClick((): void => this.onHome())
        .accessibilityText('关闭应用菜单')
        .onAreaChange((_oldArea, newArea) => {
          this.onTouchAreaChange('maps', 'close', newArea, (): void => this.onHome());
          this.onTouchAreaChange('music', 'close', newArea, (): void => this.onHome());
        })
      }
      .width('100%')
      if (this.dashboardView === 'maps' && this.mapAppLabel.length > 0 &&
        this.mapAppUri === this.categoryApp('map')?.uri) {
        Button({ type: ButtonType.Circle }) {
          SymbolGlyph($r('sys.symbol.arrow_up_right')).fontSize(18).fontColor([this.primaryTextColor])
        }
          .width(44).height(44).backgroundColor(this.glassSecondaryColor)
          .onClick((): void => this.onToggleMapDisplay())
          .accessibilityText(this.mapOnPhone ? '切换地图到虚拟屏' : '切换地图到手机')
          .onAreaChange((_oldArea, newArea) => this.onTouchAreaChange(
            'maps', 'toggleDisplay', newArea, (): void => this.onToggleMapDisplay()))
      } else if (this.dashboardView === 'maps' && this.activeAppLabel.length > 0 &&
        this.activeAppUri === this.categoryApp('map')?.uri) {
        Button({ type: ButtonType.Circle }) {
          SymbolGlyph($r('sys.symbol.arrow_up_right')).fontSize(18).fontColor([this.primaryTextColor])
        }
          .width(44).height(44).backgroundColor(this.glassSecondaryColor)
          .onClick((): void => this.onToggleAppDisplay())
          .accessibilityText(this.activeAppOnPhone ? '切换地图到虚拟屏' : '切换地图到手机')
          .onAreaChange((_oldArea, newArea) => this.onTouchAreaChange(
            'maps', 'toggleDisplay', newArea, (): void => this.onToggleAppDisplay()))
      }
      if (this.dockActionMessage.length > 0) {
        Text(this.dockActionMessage).fontSize(11).fontColor(this.secondaryTextColor).maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      Scroll(this.scroller) {
        Column({ space: 6 }) {
          ForEach(this.apps.filter((app: ProjectionApp): boolean =>
            app.category === (this.dashboardView === 'maps' ? 'map' : 'music')), (app: ProjectionApp) => {
            Row({ space: 12 }) {
              ProjectionAppIcon({ app: app, iconSize: 36, accent: this.accent })
              Text(app.label).fontSize(14).fontColor(this.primaryTextColor).layoutWeight(1).maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              if (this.categoryApp(app.category === 'map' ? 'map' : 'music')?.uri === app.uri) {
                SymbolGlyph($r('sys.symbol.checkmark')).fontSize(18).fontColor([this.accent])
              }
            }
            .width('100%').height(60).padding({ left: 12, right: 12 }).borderRadius(16)
            .backgroundColor(this.categoryApp(app.category === 'map' ? 'map' : 'music')?.uri === app.uri
              ? `#2A${this.accent.slice(1)}` : this.glassPanelColor)
            .border({ width: 1, color: this.cardStrokeColor })
            .onClick((): void => this.onSelectApp(app))
            .onAreaChange((_oldArea, newArea) => this.onTouchAreaChange(
              app.category === 'map' ? 'maps' : 'music', app.uri, newArea, (): void => this.onSelectApp(app)))
            .opacity(isProjectionAppLaunchable(app) ? 1 : 0.62)
          }, (app: ProjectionApp) => app.uri)
          if (!this.apps.some((app: ProjectionApp): boolean =>
            app.category === (this.dashboardView === 'maps' ? 'map' : 'music'))) {
            Text('暂无可用应用').fontSize(13).fontColor(this.secondaryTextColor).padding(16)
          }
        }
        .width('100%')
      }
      .layoutWeight(1).width('100%')
    }
    .width('100%').height('100%').padding(16)
    .backgroundColor(this.glassPanelColor)
    .border({ width: 1, color: this.glassStrokeColor })
    .borderRadius(22)
    .clip(true)
    .onAreaChange((_oldArea, newArea) => this.onBoundsChange(newArea))
  }
}
