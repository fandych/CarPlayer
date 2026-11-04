export interface ProjectionMapSurface {
  surfaceId: string;
  left: number;
  top: number;
  width: number;
  height: number;
}

export interface ProjectionSurfaceSize {
  width: number;
  height: number;
}

export function projectionSurfaceSize(
  width: number, height: number, landscape: boolean
): ProjectionSurfaceSize {
  if (!Number.isFinite(width) || !Number.isFinite(height) || width <= 0 || height <= 0) {
    throw new Error('Invalid projection surface size');
  }
  return {
    width,
    height: landscape && height >= width ? width * 9 / 16 : height
  };
}
