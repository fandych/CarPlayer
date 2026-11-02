import common from '@ohos.app.ability.common';
import preferences from '@ohos.data.preferences';

export interface CarPlayerSettings {
  agreementAccepted: boolean;
  deviceName: string;
  bluetoothAddress: string;
  deviceUuid: string;
  trustedMfiFingerprints: string[];
  skipMfiChallengeVerification: boolean;
}

export class CarPlayerSettingsStore {
  private store?: preferences.Preferences;

  async load(context: common.UIAbilityContext): Promise<CarPlayerSettings> {
    const store = await this.getStore(context);
    const agreementAccepted = await store.get('agreementAccepted', false);
    const deviceName = await store.get('deviceName', 'Harmony CarPlayer');
    const bluetoothAddress = await store.get('bluetoothAddress', '');
    const deviceUuid = await store.get('deviceUuid', '');
    const fingerprints = await store.get('trustedMfiFingerprints', '');
    const skipMfiChallengeVerification = await store.get('skipMfiChallengeVerification', false);
    return {
      agreementAccepted: typeof agreementAccepted === 'boolean' ? agreementAccepted : false,
      deviceName: typeof deviceName === 'string' ? deviceName : 'Harmony CarPlayer',
      bluetoothAddress: typeof bluetoothAddress === 'string' ? bluetoothAddress : '',
      deviceUuid: typeof deviceUuid === 'string' ? deviceUuid : '',
      trustedMfiFingerprints: this.parseFingerprints(
        typeof fingerprints === 'string' ? fingerprints : ''
      ),
      skipMfiChallengeVerification: typeof skipMfiChallengeVerification === 'boolean'
        ? skipMfiChallengeVerification
        : false
    };
  }

  async save(context: common.UIAbilityContext, settings: CarPlayerSettings): Promise<void> {
    const store = await this.getStore(context);
    await store.put('agreementAccepted', settings.agreementAccepted);
    await store.put('deviceName', settings.deviceName);
    await store.put('bluetoothAddress', settings.bluetoothAddress);
    await store.put('deviceUuid', settings.deviceUuid);
    await store.put('trustedMfiFingerprints', settings.trustedMfiFingerprints.join('\n'));
    await store.put('skipMfiChallengeVerification', settings.skipMfiChallengeVerification);
    await store.flush();
  }

  private async getStore(context: common.UIAbilityContext): Promise<preferences.Preferences> {
    if (!this.store) {
      this.store = await preferences.getPreferences(context, 'carplayer_settings');
    }
    return this.store;
  }

  private parseFingerprints(serialized: string): string[] {
    const unique: Set<string> = new Set<string>();
    for (const entry of serialized.split('\n')) {
      const fingerprint = entry.trim().toLowerCase();
      if (/^[0-9a-f]{64}$/.test(fingerprint)) {
        unique.add(fingerprint);
      }
    }
    return Array.from(unique);
  }
}