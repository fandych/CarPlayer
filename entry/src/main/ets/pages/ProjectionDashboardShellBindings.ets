import { ProjectionMediaCommand } from '../session/MediaSessionBridge';
import {
  ProjectionSplitPane, ProjectionSafeInsetEdge, ProjectionCalibrationControl, projectionTheme
} from '../video/ProjectionSettings';
import { ProjectionApp } from './ProjectionAppCatalog';
import { ProjectionDashboardState } from './ProjectionDashboardState';
import { ProjectionDashboardSettingsController } from './ProjectionDashboardSettingsController';
import { ProjectionDashboardAppController } from './ProjectionDashboardAppController';
import { ProjectionDashboardTouchController } from './ProjectionDashboardTouchController';
import { ProjectionDashboardMediaController } from './ProjectionDashboardMediaController';
import { ProjectionDashboardPresentationController } from './ProjectionDashboardPresentationController';

export function projectionDashboardShellBindings(
  state: ProjectionDashboardState,
  app: ProjectionDashboardAppController,
  touch: ProjectionDashboardTouchController,
  media: ProjectionDashboardMediaController,
  presentation: ProjectionDashboardPresentationController,
  settings: ProjectionDashboardSettingsController
) {
  return {
    theme: state.theme,
    accent: state.accent,
    dayNightMode: state.dayNightMode,
    nightMode: state.nightMode,
    dockPosition: state.dockPosition,
    dashboardView: state.dashboardView,
    preserveSplitSurfaceForOverlays: state.preserveSplitSurfaceForOverlays,
    settingsTab: state.settingsTab,
    activeSettingsDropdown: state.activeSettingsDropdown,
    displayBrightness: state.displayBrightness,
    splitMapRatio: state.splitMapRatio,
    splitMusicRatio: state.splitMusicRatio,
    splitMapRatioInput: state.splitMapRatioInput,
    splitMusicRatioInput: state.splitMusicRatioInput,
    splitRatioMessage: state.splitRatioMessage,
    selectedMapUri: state.selectedMapUri,
    selectedMusicUri: state.selectedMusicUri,
    apps: state.apps,
    appsGridColumns: state.appsGridColumns,
    appsGridTemplate: app.appsGridTemplate(state),
    activeAppLabel: state.activeAppLabel,
    activeAppUri: state.activeAppUri,
    appOnPhone: state.appOnPhone,
    mapAppLabel: state.mapAppLabel,
    mapAppUri: state.mapAppUri,
    mapOnPhone: state.mapOnPhone,
    navigationPreview: state.navigationPreview,
    launchMessage: state.launchMessage,
    mapMessage: state.mapMessage,
    mediaState: state.mediaState,
    dockActionMessage: state.dockActionMessage,
    dockHint: state.dockHint,
    batteryPercent: state.batteryPercent,
    signalLevel: state.signalLevel,
    networkLabel: state.networkLabel,
    dockIconSize: state.dockIconSize,
    deviceDisplayUuid: state.vehicleDisplayUuid,
    safeInsetTop: state.safeInsetTop,
    safeInsetRight: state.safeInsetRight,
    safeInsetBottom: state.safeInsetBottom,
    safeInsetLeft: state.safeInsetLeft,
    contentScalePercent: state.contentScalePercent,
    contentOffsetXPercent: state.contentOffsetXPercent,
    contentOffsetYPercent: state.contentOffsetYPercent,
    calibrationMessage: state.calibrationMessage,
    projectionModeOptions: state.projectionModeOptions,
    selectedProjectionModeId: state.selectedProjectionModeId,
    activeProjectionModeId: state.activeProjectionModeId,
    projectionResolutionMessage: state.projectionResolutionMessage,
    resolutionSelectionMessage: state.resolutionSelectionMessage,
    projectionNativeWidth: state.projectionNativeWidth,
    projectionNativeHeight: state.projectionNativeHeight,
    useBluetoothAudio: state.useBluetoothAudio,
    encoderFps: state.encoderFps,
    captureFps: state.captureFps,
    activeEncoderFps: state.activeEncoderFps,
    activeCaptureFps: state.activeCaptureFps,
    receiverHomeMessage: state.receiverHomeMessage,
    viewAreaOriginX: state.viewAreaOriginX,
    viewAreaOriginY: state.viewAreaOriginY,
    primaryTextColor: presentation.primaryTextColor(state),
    secondaryTextColor: presentation.secondaryTextColor(state),
    mutedTextColor: presentation.mutedTextColor(state),
    mapBackgroundColor: presentation.mapBackgroundColor(state),
    glassStrokeColor: presentation.glassStrokeColor(state),
    cardStrokeColor: presentation.cardStrokeColor(state),
    glassSecondaryColor: presentation.glassSecondaryColor(state),
    glassPanelColor: presentation.glassPanelColor(state),
    glassSurfaceColor: presentation.glassSurfaceColor(state),
    settingsPanelColor: presentation.settingsPanelColor(state),
    settingsGroupColor: presentation.settingsGroupColor(state),
    settingsSeparatorColor: presentation.settingsSeparatorColor(state),
    lightAppearance: presentation.isLightAppearance(state),
    themeBackgroundColor: projectionTheme(state.theme).background,
    dockItems: app.dockItems(state),
    verticalDock: state.dockPosition !== 'bottom',
    wallpaperResource: (themeId: string): Resource => presentation.wallpaperResource(themeId),
    mapPreviewResource: (): Resource => presentation.mapPreviewResource(state),
    dockIconResource: (icon: string, selected: boolean): Resource =>
      presentation.dockIconResource(state, icon, selected),
    settingsIconResource: (lightIcon: string, darkIcon: string, selected: boolean = false): Resource =>
      presentation.settingsIconResource(state, lightIcon, darkIcon, selected),
    onSettingsTabChange: (tab: string): void => { state.settingsTab = tab; },
    onDockAction: (id: string, longPress: boolean): void => app.activateDock(state, id, longPress),
    onDockHintChange: (hint: string): void => { state.dockHint = hint; },
    onThemeChange: (themeId: string): void => { state.theme = themeId; },
    onAccentChange: (color: string): void => { state.accent = color; },
    onDockMenuBoundsChange: (area: Area): void => {
      const bounds = touch.areaBounds(area);
      state.touchRouter.touchBounds.set('maps', bounds);
      state.touchRouter.touchBounds.set('music', bounds);
    },
    onSelectApp: (selectedApp: ProjectionApp): void => app.selectApp(state, selectedApp),
    onAppSurfaceChange: (surfaceId: string, area: Area | undefined, attached: boolean): void =>
      touch.handleAppSurfaceChange(state, surfaceId, area, attached),
    onMapSurfaceChange: (surfaceId: string, area: Area | undefined, attached: boolean): void =>
      touch.handleMapSurfaceChange(state, surfaceId, area, attached),
    onTouchAreaChange: (
      group: string, key: string, area: Area, action: () => void, longPress?: () => void,
      drag?: (pointX: number) => void
    ): void => touch.updateTouchArea(state, group, key, area, action, longPress, drag),
    onTouchBoundsChange: (group: string, area: Area): void => {
      state.touchRouter.touchBounds.set(group, touch.areaBounds(area));
    },
    onToggleAppDisplay: (): void => state.onToggleAppDisplay(),
    onToggleMapDisplay: (): void => state.onToggleMapDisplay(),
    onHomeClick: (): void => app.showDashboardView(state, 'home'),
    onOpenMediaApp: (): void => app.openMediaApp(state),
    onOpenMapApp: (): void => app.openMapApp(state),
    onSendMediaCommand: (command: ProjectionMediaCommand): void => { void media.sendMediaCommand(state, command); },
    onDayNightModeChange: (mode: 'AUTO' | 'DAY' | 'NIGHT'): void =>
      settings.selectDayNightMode(state, mode),
    onBrightnessChange: (value: number): void => settings.updateDisplayBrightness(state, value),
    onBrightnessTouch: (pointX: number, area: Area): void =>
      touch.setDisplayBrightnessFromTouch(state, settings, pointX, touch.areaBounds(area)),
    onSplitRatioAdjust: (pane: ProjectionSplitPane, delta: number): void =>
      settings.adjustSplitRatio(state, pane, delta),
    onSplitRatioInputChange: (pane: ProjectionSplitPane, value: string): void =>
      settings.updateSplitRatioInput(state, pane, value),
    onSplitRatioRestore: (pane: ProjectionSplitPane): void => settings.restoreSplitRatioInput(state, pane),
    onSplitRatioFocus: (pane: ProjectionSplitPane): void =>
      state.getUIContext().getFocusController().requestFocus(
        pane === 'map' ? 'projectionMapSplitRatio' : 'projectionMusicSplitRatio'),
    onDockPositionToggle: (): void => app.toggleDockPosition(state),
    onSafeInsetAdjust: (edge: ProjectionSafeInsetEdge, delta: number): void =>
      settings.adjustSafeInset(state, edge, delta),
    onContentCalibrationAdjust: (control: ProjectionCalibrationControl, delta: number): void =>
      settings.adjustContentCalibration(state, control, delta),
    onDropdownToggle: (key: string): void => {
      const previousKey = state.activeSettingsDropdown;
      state.activeSettingsDropdown = previousKey === key ? '' : key;
      if (previousKey.length > 0) {
        clearSettingsDropdownAreas(state, previousKey);
      }
    },
    onDropdownSelect: (key: string, index: number): void => {
      const select = (selectedIndex: number): void => {
        if (key === 'projectionResolution') {
          const mode = state.projectionModeOptions[selectedIndex];
          if (mode) {
            settings.selectProjectionResolution(state, mode.id);
          }
        } else if (key === 'encoderFps') {
          settings.selectEncoderFps(state, selectedIndex);
        } else {
          settings.selectCaptureFps(state, selectedIndex);
        }
      };
      select(index);
      if (state.activeSettingsDropdown === key) {
        state.activeSettingsDropdown = '';
      }
      clearSettingsDropdownAreas(state, key);
    },
    onProjectionContentAreaChange: (area: Area): void => {
      state.touchRouter.touchBounds.set('settingsContent', touch.areaBounds(area));
    },
    onDockScrollerReady: (scroller: Scroller): void => { state.dockScroller = scroller; },
    onAppsScrollerReady: (scroller: Scroller): void => { state.appsScroller = scroller; },
    onDockMenuScrollerReady: (scroller: Scroller): void => { state.dockMenuScroller = scroller; },
    onSettingsScrollerReady: (scroller: Scroller): void => { state.settingsScroller = scroller; },
    onThemesScrollerReady: (scroller: Scroller): void => { state.themesScroller = scroller; },
    onGridAreaChange: (area: Area): void => {
      state.touchRouter.touchBounds.set('grid', touch.areaBounds(area));
      app.updateAppsGridColumns(state, Number.parseFloat(`${area.width}`));
    },
    onViewportAreaChange: (area: Area): void => {
      const height = Number.parseFloat(`${area.height}`);
      state.projectionViewportWidth = Math.max(0, Number.parseFloat(`${area.width}`) - 16);
      state.projectionViewportHeight = Math.max(0, height - 16);
      state.dockIconSize = state.dockPosition === 'bottom'
        ? Math.max(18, Math.min(30, height / 20))
        : Math.max(16, Math.min(30, (height - 100) / 5));
    },
    onEncoderFpsSelect: (index: number): void => settings.selectEncoderFps(state, index),
    onCaptureFpsSelect: (index: number): void => settings.selectCaptureFps(state, index),
    onBluetoothAudioChange: (enabled: boolean): void => { state.useBluetoothAudio = enabled; }
  };
}

function clearSettingsDropdownAreas(state: ProjectionDashboardState, key: string): void {
  const prefix = `settings:dropdown-${key}-option-`;
  for (const areaKey of state.touchRouter.touchAreas.keys()) {
    if (areaKey.startsWith(prefix)) {
      state.touchRouter.touchAreas.delete(areaKey);
    }
  }
}
