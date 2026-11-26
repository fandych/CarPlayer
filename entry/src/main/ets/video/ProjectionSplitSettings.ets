import {
  PROJECTION_SPLIT_RATIO_MAX,
  PROJECTION_SPLIT_RATIO_MIN,
  ProjectionSplitPane
} from './ProjectionSettingsTypes';

export function normalizeProjectionSplitRatio(value: number, fallback: number = 3): number {
  const defaultValue = Number.isFinite(fallback)
    ? Math.max(PROJECTION_SPLIT_RATIO_MIN, Math.min(PROJECTION_SPLIT_RATIO_MAX, Math.round(fallback)))
    : 3;
  if (!Number.isFinite(value)) {
    return defaultValue;
  }
  return Math.max(PROJECTION_SPLIT_RATIO_MIN, Math.min(PROJECTION_SPLIT_RATIO_MAX, Math.round(value)));
}

export function readProjectionSplitRatio(pane: ProjectionSplitPane): number {
  const defaultValue = pane === 'map' ? 3 : 2;
  const key = pane === 'map' ? 'carplaySplitMapRatio' : 'carplaySplitMusicRatio';
  PersistentStorage.persistProp(key, defaultValue);
  return normalizeProjectionSplitRatio(AppStorage.get<number>(key) ?? defaultValue, defaultValue);
}

export function saveProjectionSplitRatio(pane: ProjectionSplitPane, value: number): number {
  const defaultValue = pane === 'map' ? 3 : 2;
  const key = pane === 'map' ? 'carplaySplitMapRatio' : 'carplaySplitMusicRatio';
  const ratio = normalizeProjectionSplitRatio(value, defaultValue);
  PersistentStorage.persistProp(key, defaultValue);
  AppStorage.setOrCreate(key, ratio);
  return ratio;
}
