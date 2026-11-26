import { projectionSurfaceSize, ProjectionSurfaceSize } from './ProjectionSurface';

@Component
export struct ProjectionContentSurface {
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
