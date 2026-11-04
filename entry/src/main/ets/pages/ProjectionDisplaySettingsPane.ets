import {
  ProjectionCalibrationControl,
  ProjectionDisplayMode,
  ProjectionSafeInsetEdge,
  ProjectionSplitPane
} from '../video/ProjectionSettings';
import { ProjectionSettingsDropdown } from './ProjectionSettingsDropdown';

@Component
export struct ProjectionDisplaySettingsPane {
  @Prop dayNightMode: string = 'NIGHT';
  @Prop nightMode: boolean = false;
  @Prop displayBrightness: number = 80;
  @Prop splitMapRatio: number = 3;
  @Prop splitMusicRatio: number = 2;
  @Prop splitMapRatioInput: string = '3';
  @Prop splitMusicRatioInput: string = '2';
  @Prop splitRatioMessage: string = '';
  @Prop dockPosition: string = 'left';
  @Prop vehicleDisplayUuid: string = '';
  @Prop safeInsetTop: number = 0;
  @Prop safeInsetRight: number = 0;
  @Prop safeInsetBottom: number = 0;
  @Prop safeInsetLeft: number = 0;
  @Prop contentScalePercent: number = 100;
  @Prop contentOffsetXPercent: number = 0;
  @Prop contentOffsetYPercent: number = 0;
  @Prop calibrationMessage: string = '';
  @Prop projectionModeOptions: ProjectionDisplayMode[] = [];
  @Prop selectedProjectionModeId: string = 'receiver-native';
  @Prop activeProjectionModeId: string = '';
  @Prop projectionResolutionMessage: string = '';
  @Prop resolutionSelectionMessage: string = '';
  @Prop projectionNativeWidth: number = 0;
  @Prop projectionNativeHeight: number = 0;
  @Prop activeSettingsDropdown: string = '';
  @Prop accent: string = '#0A84FF';
  @Prop primaryTextColor: string = '#FFFFFF';
  @Prop secondaryTextColor: string = '#9EFFFFFF';
  @Prop mutedTextColor: string = '#80FFFFFF';
  @Prop mapBackgroundColor: string = '#1D2230';
  @Prop glassSecondaryColor: string = '#14FFFFFF';
  @Prop glassPanelColor: string = '#75262630';
  @Prop glassGroupColor: string = '#14FFFFFF';
  @Prop glassStrokeColor: string = '#38FFFFFF';
  @Prop settingsSeparatorColor: string = '#1FFFFFFF';
  onDayNightModeChange: (mode: 'AUTO' | 'DAY' | 'NIGHT') => void = (_mode: 'AUTO' | 'DAY' | 'NIGHT'): void => {};
  onBrightnessChange: (value: number) => void = (_value: number): void => {};
  onBrightnessTouch: (pointX: number, area: Area) => void = (_pointX: number, _area: Area): void => {};
  onSplitRatioAdjust: (pane: ProjectionSplitPane, delta: number) => void =
    (_pane: ProjectionSplitPane, _delta: number): void => {};
  onSplitRatioInputChange: (pane: ProjectionSplitPane, value: string) => void =
    (_pane: ProjectionSplitPane, _value: string): void => {};
  onSplitRatioRestore: (pane: ProjectionSplitPane) => void = (_pane: ProjectionSplitPane): void => {};
  onSplitRatioFocus: (pane: ProjectionSplitPane) => void = (_pane: ProjectionSplitPane): void => {};
  onDockPositionToggle: () => void = (): void => {};
  onSafeInsetAdjust: (edge: ProjectionSafeInsetEdge, delta: number) => void =
    (_edge: ProjectionSafeInsetEdge, _delta: number): void => {};
  onContentCalibrationAdjust: (control: ProjectionCalibrationControl, delta: number) => void =
    (_control: ProjectionCalibrationControl, _delta: number): void => {};
  onDropdownToggle: (key: string) => void = (_key: string): void => {};
  onDropdownSelect: (key: string, index: number) => void = (_key: string, _index: number): void => {};
  onTouchAreaChange: (
    key: string, area: Area, action: () => void, longPress?: () => void, drag?: (pointX: number) => void
  ) => void = (_key: string, _area: Area, _action: () => void, _longPress?: () => void,
    _drag?: (pointX: number) => void): void => {};
  onContentAreaChange: (area: Area) => void = (_area: Area): void => {};
  onScrollerReady: (scroller: Scroller) => void = (_scroller: Scroller): void => {};
  private readonly scroller: Scroller = new Scroller();

  aboutToAppear(): void {
    this.onScrollerReady(this.scroller);
  }

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

