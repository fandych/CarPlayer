import { isProjectionAppLaunchable, ProjectionApp, PROJECTION_VEHICLE_APPS } from './ProjectionAppCatalog';
import { ProjectionAppsPage } from './ProjectionAppsPage';
import { ProjectionDashboardContent } from './ProjectionDashboardContent';
import { ProjectionDockMenu } from './ProjectionDockMenu';
import { ProjectionThemesPage } from './ProjectionThemesPage';
import { ProjectionMediaCommand, ProjectionMediaSnapshot } from '../session/MediaSessionBridge';

@Component
export struct ProjectionDashboardShellContent {
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
    title: '', artist: '', lyric: '', positionMs: 0, durationMs: 0, isPlaying: false, commands: [], queue: [], message: ''
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
  @Prop mapBackgroundColor: string = '#1D2230';
  @Prop verticalDock: boolean = false;
  @Prop wallpaperResource: (themeId: string) => Resource = (_themeId: string): Resource =>
    $r('app.media.projection_aurora');
  @Prop mapPreviewResource: () => Resource = (): Resource => $r('app.media.projection_map_preview');
  @Prop appsGridColumns: number = 4;
  @Prop appsGridTemplate: string = '1fr 1fr 1fr 1fr';
  @Prop dockActionMessage: string = '';
  @Prop onAppSurfaceChange: (surfaceId: string, area: Area | undefined, attached: boolean) => void =
    (_surfaceId: string, _area: Area | undefined, _attached: boolean): void => {};
  @Prop onMapSurfaceChange: (surfaceId: string, area: Area | undefined, attached: boolean) => void =
    (_surfaceId: string, _area: Area | undefined, _attached: boolean): void => {};
  @Prop onTouchAreaChange: (
    group: string, key: string, area: Area, action: () => void, longPress?: () => void,
    drag?: (pointX: number) => void
  ) => void = (_group: string, _key: string, _area: Area, _action: () => void,
    _longPress?: () => void, _drag?: (pointX: number) => void): void => {};
  @Prop onTouchBoundsChange: (group: string, area: Area) => void =
    (_group: string, _area: Area): void => {};
  @Prop onToggleAppDisplay: () => void = (): void => {};
  @Prop onToggleMapDisplay: () => void = (): void => {};
  @Prop onOpenMediaApp: () => void = (): void => {};
  @Prop onOpenMapApp: () => void = (): void => {};
  @Prop onSendMediaCommand: (command: ProjectionMediaCommand) => void = (_command: ProjectionMediaCommand): void => {};
  @Prop onSelectApp: (app: ProjectionApp) => void = (_app: ProjectionApp): void => {};
  @Prop onGridAreaChange: (area: Area) => void = (_area: Area): void => {};
  @Prop onAppsScrollerReady: (scroller: Scroller) => void = (_scroller: Scroller): void => {};
  @Prop onSettingsTabChange: (tab: string) => void = (_tab: string): void => {};
  @Prop settingsPage: ProjectionDashboardShellSettingsPage;
  @Prop onThemeChange: (themeId: string) => void = (_themeId: string): void => {};
  @Prop onAccentChange: (color: string) => void = (_color: string): void => {};
  @Prop onThemesScrollerReady: (scroller: Scroller) => void = (_scroller: Scroller): void => {};
  @Prop onDockMenuBoundsChange: (area: Area) => void = (_area: Area): void => {};
  @Prop onDockMenuScrollerReady: (scroller: Scroller) => void = (_scroller: Scroller): void => {};
  @Prop onHomeClick: () => void = (): void => {};
  @BuilderParam settingsPage: () => void = this.EmptySettingsPage;

  @Builder
  private EmptySettingsPage() {}

