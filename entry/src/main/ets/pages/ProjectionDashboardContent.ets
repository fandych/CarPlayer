import { ProjectionApp, activeProjectionMusicApp } from './ProjectionAppCatalog';
import { ProjectionMediaCommand, ProjectionMediaSnapshot } from '../session/MediaSessionBridge';
import { ProjectionMediaSidebar } from './ProjectionMediaSidebar';
import { projectionSurfaceSize, ProjectionSurfaceSize } from './ProjectionSurface';

@Component
struct ProjectionContentSurface {
  @Prop surfaceName: string = '';
  @Prop landscape: boolean = false;
  onSurfaceChange: (surfaceId: string, area: Area | undefined, attached: boolean) => void =
    (_surfaceId: string, _area: Area | undefined, _attached: boolean): void => {};
  @State private viewportWidth: number = 0;
  @State private viewportHeight: number = 0;
  private readonly controller: XComponentController = new XComponentController();
  private surfaceId: string = '';
  private surfaceArea?: Area;

  private surfaceSize(): ProjectionSurfaceSize {
    return projectionSurfaceSize(this.viewportWidth, this.viewportHeight, this.landscape);
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      if (this.viewportWidth > 0 && this.viewportHeight > 0) {
        XComponent({ id: this.surfaceName, type: XComponentType.SURFACE, controller: this.controller })
          .width(this.surfaceSize().width)
          .height(this.surfaceSize().height)
          .onLoad((): void => {
            this.surfaceId = this.controller.getXComponentSurfaceId();
            this.onSurfaceChange(this.surfaceId, this.surfaceArea, true);
          })
          .onDestroy((): void => {
            this.surfaceId = '';
            this.surfaceArea = undefined;
            this.onSurfaceChange('', undefined, false);
          })
          .onAreaChange((_oldArea, newArea) => {
            this.surfaceArea = newArea;
            this.onSurfaceChange(this.surfaceId, newArea, true);
          })
      }
    }
    .width('100%')
    .height('100%')
    .onAreaChange((_oldArea, newArea) => {
      this.viewportWidth = Number.parseFloat(`${newArea.width}`);
      this.viewportHeight = Number.parseFloat(`${newArea.height}`);
    })
  }
}

@Component
export struct ProjectionDashboardContent {
  @Prop dashboardView: string = 'home';
  @Prop preserveSplitSurfaceForOverlays: boolean = false;
  @Prop activeAppLabel: string = '';
  @Prop activeAppUri: string = '';
  @Prop appOnPhone: boolean = false;
  @Prop mapAppLabel: string = '';
  @Prop mapAppUri: string = '';
  @Prop mapOnPhone: boolean = false;
  @Prop navigationPreview: boolean = false;
  @Prop launchMessage: string = '';
  @Prop mapMessage: string = '';
  @Prop splitMapRatio: number = 3;
  @Prop splitMusicRatio: number = 2;
  @Prop apps: ProjectionApp[] = [];
  @Prop selectedMapUri: string = '';
  @Prop selectedMusicUri: string = '';
  @Prop mediaState: ProjectionMediaSnapshot = {
    title: '',
    artist: '',
    lyric: '',
    positionMs: 0,
    durationMs: 0,
    isPlaying: false,
    commands: [],
    queue: [],
    message: ''
  };
  @Prop accent: string = '#0A84FF';
  @Prop primaryTextColor: string = '#FFFFFF';
  @Prop secondaryTextColor: string = '#9EFFFFFF';
  @Prop glassSecondaryColor: string = '#14FFFFFF';
  @Prop glassPanelColor: string = '#75262630';
  @Prop glassStrokeColor: string = '#38FFFFFF';
  @Prop cardStrokeColor: string = '#20FFFFFF';
  @Prop theme: string = 'aurora';
  @Prop lightAppearance: boolean = false;
  wallpaperResource: (themeId: string) => Resource = (_themeId: string): Resource =>
    $r('app.media.projection_aurora');
  mapPreviewResource: () => Resource = (): Resource => $r('app.media.projection_map_preview');
  onAppSurfaceChange: (surfaceId: string, area: Area | undefined, attached: boolean) => void =
    (_surfaceId: string, _area: Area | undefined, _attached: boolean): void => {};
  onMapSurfaceChange: (surfaceId: string, area: Area | undefined, attached: boolean) => void =
    (_surfaceId: string, _area: Area | undefined, _attached: boolean): void => {};
  onTouchAreaChange: (
    group: string, key: string, area: Area, action: () => void, longPress?: () => void,
    drag?: (pointX: number) => void
  ) => void = (_group: string, _key: string, _area: Area, _action: () => void,
    _longPress?: () => void, _drag?: (pointX: number) => void): void => {};
  onTouchBoundsChange: (group: string, area: Area) => void =
    (_group: string, _area: Area): void => {};
  onToggleAppDisplay: () => void = (): void => {};
  onToggleMapDisplay: () => void = (): void => {};
  onOpenMediaApp: () => void = (): void => {};
  onOpenMapApp: () => void = (): void => {};
  onSendMediaCommand: (command: ProjectionMediaCommand) => void = (_command: ProjectionMediaCommand): void => {};

