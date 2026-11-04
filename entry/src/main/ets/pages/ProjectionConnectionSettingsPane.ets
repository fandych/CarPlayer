import { ProjectionBatteryIndicator, ProjectionSignalIndicator } from './ProjectionDock';
import { ProjectionSettingsDropdown } from './ProjectionSettingsDropdown';

@Component
export struct ProjectionConnectionSettingsPane {
  @Prop useBluetoothAudio: boolean = false;
  @Prop networkLabel: string = '网络';
  @Prop signalLevel: number = 0;
  @Prop batteryPercent: number = 0;
  @Prop encoderFps: number = 30;
  @Prop captureFps: number = 60;
  @Prop activeSettingsDropdown: string = '';
  @Prop receiverHomeMessage: string = '';
  @Prop launchMessage: string = '';
  @Prop accent: string = '#0A84FF';
  @Prop primaryTextColor: string = '#FFFFFF';
  @Prop secondaryTextColor: string = '#9EFFFFFF';
  @Prop mutedTextColor: string = '#80FFFFFF';
  @Prop glassSecondaryColor: string = '#14FFFFFF';
  @Prop glassPanelColor: string = '#75262630';
  @Prop glassGroupColor: string = '#14FFFFFF';
  @Prop glassStrokeColor: string = '#38FFFFFF';
  @Prop settingsSeparatorColor: string = '#1FFFFFFF';
  settingsIconResource: (lightIcon: string, darkIcon: string, selected?: boolean) => Resource =
    (_lightIcon: string, _darkIcon: string, _selected?: boolean): Resource => $r('app.media.ic_car_front');
  onBluetoothAudioChange: (enabled: boolean) => void = (_enabled: boolean): void => {};
  onSelectEncoderFps: (index: number) => void = (_index: number): void => {};
  onSelectCaptureFps: (index: number) => void = (_index: number): void => {};
  onDropdownToggle: (key: string) => void = (_key: string): void => {};
  onDropdownSelect: (key: string, index: number) => void = (_key: string, _index: number): void => {};
  onTouchAreaChange: (key: string, area: Area, action: () => void) => void =
    (_key: string, _area: Area, _action: () => void): void => {};
  onContentAreaChange: (area: Area) => void = (_area: Area): void => {};
  onScrollerReady: (scroller: Scroller) => void = (_scroller: Scroller): void => {};
  private readonly scroller: Scroller = new Scroller();

  aboutToAppear(): void {
    this.onScrollerReady(this.scroller);
  }