  @Builder
  private SplitRatioControl(pane: ProjectionSplitPane) {
    Row({ space: 4 }) {
      Button({ type: ButtonType.Normal }) {
        Text('−').fontSize(26).fontWeight(FontWeight.Bold).fontColor(this.primaryTextColor)
      }
        .width(42).height(42).padding(0)
        .backgroundColor(this.glassSecondaryColor).borderRadius(10)
        .accessibilityText(pane === 'map' ? '减少地图比例' : '减少音乐比例')
        .onClick((): void => this.onSplitRatioAdjust(pane, -1))
        .onAreaChange((_oldArea, newArea) => this.onTouchAreaChange(
          `splitRatio-${pane}-minus`, newArea, (): void => this.onSplitRatioAdjust(pane, -1)))
      TextInput({
        text: pane === 'map' ? this.splitMapRatioInput : this.splitMusicRatioInput,
        placeholder: pane === 'map' ? '3' : '2'
      })
        .id(pane === 'map' ? 'projectionMapSplitRatio' : 'projectionMusicSplitRatio')
        .type(InputType.Number)
        .width(52).height(40)
        .fontColor(this.primaryTextColor)
        .placeholderColor(this.secondaryTextColor)
        .backgroundColor(this.glassSecondaryColor)
        .borderRadius(10)
        .textAlign(TextAlign.Center)
        .onChange((value: string): void => this.onSplitRatioInputChange(pane, value))
        .onBlur((): void => this.onSplitRatioRestore(pane))
        .onSubmit((): void => this.onSplitRatioRestore(pane))
        .onAreaChange((_oldArea, newArea) => this.onTouchAreaChange(
          `splitRatio-${pane}-input`, newArea, (): void => this.onSplitRatioFocus(pane)))
      Button({ type: ButtonType.Normal }) {
        Text('+').fontSize(26).fontWeight(FontWeight.Bold).fontColor(this.primaryTextColor)
      }
        .width(42).height(42).padding(0)
        .backgroundColor(this.glassSecondaryColor).borderRadius(10)
        .accessibilityText(pane === 'map' ? '增加地图比例' : '增加音乐比例')
        .onClick((): void => this.onSplitRatioAdjust(pane, 1))
        .onAreaChange((_oldArea, newArea) => this.onTouchAreaChange(
          `splitRatio-${pane}-plus`, newArea, (): void => this.onSplitRatioAdjust(pane, 1)))
    }
  }

