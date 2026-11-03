import abilityAccessCtrl from '@ohos.abilityAccessCtrl';
import common from '@ohos.app.ability.common';
import { InfoCard, SectionHeading } from './PageParts';

type RestrictedPermission =
  'ohos.permission.ACCESS_VIRTUAL_SCREEN' |
  'ohos.permission.MANAGE_MEDIA_RESOURCES_FOR_PUBLIC' |
  'ohos.permission.CUSTOM_SCREEN_CAPTURE';

@Component
export struct SettingsPage {
  @Prop isSessionActive: boolean = false;
  @Prop deviceName: string = '';
  @Prop bluetoothAddress: string = '';
  @Prop skipMfiChallengeVerification: boolean = false;
  @Prop trustedMfiFingerprints: string[] = [];
  @StorageLink('carplayUseBluetoothAudio') useBluetoothAudio: boolean = false;
  @State restrictedPermissionStatus: string[] = [];
  onDeviceNameChange: (value: string) => void = (_value: string): void => {};
  onBluetoothAddressChange: (value: string) => void = (_value: string): void => {};
  onSave: () => void = (): void => {};
  onSkipMfiChange: (enabled: boolean) => void = (_enabled: boolean): void => {};
  onRevokeFingerprint: (fingerprint: string) => void = (_fingerprint: string): void => {};

  aboutToAppear(): void {
    void this.refreshRestrictedPermissions();
  }