  build() {
    Scroll(this.scroller) {
      Column({ space: 14 }) {
        Text('连接').fontSize(26).fontWeight(FontWeight.Bold).fontColor(this.primaryTextColor)
        Column() {
          Row({ space: 12 }) {
            Image(this.settingsIconResource('app.media.ic_car_front_light', 'app.media.ic_car_front'))
              .width(34).height(34).objectFit(ImageFit.Contain)
            Column({ space: 3 }) {
              Text('CarPlay').fontSize(15).fontWeight(FontWeight.Medium).fontColor(this.primaryTextColor)
              Text('车机投影连接').fontSize(12).fontColor(this.secondaryTextColor)
            }
            .layoutWeight(1).alignItems(HorizontalAlign.Start)
            Text('已连接').fontSize(13).fontColor('#32D74B')
          }
          .width('100%').height(64).padding(14)
          Row({ space: 12 }) {
            Column({ space: 3 }) {
              Text('蓝牙音频').fontSize(14).fontColor(this.primaryTextColor)
              Text(this.useBluetoothAudio ? '系统蓝牙音频路由' : '使用 CarPlay RTP 音频')
                .fontSize(12).fontColor(this.secondaryTextColor)
            }
            .layoutWeight(1).alignItems(HorizontalAlign.Start)
            Toggle({ type: ToggleType.Switch, isOn: this.useBluetoothAudio })
              .selectedColor('#32D74B')
              .onChange((enabled: boolean): void => this.onBluetoothAudioChange(enabled))
              .accessibilityText('使用蓝牙音频')
              .onAreaChange((_oldArea, newArea) => this.onTouchAreaChange(
                'bluetoothAudio', newArea,
                (): void => this.onBluetoothAudioChange(!this.useBluetoothAudio)))
          }
          .width('100%').height(64).padding(14)
          .border({ width: { top: 1 }, color: this.settingsSeparatorColor })
        }
        .width('100%').borderRadius(18).backgroundColor(this.glassGroupColor)
        .border({ width: 1, color: this.glassStrokeColor })

        Column() {
          Row({ space: 12 }) {
            Column({ space: 3 }) {
              Text('设备状态').fontSize(14).fontColor(this.primaryTextColor)
              Text(this.networkLabel).fontSize(12).fontColor(this.secondaryTextColor)
            }
            .layoutWeight(1).alignItems(HorizontalAlign.Start)
            ProjectionSignalIndicator({
              signalLevel: this.signalLevel,
              networkLabel: this.networkLabel,
              primaryTextColor: this.primaryTextColor,
              mutedTextColor: this.mutedTextColor
            })
            ProjectionBatteryIndicator({
              batteryPercent: this.batteryPercent,
              accent: this.accent,
              secondaryTextColor: this.secondaryTextColor
            })
          }
          .width('100%').height(64).padding(14)
          ProjectionSettingsDropdown({
            label: '投屏帧率 FPS',
            dropdownKey: 'encoderFps',
            options: ['30 fps', '60 fps'],
            selectedIndex: Math.max(0, [30, 60].indexOf(this.encoderFps)),
            controlEnabled: true,
            expanded: this.activeSettingsDropdown === 'encoderFps',
            accent: this.accent,
            primaryTextColor: this.primaryTextColor,
            secondaryTextColor: this.secondaryTextColor,
            glassStrokeColor: this.glassStrokeColor,
            glassSecondaryColor: this.glassSecondaryColor,
            glassPanelColor: this.glassPanelColor,
            settingsSeparatorColor: this.settingsSeparatorColor,
            onToggle: (): void => this.onDropdownToggle('encoderFps'),
            onSelect: (index: number): void => this.onDropdownSelect('encoderFps', index),
            onTouchAreaChange: (key: string, area: Area, action: () => void): void =>
              this.onTouchAreaChange(key, area, action)
          })
          ProjectionSettingsDropdown({
            label: '采集刷新率',
            dropdownKey: 'captureFps',
            options: ['30 Hz', '60 Hz'],
            selectedIndex: Math.max(0, [30, 60].indexOf(this.captureFps)),
            controlEnabled: true,
            expanded: this.activeSettingsDropdown === 'captureFps',
            accent: this.accent,
            primaryTextColor: this.primaryTextColor,
            secondaryTextColor: this.secondaryTextColor,
            glassStrokeColor: this.glassStrokeColor,
            glassSecondaryColor: this.glassSecondaryColor,
            glassPanelColor: this.glassPanelColor,
            settingsSeparatorColor: this.settingsSeparatorColor,
            onToggle: (): void => this.onDropdownToggle('captureFps'),
            onSelect: (index: number): void => this.onDropdownSelect('captureFps', index),
            onTouchAreaChange: (key: string, area: Area, action: () => void): void =>
              this.onTouchAreaChange(key, area, action)
          })
        }
        .width('100%').borderRadius(18).backgroundColor(this.glassGroupColor)
        .border({ width: 1, color: this.glassStrokeColor })
        Text(this.receiverHomeMessage || this.launchMessage).fontSize(11).fontColor(this.secondaryTextColor)
      }
      .width('100%').padding({ left: 36, right: 36, top: 28, bottom: 28 })
    }
    .layoutWeight(1).width('0%').height('100%')
    .backgroundColor(Color.Transparent)
    .onAreaChange((_oldArea, newArea) => this.onContentAreaChange(newArea))
  }
}
