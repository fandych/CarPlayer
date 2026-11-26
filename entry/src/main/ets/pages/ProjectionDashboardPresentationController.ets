import { projectionTheme, resolveNightMode } from '../video/ProjectionSettings';
import { ProjectionDashboardState } from './ProjectionDashboardState';

export class ProjectionDashboardPresentationController {
  isLightAppearance(state: ProjectionDashboardState): boolean {
    return !resolveNightMode(state.dayNightMode, state.nightMode);
  }

  private colorWithAlpha(color: string, alpha: string): string {
    return `#${alpha}${color.slice(1)}`;
  }

  primaryTextColor(state: ProjectionDashboardState): string {
    return this.isLightAppearance(state) ? '#1C1C1E' : '#FFFFFF';
  }

  secondaryTextColor(state: ProjectionDashboardState): string {
    return this.isLightAppearance(state) ? '#A63C3C43' : '#9EFFFFFF';
  }

  mutedTextColor(state: ProjectionDashboardState): string {
    return this.isLightAppearance(state) ? '#993C3C43' : '#80FFFFFF';
  }

  mapBackgroundColor(state: ProjectionDashboardState): string {
    return this.isLightAppearance(state) ? '#E9E7E1' : '#1D2230';
  }

  glassStrokeColor(state: ProjectionDashboardState): string {
    return this.isLightAppearance(state) ? '#BFFFFFFF' : '#38FFFFFF';
  }

  cardStrokeColor(state: ProjectionDashboardState): string {
    return this.isLightAppearance(state) ? '#243C3C43' : '#20FFFFFF';
  }

  glassSecondaryColor(state: ProjectionDashboardState): string {
    return this.isLightAppearance(state) ? '#0D000000' : '#14FFFFFF';
  }

  glassPanelColor(state: ProjectionDashboardState): string {
    return this.isLightAppearance(state) ? '#85FFFFFF' : this.colorWithAlpha(projectionTheme(state.theme).surface, '75');
  }

  glassSurfaceColor(state: ProjectionDashboardState): string {
    return this.isLightAppearance(state) ? '#B8FFFFFF' : this.colorWithAlpha(projectionTheme(state.theme).panel, '9E');
  }

  settingsPanelColor(state: ProjectionDashboardState): string {
    return this.glassPanelColor(state);
  }

  settingsGroupColor(state: ProjectionDashboardState): string {
    return this.glassSecondaryColor(state);
  }

  settingsSeparatorColor(state: ProjectionDashboardState): string {
    return this.isLightAppearance(state) ? '#243C3C43' : '#1FFFFFFF';
  }

  wallpaperResource(themeId: string, resolve: (resource: string) => Resource = $r): Resource {
    switch (themeId) {
      case 'sunset':
        return resolve('app.media.projection_sunset');
      case 'forest':
        return resolve('app.media.projection_forest');
      case 'ocean':
        return resolve('app.media.projection_ocean');
      case 'graphite':
        return resolve('app.media.projection_graphite');
      default:
        return resolve('app.media.projection_aurora');
    }
  }

  mapPreviewResource(state: ProjectionDashboardState,
    resolve: (resource: string) => Resource = $r): Resource {
    return this.isLightAppearance(state)
      ? resolve('app.media.projection_map_preview_light') : resolve('app.media.projection_map_preview');
  }

  dockIconResource(state: ProjectionDashboardState, icon: string, selected: boolean,
    resolve: (resource: string) => Resource = $r): Resource {
    if (!this.isLightAppearance(state) || selected) {
      return resolve(icon);
    }
    switch (icon) {
      case 'app.media.ic_house':
        return resolve('app.media.ic_house_light');
      case 'app.media.ic_layout_grid':
        return resolve('app.media.ic_layout_grid_light');
      case 'app.media.ic_navigation':
        return resolve('app.media.ic_navigation_light');
      case 'app.media.ic_music':
        return resolve('app.media.ic_music_light');
      case 'app.media.ic_split':
        return resolve('app.media.ic_split_light');
      case 'app.media.ic_settings':
        return resolve('app.media.ic_settings_light');
      default:
        return resolve(icon);
    }
  }

  settingsIconResource(state: ProjectionDashboardState, lightIcon: string, darkIcon: string,
    selected: boolean = false, resolve: (resource: string) => Resource = $r): Resource {
    return this.isLightAppearance(state) && !selected ? resolve(lightIcon) : resolve(darkIcon);
  }
}
