import { hilog } from '@kit.PerformanceAnalysisKit';
import { ProjectionApp, isProjectionAppLaunchable } from './ProjectionAppCatalog';

export function projectionAppIconResource(appId: string): Resource | undefined {
  switch (appId) {
    case 'shell-home': return $r('app.media.ic_car_front');
    case 'shell-settings': return $r('app.media.ic_settings');
    case 'shell-themes': return $r('app.media.ic_palette');
    case 'shell-split': return $r('app.media.ic_layout_grid');
    case 'amap': return $r('app.media.app_amap');
    case 'baidu-map': return $r('app.media.app_baidu');
    case 'petal-maps': return $r('app.media.ic_navigation');
    case 'tencent-map': return $r('app.media.app_tencent_map');
    case 'huawei-music': return $r('app.media.app_huawei_music');
    case 'qq-music': return $r('app.media.app_qqmusic');
    case 'netease-music': return $r('app.media.app_netease');
    case 'kugou-music': return $r('app.media.app_kugou');
    case 'tangshui-music':
    case 'kuwo-music': return $r('app.media.ic_music');
    default: return undefined;
  }
}

@Component
export struct ProjectionAppIcon {
  @Prop app: ProjectionApp = {
    appId: '',
    uri: '',
    launchState: 'UNVERIFIED',
    label: '',
    mark: '',
    color: '#0A84FF',
    category: 'home'
  };
  @Prop iconSize: number = 36;
  @Prop accent: string = '#0A84FF';
  @State private failedAppId: string = '';

  build() {
    if (projectionAppIconResource(this.app.appId) && this.failedAppId !== this.app.appId) {
      Image(projectionAppIconResource(this.app.appId))
        .width(this.iconSize)
        .height(this.iconSize)
        .objectFit(ImageFit.Contain)
        .borderRadius(8)
        .onError((error) => {
          this.failedAppId = this.app.appId;
          hilog.error(0xCA22, 'CarPlayerProjection', '应用图标加载失败：%{public}s, %{public}s',
            this.app.appId, error?.message ?? 'unknown image error');
        })
    } else if (this.app.category === 'map') {
      SymbolGlyph($r('sys.symbol.arrow_up_right'))
        .fontSize(this.iconSize - 4)
        .fontColor([this.accent])
        .width(this.iconSize)
        .height(this.iconSize)
    } else {
      SymbolGlyph($r('sys.symbol.speaker_wave_2'))
        .fontSize(this.iconSize - 4)
        .fontColor([this.app.color])
        .width(this.iconSize)
        .height(this.iconSize)
    }
  }
}

@Component
struct ProjectionAppTile {
  @Prop app: ProjectionApp = {
    appId: '',
    uri: '',
    launchState: 'UNVERIFIED',
    label: '',
    mark: '',
    color: '#0A84FF',
    category: 'home'
  };
  @Prop accent: string = '#0A84FF';
  @Prop primaryTextColor: string = '#FFFFFF';
  onAppClick: (app: ProjectionApp) => void = (_app: ProjectionApp): void => {};
  onTouchAreaChange: (key: string, area: Area, action: () => void) => void =
    (_key: string, _area: Area, _action: () => void): void => {};

  build() {
    Column({ space: 8 }) {
      Stack({ alignContent: Alignment.Center }) {
        ProjectionAppIcon({ app: this.app, iconSize: 42, accent: this.accent })
      }
      .width(68)
      .height(68)
      .borderRadius(20)
      Text(this.app.label)
        .fontSize(13)
        .fontColor(this.primaryTextColor)
        .fontWeight(FontWeight.Medium)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .height(100)
    .justifyContent(FlexAlign.Center)
    .borderRadius(8)
    .opacity(this.app.launchState === 'UNVERIFIED' ? 0.62 : 1)
    .onClick((): void => this.onAppClick(this.app))
    .onAreaChange((_oldArea, newArea) => this.onTouchAreaChange(
      this.app.uri, newArea, (): void => this.onAppClick(this.app)))
    .accessibilityText(this.app.category === 'vehicle' || this.app.category === 'home' ||
      isProjectionAppLaunchable(this.app)
      ? `打开${this.app.label}` : `${this.app.label}，启动入口待验证`)
  }
}

@Component
export struct ProjectionAppsPage {
  @Prop apps: ProjectionApp[] = [];
  @Prop gridColumns: number = 4;
  @Prop gridTemplate: string = '1fr 1fr 1fr 1fr';
  @Prop panelColor: string = '#1E1E26';
  @Prop panelStrokeColor: string = '#38FFFFFF';
  @Prop primaryTextColor: string = '#FFFFFF';
  @Prop secondaryTextColor: string = '#A1A1AA';
  @Prop accent: string = '#0A84FF';
  onAppClick: (app: ProjectionApp) => void = (_app: ProjectionApp): void => {};
  onTouchAreaChange: (key: string, area: Area, action: () => void) => void =
    (_key: string, _area: Area, _action: () => void): void => {};
  onGridAreaChange: (area: Area) => void = (_area: Area): void => {};
  onScrollerReady: (scroller: Scroller) => void = (_scroller: Scroller): void => {};
  private readonly scroller: Scroller = new Scroller();

  aboutToAppear(): void {
    this.onScrollerReady(this.scroller);
  }

  build() {
    Scroll(this.scroller) {
      Column({ space: 12 }) {
        Row() {
          Text('应用').fontSize(22).fontWeight(FontWeight.Bold).fontColor(this.primaryTextColor)
          Blank()
          Text(`${this.apps.length} 个应用`).fontSize(12).fontColor(this.secondaryTextColor)
        }
        .width('100%')
        Grid() {
          ForEach(this.apps, (app: ProjectionApp) => {
            GridItem() {
              ProjectionAppTile({
                app: app,
                accent: this.accent,
                primaryTextColor: this.primaryTextColor,
                onAppClick: (selectedApp: ProjectionApp): void => this.onAppClick(selectedApp),
                onTouchAreaChange: (key: string, area: Area, action: () => void): void =>
                  this.onTouchAreaChange(key, area, action)
              })
            }
          }, (app: ProjectionApp) => app.uri)
        }
        .columnsTemplate(this.gridTemplate).columnsGap(18).rowsGap(14)
        .height(Math.ceil(this.apps.length / this.gridColumns) * 114)
        .width('100%')
      }
      .width('100%').padding(18)
    }
    .width('100%').height('100%')
    .backgroundColor(this.panelColor)
    .border({ width: 1, color: this.panelStrokeColor })
    .borderRadius(22)
    .clip(true)
    .onAreaChange((_oldArea, newArea) => this.onGridAreaChange(newArea))
  }
}
