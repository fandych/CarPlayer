import { IndexHost } from './IndexHost';
import promptAction from '@ohos.promptAction';
import { CarPlayerSettings } from '../settings/CarPlayerSettingsStore';

export async function loadSettings(host: IndexHost): Promise<void> {
    host.settingsReady = false;
    host.settingsError = '';
    try {
      const settings = await host.settingsStore.load(host.getAppContext());
      host.acceptedTerms = settings.agreementAccepted;
      host.showWelcome = !settings.agreementAccepted;
      host.deviceName = settings.deviceName;
      host.bluetoothAddress = settings.bluetoothAddress;
      host.deviceUuid = settings.deviceUuid || host.createDeviceUuid();
      host.trustedMfiFingerprints = settings.trustedMfiFingerprints;
      host.skipMfiChallengeVerification = settings.skipMfiChallengeVerification;
      if (!settings.deviceUuid) {
        await host.persistSettings();
      }
      host.logProtocol('settings', '本地设置读取完成');
    } catch (error) {
      host.settingsError = host.errorMessage(error);
      host.logProtocol('settings', host.settingsError, 'ERROR');
    } finally {
      host.settingsReady = true;
    }
}

export function collectSettings(host: IndexHost, agreementAccepted: boolean = host.acceptedTerms): CarPlayerSettings {
    return {
      agreementAccepted,
      deviceName: host.deviceName.trim() || 'Harmony CarPlayer',
      bluetoothAddress: host.bluetoothAddress.trim().toUpperCase(),
      deviceUuid: host.deviceUuid,
      trustedMfiFingerprints: host.trustedMfiFingerprints.slice(),
      skipMfiChallengeVerification: host.skipMfiChallengeVerification
    };
}

export async function persistSettings(host: IndexHost, agreementAccepted: boolean = host.acceptedTerms): Promise<void> {
    await host.settingsStore.save(host.getAppContext(), host.collectSettings(agreementAccepted));
}

export async function acceptAgreement(host: IndexHost): Promise<void> {
    try {
      await host.persistSettings(true);
      host.acceptedTerms = true;
      host.showWelcome = false;
      host.logProtocol('ui', '用户已同意首次使用协议');
    } catch (error) {
      host.showError(error);
    }
}

export async function saveSettings(host: IndexHost): Promise<void> {
    try {
      if (host.isSessionActive) {
        throw new Error('请先停止监听，再修改发送端身份');
      }
      await host.persistSettings();
      host.logProtocol('settings', '发送端身份设置已保存');
      await promptAction.showToast({ message: '设置已保存' });
    } catch (error) {
      host.showError(error);
    }
}

export async function persistMfiFingerprint(host: IndexHost, fingerprint: string): Promise<void> {
    const normalized = fingerprint.toLowerCase();
    if (!/^[0-9a-f]{64}$/.test(normalized)) {
      throw new Error('MFi 指纹不是有效 SHA-256，拒绝保存');
    }
    if (host.trustedMfiFingerprints.includes(normalized)) {
      return;
    }
    const previous = host.trustedMfiFingerprints;
    host.trustedMfiFingerprints = [...previous, normalized];
    try {
      host.logProtocol('mfi', 'challenge 签名已通过，开始持久化 MFi 指纹');
      await host.persistSettings();
      host.logProtocol('mfi', 'challenge 签名验证成功后已保存 MFi 指纹');
    } catch (error) {
      host.trustedMfiFingerprints = previous;
      host.logProtocol('mfi', `保存 MFi 指纹失败，已恢复内存状态：${host.errorDetails(error)}`, 'ERROR');
      throw error instanceof Error ? error : new Error(String(error));
    }
}

export async function revokeMfiFingerprint(host: IndexHost, fingerprint: string): Promise<void> {
    const previous = host.trustedMfiFingerprints;
    host.trustedMfiFingerprints = previous.filter((value: string) => value !== fingerprint);
    try {
      await host.persistSettings();
      host.logProtocol('mfi', '已撤销本地固定的 MFi 指纹', 'WARN');
    } catch (error) {
      host.trustedMfiFingerprints = previous;
      host.showError(error);
    }
}

export async function setSkipMfiChallengeVerification(host: IndexHost, enabled: boolean): Promise<void> {
    const previous = host.skipMfiChallengeVerification;
    host.skipMfiChallengeVerification = enabled;
    try {
      await host.persistSettings();
      host.logProtocol(
        'mfi',
        enabled
          ? '诊断模式已启用：跳过 MFi challenge 验签；不会将跳过记录为验证通过'
          : '诊断模式已关闭：恢复 MFi challenge 签名验证',
        enabled ? 'WARN' : 'INFO'
      );
    } catch (error) {
      host.skipMfiChallengeVerification = previous;
      host.showError(error instanceof Error ? error : new Error(String(error)));
    }
}

export function createDeviceUuid(host: IndexHost): string {
    const randomPart = Math.floor(Math.random() * 0xffffffff).toString(16).padStart(8, '0');
    return `HOS-${Date.now().toString(16)}-${randomPart}`;
}
