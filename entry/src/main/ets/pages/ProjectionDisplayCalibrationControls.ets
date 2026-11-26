import { ProjectionCalibrationControl, ProjectionSafeInsetEdge } from '../video/ProjectionSettings';

@Component
export struct ProjectionDisplayCalibrationControls {
  @Prop vehicleDisplayUuid: string = '';
  @Prop safeInsetTop: number = 0;
  @Prop safeInsetRight: number = 0;
  @Prop safeInsetBottom: number = 0;
  @Prop safeInsetLeft: number = 0;
  @Prop contentScalePercent: number = 100;
  @Prop contentOffsetXPercent: number = 0;
  @Prop contentOffsetYPercent: number = 0;
  @Prop calibrationMessage: string = '';
  @Prop primaryTextColor: string = '#FFFFFF';
  @Prop secondaryTextColor: string = '#9EFFFFFF';
  @Prop glassSecondaryColor: string = '#14FFFFFF';
  @Prop glassGroupColor: string = '#14FFFFFF';
  @Prop glassStrokeColor: string = '#38FFFFFF';
  onSafeInsetAdjust: (edge: ProjectionSafeInsetEdge, delta: number) => void =
    (_edge: ProjectionSafeInsetEdge, _delta: number): void => {};
  onContentCalibrationAdjust: (control: ProjectionCalibrationControl, delta: number) => void =
    (_control: ProjectionCalibrationControl, _delta: number): void => {};
  onTouchAreaChange: (
    key: string, area: Area, action: () => void, longPress?: () => void, drag?: (pointX: number) => void
  ) => void = (_key: string, _area: Area, _action: () => void, _longPress?: () => void,
    _drag?: (pointX: number) => void): void => {};

  @Builder
  private SafeInsetRow(label: string, edge: ProjectionSafeInsetEdge) {
    Row({ space: 8 }) {
      Text(label).fontSize(13).fontColor(this.primaryTextColor).layoutWeight(1)
      Button('−')
        .width(40).height(40).fontColor(this.primaryTextColor)
        .backgroundColor(this.glassSecondaryColor).borderRadius(12)
        .onClick((): void => this.onSafeInsetAdjust(edge, -1))
        .onAreaChange((_oldArea, newArea) => this.onTouchAreaChange(
          `safe-${edge}-minus`, newArea, (): void => this.onSafeInsetAdjust(edge, -1)))
      Text(`${edge === 'top' ? this.safeInsetTop : edge === 'right' ? this.safeInsetRight :
        edge === 'bottom' ? this.safeInsetBottom : this.safeInsetLeft}%`)
        .fontSize(13).fontColor(this.primaryTextColor).width(42).textAlign(TextAlign.Center)
      Button('+')
        .width(40).height(40).fontColor(this.primaryTextColor)
        .backgroundColor(this.glassSecondaryColor).borderRadius(12)
        .onClick((): void => this.onSafeInsetAdjust(edge, 1))
        .onAreaChange((_oldArea, newArea) => this.onTouchAreaChange(
          `safe-${edge}-plus`, newArea, (): void => this.onSafeInsetAdjust(edge, 1)))
    }
    .width('100%')
    .height(46)
  }

  @Builder
  private CalibrationControlRow(label: string, control: ProjectionCalibrationControl) {
    Row({ space: 8 }) {
      Text(label).fontSize(13).fontColor(this.primaryTextColor).layoutWeight(1)
      Button('−')
        .width(40).height(40).fontColor(this.primaryTextColor)
        .backgroundColor(this.glassSecondaryColor).borderRadius(12)
        .onClick((): void => this.onContentCalibrationAdjust(control, -1))
        .onAreaChange((_oldArea, newArea) => this.onTouchAreaChange(
          `calibration-${control}-minus`, newArea,
          (): void => this.onContentCalibrationAdjust(control, -1)))
      Text(`${control === 'scale' ? this.contentScalePercent :
        control === 'offsetX' ? this.contentOffsetXPercent : this.contentOffsetYPercent}%`)
        .fontSize(13).fontColor(this.primaryTextColor).width(46).textAlign(TextAlign.Center)
      Button('+')
        .width(40).height(40).fontColor(this.primaryTextColor)
        .backgroundColor(this.glassSecondaryColor).borderRadius(12)
        .onClick((): void => this.onContentCalibrationAdjust(control, 1))
        .onAreaChange((_oldArea, newArea) => this.onTouchAreaChange(
          `calibration-${control}-plus`, newArea,
          (): void => this.onContentCalibrationAdjust(control, 1)))
    }
    .width('100%')
    .height(46)
  }

  build() {
    Column({ space: 16 }) {
      Column({ space: 4 }) {
        Text(this.vehicleDisplayUuid.length > 0
          ? `显示安全边距 · ${this.vehicleDisplayUuid.slice(-8)}` : '显示安全边距 · 默认')
          .fontSize(14).fontColor(this.primaryTextColor)
        Text('按百分比避让遮挡区域；曲面轮廓仍需在目标车机校准')
          .fontSize(12).fontColor(this.secondaryTextColor).maxLines(2)
        this.SafeInsetRow('上', 'top')
        this.SafeInsetRow('右', 'right')
        this.SafeInsetRow('下', 'bottom')
        this.SafeInsetRow('左', 'left')
      }
      .width('100%').padding(14).borderRadius(16)
      .backgroundColor(this.glassGroupColor)
      .border({ width: 1, color: this.glassStrokeColor })

      Column({ space: 4 }) {
        Text(this.vehicleDisplayUuid.length > 0
          ? `异形屏内容校准 · ${this.vehicleDisplayUuid.slice(-8)}` : '异形屏内容校准')
          .fontSize(14).fontColor(this.primaryTextColor)
        Text('等比缩放与位置微调仅作用于 Shell 内容；输出分辨率和全屏背景保持不变')
          .fontSize(12).fontColor(this.secondaryTextColor).maxLines(2)
        this.CalibrationControlRow('内容缩放', 'scale')
        this.CalibrationControlRow('水平位置', 'offsetX')
        this.CalibrationControlRow('垂直位置', 'offsetY')
        Text(this.calibrationMessage || '缩放 70–100%；水平/垂直偏移各 ±15%，按显示 UUID 保存')
          .fontSize(10).fontColor(this.secondaryTextColor).maxLines(2)
      }
      .width('100%').padding(14).borderRadius(16)
      .backgroundColor(this.glassGroupColor)
      .border({ width: 1, color: this.glassStrokeColor })
    }
  }
}