  private visibleApps(): ProjectionApp[] {
    const visible: ProjectionApp[] = [...PROJECTION_VEHICLE_APPS];
    for (const app of this.apps) {
      if (isProjectionAppLaunchable(app)) {
        visible.push(app);
      }
    }
    return visible;
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      ProjectionDashboardContent({
        dashboardView: this.dashboardView,
        preserveSplitSurfaceForOverlays: this.preserveSplitSurfaceForOverlays,
        activeAppLabel: this.activeAppLabel,
        activeAppUri: this.activeAppUri,
        appOnPhone: this.appOnPhone,
        mapAppLabel: this.mapAppLabel,
        mapAppUri: this.mapAppUri,
        mapOnPhone: this.mapOnPhone,
        navigationPreview: this.navigationPreview,
        launchMessage: this.launchMessage,
        mapMessage: this.mapMessage,
        splitMapRatio: this.splitMapRatio,
        splitMusicRatio: this.splitMusicRatio,
        apps: this.apps,
        selectedMapUri: this.selectedMapUri,
        selectedMusicUri: this.selectedMusicUri,
        mediaState: this.mediaState,
        accent: this.accent,
        primaryTextColor: this.primaryTextColor,
        secondaryTextColor: this.secondaryTextColor,
        glassSecondaryColor: this.glassSecondaryColor,
        glassPanelColor: this.glassPanelColor,
        glassStrokeColor: this.glassStrokeColor,
        cardStrokeColor: this.cardStrokeColor,
        theme: this.theme,
        lightAppearance: this.lightAppearance,
        wallpaperResource: (themeId: string): Resource => this.wallpaperResource(themeId),
        mapPreviewResource: (): Resource => this.mapPreviewResource(),
        onAppSurfaceChange: (surfaceId: string, area: Area | undefined, attached: boolean): void =>
          this.onAppSurfaceChange(surfaceId, area, attached),
        onMapSurfaceChange: (surfaceId: string, area: Area | undefined, attached: boolean): void =>
          this.onMapSurfaceChange(surfaceId, area, attached),
        onTouchAreaChange: (
          group: string, key: string, area: Area, action: () => void, longPress?: () => void,
          drag?: (pointX: number) => void
        ): void => this.onTouchAreaChange(group, key, area, action, longPress, drag),
        onTouchBoundsChange: (group: string, area: Area): void => this.onTouchBoundsChange(group, area),
        onToggleAppDisplay: (): void => this.onToggleAppDisplay(),
        onToggleMapDisplay: (): void => this.onToggleMapDisplay(),
        onOpenMediaApp: (): void => this.onOpenMediaApp(),
        onOpenMapApp: (): void => this.onOpenMapApp(),
        onSendMediaCommand: (command: ProjectionMediaCommand): void => this.onSendMediaCommand(command)
      })
      if (this.dashboardView === 'apps') {
        ProjectionAppsPage({
          apps: this.visibleApps(),
          gridColumns: this.appsGridColumns,
          gridTemplate: this.appsGridTemplate,
          panelColor: this.glassPanelColor,
          panelStrokeColor: this.glassStrokeColor,
          primaryTextColor: this.primaryTextColor,
          secondaryTextColor: this.secondaryTextColor,
          accent: this.accent,
          onAppClick: (app: ProjectionApp): void => this.onSelectApp(app),
          onTouchAreaChange: (key: string, area: Area, action: () => void): void =>
            this.onTouchAreaChange('grid', key, area, action),
          onGridAreaChange: (area: Area): void => this.onGridAreaChange(area),
          onScrollerReady: (scroller: Scroller): void => this.onAppsScrollerReady(scroller)
        })
      } else if (this.dashboardView === 'settings') {
        this.settingsPage()
      } else if (this.dashboardView === 'themes') {
        ProjectionThemesPage({
          theme: this.theme,
          accent: this.accent,
          primaryTextColor: this.primaryTextColor,
          secondaryTextColor: this.secondaryTextColor,
          mapBackgroundColor: this.mapBackgroundColor,
          panelColor: this.glassPanelColor,
          strokeColor: this.glassStrokeColor,
          wallpaperResource: (themeId: string): Resource => this.wallpaperResource(themeId),
          onThemeChange: (themeId: string): void => this.onThemeChange(themeId),
          onAccentChange: (color: string): void => this.onAccentChange(color),
          onTouchAreaChange: (key: string, area: Area, action: () => void): void =>
            this.onTouchAreaChange('themes', key, area, action),
          onScrollerReady: (scroller: Scroller): void => this.onThemesScrollerReady(scroller),
          onBoundsChange: (area: Area): void => this.onTouchBoundsChange('themes', area)
        })
      } else if (this.dashboardView === 'maps' || this.dashboardView === 'music') {
        ProjectionDockMenu({
          dashboardView: this.dashboardView,
          apps: this.apps,
          selectedMapUri: this.selectedMapUri,
          selectedMusicUri: this.selectedMusicUri,
          mediaBundleName: this.mediaState.bundleName ?? '',
          activeAppLabel: this.activeAppLabel,
          activeAppUri: this.activeAppUri,
          activeAppOnPhone: this.appOnPhone,
          mapAppLabel: this.mapAppLabel,
          mapAppUri: this.mapAppUri,
          mapOnPhone: this.mapOnPhone,
          dockActionMessage: this.dockActionMessage,
          accent: this.accent,
          primaryTextColor: this.primaryTextColor,
          secondaryTextColor: this.secondaryTextColor,
          glassSecondaryColor: this.glassSecondaryColor,
          glassPanelColor: this.glassPanelColor,
          glassStrokeColor: this.glassStrokeColor,
          cardStrokeColor: this.cardStrokeColor,
          onHome: (): void => this.onHomeClick(),
          onSelectApp: (app: ProjectionApp): void => this.onSelectApp(app),
          onToggleAppDisplay: (): void => this.onToggleAppDisplay(),
          onToggleMapDisplay: (): void => this.onToggleMapDisplay(),
          onTouchAreaChange: (group: string, key: string, area: Area, action: () => void): void =>
            this.onTouchAreaChange(group, key, area, action),
          onBoundsChange: (area: Area): void => this.onDockMenuBoundsChange(area),
          onScrollerReady: (scroller: Scroller): void => this.onDockMenuScrollerReady(scroller)
        })
      }
    }
    .layoutWeight(1)
    .width(this.verticalDock ? '0%' : '100%')
    .height(this.verticalDock ? '100%' : '0%')
  }
}