  private hasActiveMusicApp(): boolean {
    return !this.appOnPhone && !!activeProjectionMusicApp(this.apps, this.activeAppUri);
  }

  private categoryApp(category: 'map' | 'music'): ProjectionApp | undefined {
    const selectedUri = category === 'map' ? this.selectedMapUri : this.selectedMusicUri;
    return this.apps.find((app: ProjectionApp): boolean =>
      app.category === category && app.uri === selectedUri) ??
      this.apps.find((app: ProjectionApp): boolean =>
        app.category === category && app.uri === this.activeAppUri) ??
      this.apps.find((app: ProjectionApp): boolean => app.category === category);
  }

  private isActiveMap(): boolean {
    return this.apps.some((app: ProjectionApp): boolean =>
      app.uri === this.activeAppUri && app.category === 'map');
  }

  @Builder
  private SplitPage() {
    Row({ space: 8 }) {
      Column({ space: 6 }) {
        Stack({ alignContent: Alignment.BottomStart }) {
          ProjectionContentSurface({
            surfaceName: 'projectionSplitMapSurface',
            landscape: true,
            onSurfaceChange: (surfaceId: string, area: Area | undefined, attached: boolean): void =>
              this.onMapSurfaceChange(surfaceId, area, attached)
          })
            .width('100%')
            .height('100%')
          if (this.mapMessage.length > 0) {
            Text(this.mapMessage).fontSize(11).fontColor(this.secondaryTextColor)
              .textAlign(TextAlign.Center).padding(12)
          }
        }
        .layoutWeight(1)
        .width('100%')
        .clip(true)
      }
      .layoutWeight(this.splitMapRatio)
      .height('100%')
      .padding(12)
      .borderRadius(22)
      .backgroundColor(this.glassPanelColor)
      .border({ width: 1, color: this.cardStrokeColor })
      .clip(true)

      Column({ space: 6 }) {
        if (this.hasActiveMusicApp()) {
          Stack({ alignContent: Alignment.Center }) {
            ProjectionContentSurface({
              surfaceName: 'projectionSplitMusicSurface',
              onSurfaceChange: (surfaceId: string, area: Area | undefined, attached: boolean): void =>
                this.onAppSurfaceChange(surfaceId, area, attached)
            })
              .width('100%')
              .height('100%')
            if (this.launchMessage.length > 0) {
              Text(this.launchMessage).fontSize(11).fontColor(this.secondaryTextColor)
                .textAlign(TextAlign.Center).padding(12)
            }
          }
          .layoutWeight(1)
          .width('100%')
          .clip(true)
        } else {
          Text('请先从音乐 Dock 打开音乐 app，再进入分屏')
            .fontSize(11).fontColor(this.secondaryTextColor).maxLines(2).layoutWeight(1)
        }
      }
      .layoutWeight(this.splitMusicRatio)
      .height('100%')
      .padding(12)
      .borderRadius(22)
      .backgroundColor(this.glassPanelColor)
      .border({ width: 1, color: this.cardStrokeColor })
      .clip(true)
    }
    .width('100%')
    .height('100%')
    .onAreaChange((_oldArea, newArea) => this.onTouchBoundsChange('split', newArea))
  }

  @Builder
  private DashboardSidebar() {
    ProjectionMediaSidebar({
      title: this.mediaState.title,
      lyric: this.mediaState.lyric,
      positionMs: this.mediaState.positionMs,
      durationMs: this.mediaState.durationMs,
      isPlaying: this.mediaState.isPlaying,
      commands: this.mediaState.commands,
      splitMusicRatio: this.splitMusicRatio,
      accent: this.accent,
      primaryTextColor: this.primaryTextColor,
      secondaryTextColor: this.secondaryTextColor,
      panelColor: this.glassPanelColor,
      cardStrokeColor: this.cardStrokeColor,
      secondaryButtonColor: this.glassSecondaryColor,
      onOpenMediaApp: (): void => this.onOpenMediaApp(),
      onSendMediaCommand: (command: ProjectionMediaCommand): void => this.onSendMediaCommand(command),
      onTouchAreaChange: (key: string, area: Area, action: () => void): void =>
        this.onTouchAreaChange('media', key, area, action),
      onBoundsChange: (area: Area): void => this.onTouchBoundsChange('media', area)
    })
  }