  build() {
    Scroll(this.scroller) {
      Column({ space: 16 }) {
        Text('显示').fontSize(26).fontWeight(FontWeight.Bold).fontColor(this.primaryTextColor)
        Column() {
          Row({ space: 14 }) {
            Text('外观').fontSize(14).fontColor(this.primaryTextColor).layoutWeight(1)
            Row({ space: 4 }) {
              Button({ type: ButtonType.Normal }) {
                Text('深色').fontSize(12).fontColor(
                  this.dayNightMode === 'NIGHT' || (this.dayNightMode === 'AUTO' && this.nightMode)
                    ? this.mapBackgroundColor : this.secondaryTextColor)
              }
              .height(42).padding({ left: 9, right: 9 }).borderRadius(9)
              .backgroundColor(this.dayNightMode === 'NIGHT' ||
                (this.dayNightMode === 'AUTO' && this.nightMode)
                ? this.primaryTextColor : Color.Transparent)
              .onClick((): void => this.onDayNightModeChange('NIGHT'))
              .onAreaChange((_oldArea, newArea) => this.onTouchAreaChange(
                'appearanceNight', newArea, (): void => this.onDayNightModeChange('NIGHT')))
              Button({ type: ButtonType.Normal }) {
                Text('浅色').fontSize(12).fontColor(
                  this.dayNightMode === 'DAY' || (this.dayNightMode === 'AUTO' && !this.nightMode)
                    ? this.mapBackgroundColor : this.secondaryTextColor)
              }
              .height(42).padding({ left: 9, right: 9 }).borderRadius(9)
              .backgroundColor(this.dayNightMode === 'DAY' ||
                (this.dayNightMode === 'AUTO' && !this.nightMode)
                ? this.primaryTextColor : Color.Transparent)
              .onClick((): void => this.onDayNightModeChange('DAY'))
              .onAreaChange((_oldArea, newArea) => this.onTouchAreaChange(
                'appearanceDay', newArea, (): void => this.onDayNightModeChange('DAY')))
            }
          }
          .height(68).padding(12)
          Row({ space: 14 }) {
            Column({ space: 3 }) {
              Text('亮度').fontSize(14).fontColor(this.primaryTextColor)
              Text(`${Math.round(this.displayBrightness)}%`).fontSize(12).fontColor(this.secondaryTextColor)
            }
            .width(72).alignItems(HorizontalAlign.Start)
            Slider({ value: this.displayBrightness, min: 20, max: 100, step: 1 })
              .layoutWeight(1)
              .blockColor('#FFFFFFFF')
              .selectedColor('#66787880')
              .trackColor('#66787880')
              .onChange((value: number): void => this.onBrightnessChange(value))
              .accessibilityText('亮度')
              .onAreaChange((_oldArea, newArea) => this.onTouchAreaChange(
                'displayBrightness',
                newArea,
                (): void => {},
                undefined,
                (pointX: number): void => this.onBrightnessTouch(pointX, newArea)))
          }
          .height(68).padding(12)
          .border({ width: { top: 1 }, color: this.settingsSeparatorColor })
          Row({ space: 10 }) {
            Column({ space: 3 }) {
              Text('分屏比例').fontSize(14).fontColor(this.primaryTextColor)
              Text(this.splitRatioMessage || '地图 : 音乐 · 每项 1–10')
                .fontSize(11).fontColor(this.splitRatioMessage ? '#FF9F0A' : this.secondaryTextColor)
            }
            .layoutWeight(1).alignItems(HorizontalAlign.Start)
            Row({ space: 4 }) {
              this.SplitRatioControl('map')
              Text(':').fontSize(14).fontColor(this.secondaryTextColor)
              this.SplitRatioControl('music')
            }
          }
          .height(68).padding(12)
          .border({ width: { top: 1 }, color: this.settingsSeparatorColor })
        }
        .width('100%')
        .borderRadius(18)
        .backgroundColor(this.glassGroupColor)
        .border({ width: 1, color: this.glassStrokeColor })

        Row({ space: 14 }) {
          Column({ space: 3 }) {
            Text('Dock 位置').fontSize(14).fontColor(this.primaryTextColor)
            Text(this.dockPosition === 'bottom' ? '底部' : '左侧')
              .fontSize(12).fontColor(this.secondaryTextColor)
          }
          .layoutWeight(1)
          Button(this.dockPosition === 'bottom' ? '切换到左侧' : '切换到底部')
            .height(44)
            .fontColor(this.primaryTextColor)
            .backgroundColor(this.glassSecondaryColor)
            .borderRadius(12)
            .onClick((): void => this.onDockPositionToggle())
            .onAreaChange((_oldArea, newArea) => this.onTouchAreaChange(
              'dockPosition', newArea, (): void => this.onDockPositionToggle()))
        }
        .height(68).padding(12).borderRadius(16).backgroundColor(this.glassGroupColor)
        .border({ width: 1, color: this.glassStrokeColor })

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

        Column() {
          ProjectionSettingsDropdown({
            label: '投屏分辨率',
            dropdownKey: 'projectionResolution',
            options: this.projectionModeOptions.length > 0
              ? this.projectionModeOptions.map((mode: ProjectionDisplayMode): string => mode.label)
              : ['暂无可用档位'],
            selectedIndex: Math.max(0, this.projectionModeOptions.findIndex(
              (mode: ProjectionDisplayMode): boolean => mode.id === this.selectedProjectionModeId
            )),
            controlEnabled: this.projectionModeOptions.length > 1,
            expanded: this.activeSettingsDropdown === 'projectionResolution',
            accent: this.accent,
            primaryTextColor: this.primaryTextColor,
            secondaryTextColor: this.secondaryTextColor,
            glassStrokeColor: this.glassStrokeColor,
            glassSecondaryColor: this.glassSecondaryColor,
            glassPanelColor: this.glassPanelColor,
            settingsSeparatorColor: this.settingsSeparatorColor,
            onToggle: (): void => this.onDropdownToggle('projectionResolution'),
            onSelect: (index: number): void => this.onDropdownSelect('projectionResolution', index),
            onTouchAreaChange: (key: string, area: Area, action: () => void): void =>
              this.onTouchAreaChange(key, area, action)
          })
        }
        .width('100%').borderRadius(16)
        .backgroundColor(this.glassGroupColor)
        .border({ width: 1, color: this.glassStrokeColor })

        Text(this.resolutionSelectionMessage || this.projectionResolutionMessage ||
          (this.projectionModeOptions.length > 1
            ? `车机原生 ${this.projectionNativeWidth}×${this.projectionNativeHeight}；档位按显示 UUID 独立保存`
            : `车机原生 ${this.projectionNativeWidth}×${this.projectionNativeHeight}；当前无其它已验证档位`))
          .fontSize(12).fontColor(this.secondaryTextColor).width('100%').maxLines(2)
      }
      .width('100%').padding(16)
    }
    .layoutWeight(1).width('0%').height('100%')
    .backgroundColor(Color.Transparent)
    .onAreaChange((_oldArea, newArea) => this.onContentAreaChange(newArea))
  }
}