  private async refreshRestrictedPermissions(): Promise<void> {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const manager = abilityAccessCtrl.createAtManager();
      const tokenId = context.applicationInfo.accessTokenId;
      const permissions: RestrictedPermission[] = [
        'ohos.permission.ACCESS_VIRTUAL_SCREEN',
        'ohos.permission.MANAGE_MEDIA_RESOURCES_FOR_PUBLIC',
        'ohos.permission.CUSTOM_SCREEN_CAPTURE'
      ];
      const statuses: string[] = [];
      for (const permission of permissions) {
        try {
          const result = manager.checkAccessTokenSync(tokenId, permission);
          statuses.push(`${permission} · ${result === 0 ? '已授予' : '未授予/未审批'}`);
        } catch (error) {
          statuses.push(`${permission} · 状态读取失败：${error instanceof Error ? error.message : String(error)}`);
        }
      }
      this.restrictedPermissionStatus = statuses;
    } catch (error) {
      this.restrictedPermissionStatus = [
        `权限状态读取失败：${error instanceof Error ? error.message : String(error)}`
      ];
    }
  }

  build() {
    Scroll() {
      Column({ space: 18 }) {
        SectionHeading({
          title: '发送端身份',
          subtitle: '开启蓝牙监听无需填写；完整 CarPlay 会话需要真实蓝牙 MAC'
        })
        Column({ space: 12 }) {
          TextInput({ text: this.deviceName, placeholder: '设备名称' })
            .height(46)
            .fontColor('#FFFFFF')
            .placeholderColor('#FFFFFF70')
            .backgroundColor('#14FFFFFF')
            .borderRadius(14)
            .border({ width: 1, color: '#FFFFFF26' })
            .onChange((value: string) => this.onDeviceNameChange(value))
          TextInput({ text: this.bluetoothAddress, placeholder: '真实蓝牙 MAC，例如 AA:BB:CC:DD:EE:FF' })
            .height(46)
            .fontColor('#FFFFFF')
            .placeholderColor('#FFFFFF70')
            .backgroundColor('#14FFFFFF')
            .borderRadius(14)
            .border({ width: 1, color: '#FFFFFF26' })
            .onChange((value: string) => this.onBluetoothAddressChange(value))
          Text('系统占位地址 02:00:00:00:00:00 不可用于 CarPlay 身份。')
            .fontSize(12)
            .fontColor('#FFB36B')
          Button(this.isSessionActive ? '监听期间不能保存身份' : '保存身份')
            .width('100%')
            .height(44)
            .fontColor('#FFFFFF')
            .backgroundColor('#0A84FF')
            .borderRadius(12)
            .enabled(!this.isSessionActive)
            .onClick(() => this.onSave())
        }
        .width('100%')
        .padding(16)
        .borderRadius(20)
        .backgroundColor('#24FFFFFF')
        .border({ width: 1, color: '#FFFFFF26' })
        SectionHeading({ title: '音频输出', subtitle: '下次连接生效' })
        Row({ space: 12 }) {
          Column({ space: 5 }) {
            Text('使用蓝牙音频')
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor('#F5F5F7')
            Text(this.useBluetoothAudio ? '蓝牙 A2DP（系统路由）' : 'CarPlay RTP')
              .fontSize(12)
              .fontColor('#FFFFFFA6')
              .maxLines(2)
          }
          .layoutWeight(1)
          Toggle({ type: ToggleType.Switch, isOn: this.useBluetoothAudio })
            .selectedColor('#0A84FF')
            .onChange((enabled: boolean): void => { this.useBluetoothAudio = enabled; })
            .accessibilityText('使用蓝牙音频')
        }
        .width('100%')
        .padding(16)
        .borderRadius(20)
        .backgroundColor('#24FFFFFF')
        .border({ width: 1, color: '#FFFFFF26' })
        SectionHeading({ title: '受限系统能力', subtitle: '清单声明不代表 ACL 已批准；获批后重启应用并刷新状态' })
        Column({ space: 6 }) {
          ForEach(this.restrictedPermissionStatus, (status: string) => {
            Text(status).fontSize(10).fontColor('#FFFFFFA6')
              .width('100%').maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
          }, (status: string) => status)
          Button('刷新权限状态')
            .width('100%')
            .onClick((): void => { void this.refreshRestrictedPermissions(); })
        }
        .width('100%')
        .padding(12)
        .borderRadius(18)
        .backgroundColor('#24FFFFFF')
        .border({ width: 1, color: '#FFFFFF26' })
        SectionHeading({ title: '安全与诊断', subtitle: '按天归档并保留 10 天；日志页显示最近 300 行' })
        Row({ space: 12 }) {
          Column({ space: 5 }) {
            Text('临时跳过 MFi challenge 验签')
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor('#F5F5F7')
            Text('联调模式会继续发送 AA05，不代表 MFi 身份已验证。')
              .fontSize(12)
              .fontColor('#FFB36B')
              .maxLines(2)
          }
          .layoutWeight(1)
          Toggle({ type: ToggleType.Switch, isOn: this.skipMfiChallengeVerification })
            .enabled(!this.isSessionActive)
            .onChange((enabled: boolean) => this.onSkipMfiChange(enabled))
        }
        .width('100%')
        .padding(16)
        .borderRadius(18)
        .backgroundColor('#3DFF9F0A')
        .border({ width: 1, color: '#FFFFFF26' })
        if (this.trustedMfiFingerprints.length > 0) {
          Column({ space: 8 }) {
            Text('已固定的 MFi 证书指纹')
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor('#F5F5F7')
            ForEach(this.trustedMfiFingerprints, (fingerprint: string) => {
              Row({ space: 8 }) {
                Text(fingerprint)
                  .fontSize(9)
                  .fontColor('#FFFFFFA6')
                  .layoutWeight(1)
                  .maxLines(2)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                Button('撤销')
                  .fontSize(11)
                  .enabled(!this.isSessionActive)
                  .onClick(() => this.onRevokeFingerprint(fingerprint))
              }
              .width('100%')
            }, (fingerprint: string) => fingerprint)
          }
          .width('100%')
          .padding(16)
          .borderRadius(18)
          .backgroundColor('#24FFFFFF')
          .border({ width: 1, color: '#FFFFFF26' })
        }
        InfoCard({
          title: '凭据保护',
          body: '热点密码只保存在当前内存会话；证书固定仅在 challenge 签名验证后保存。协议日志不记录密码、私钥或共享密钥。'
        })
      }
      .width('100%')
      .padding({ left: 22, right: 22, top: 24, bottom: 30 })
    }
    .width('100%')
    .layoutWeight(1)
    .scrollBar(BarState.Off)
  }
}