  @Builder
  private MainPanel() {
    Stack({ alignContent: Alignment.TopStart }) {
      if (this.dashboardView === 'split' || this.preserveSplitSurfaceForOverlays) {
        this.SplitPage()
      } else if (this.activeAppLabel.length > 0) {
        Row({ space: 8 }) {
          Stack({ alignContent: Alignment.BottomStart }) {
            ProjectionContentSurface({
              surfaceName: 'projectionAppSurface',
              landscape: this.isActiveMap(),
              onSurfaceChange: (surfaceId: string, area: Area | undefined, attached: boolean): void =>
                this.onAppSurfaceChange(surfaceId, area, attached)
            })
              .width('100%')
              .height('100%')
            if (this.launchMessage.length > 0) {
              Text(this.launchMessage)
                .fontSize(12)
                .fontColor(this.secondaryTextColor)
                .textAlign(TextAlign.Center)
                .padding(12)
            }
            if (this.navigationPreview) {
              Column() {}
                .width('100%').height('100%')
                .onClick((): void => this.onOpenMapApp())
                .onAreaChange((_oldArea, newArea) => {
                  this.onTouchBoundsChange('preview', newArea);
                  this.onTouchAreaChange('preview', 'expand', newArea, (): void => this.onOpenMapApp());
                })
                .accessibilityText('展开当前地图')
            }
          }
          .layoutWeight(this.splitMapRatio)
          .height('100%')
          .clip(true)
          if (this.navigationPreview) {
            this.DashboardSidebar()
          }
        }
        .width('100%').height('100%')
      } else {
        Row({ space: 14 }) {
          Stack({ alignContent: Alignment.TopStart }) {
            Image(this.mapPreviewResource())
              .width('100%').height('100%').objectFit(ImageFit.Cover)
            Column() {
              Row({ space: 12 }) {
                Stack({ alignContent: Alignment.Center }) {
                  SymbolGlyph($r('sys.symbol.arrow_up_right')).fontSize(22).fontColor(['#FFFFFF'])
                }
                .width(46).height(46).borderRadius(15).backgroundColor(this.accent)
                Column({ space: 4 }) {
                  Text('导航预览').fontSize(16).fontWeight(FontWeight.Bold).fontColor(this.primaryTextColor)
                  Text('示意地图 · 实际路线由地图应用提供')
                    .fontSize(11).fontColor(this.secondaryTextColor).maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                }
                .alignItems(HorizontalAlign.Start)
              }
              .width('100%').padding(12).borderRadius(18)
              .backgroundColor(this.glassPanelColor)
              .border({ width: 1, color: this.cardStrokeColor })
              Blank()
              Row({ space: 12 }) {
                Column({ space: 4 }) {
                  Text(this.launchMessage.length > 0 ? '地图暂不可用' : '准备开始导航')
                    .fontSize(15).fontWeight(FontWeight.Bold).fontColor(this.primaryTextColor)
                  Text(this.launchMessage || '打开地图应用以查看实时路线与路况')
                    .fontSize(11).fontColor(this.secondaryTextColor).maxLines(2)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                }
                .layoutWeight(1).alignItems(HorizontalAlign.Start)
                Button({ type: ButtonType.Normal }) {
                  Row({ space: 8 }) {
                    SymbolGlyph($r('sys.symbol.arrow_up_right')).fontSize(17).fontColor(['#FFFFFF'])
                    Text('打开地图').fontSize(13).fontWeight(FontWeight.Medium).fontColor('#FFFFFF')
                  }
                }
                .height(48).padding({ left: 14, right: 14 }).borderRadius(15)
                .backgroundColor(this.accent)
                .accessibilityText('打开地图')
                .onClick((): void => this.onOpenMapApp())
                .onAreaChange((_oldArea, newArea) => this.onTouchAreaChange(
                  'map', 'open', newArea, (): void => this.onOpenMapApp()))
              }
              .width('100%').padding(12).borderRadius(18)
              .backgroundColor(this.glassPanelColor)
              .border({ width: 1, color: this.cardStrokeColor })
            }
            .width('100%').height('100%').padding(14)
          }
          .layoutWeight(this.splitMapRatio).height('100%')
          .borderRadius(22).clip(true)
          .border({ width: 1, color: this.cardStrokeColor })
          .onAreaChange((_oldArea, newArea) => this.onTouchBoundsChange('map', newArea))
          this.DashboardSidebar()
        }
        .width('100%').height('100%')
      }
      if (this.dashboardView !== 'home' && this.dashboardView !== 'split') {
        Image(this.wallpaperResource(this.theme))
          .width('100%').height('100%').objectFit(ImageFit.Cover)
        if (this.lightAppearance) {
          Column()
            .width('100%')
            .height('100%')
            .backgroundColor('#6BFFFFFF')
        }
      }
    }
    .width('100%')
    .height('100%')
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      this.MainPanel()
    }
    .width('100%')
    .height('100%')
  }
}
