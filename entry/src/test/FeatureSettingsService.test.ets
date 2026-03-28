import { describe, it, expect } from '@ohos/hypium';
import {
  FeatureSettingsService,
  FeatureSettingsState,
  FeatureSettingsStore,
  OrientationPreferenceApplier
} from '../main/ets/services/storage/FeatureSettingsService';

class FakeFeatureSettingsStore implements FeatureSettingsStore {
  private boolValues: Map<string, boolean> = new Map();
  private stringValues: Map<string, string> = new Map();

  async getBoolean(key: string, defaultValue: boolean): Promise<boolean> {
    return this.boolValues.has(key) ? (this.boolValues.get(key) as boolean) : defaultValue;
  }

  async putBoolean(key: string, value: boolean): Promise<void> {
    this.boolValues.set(key, value);
  }

  async getString(key: string, defaultValue: string): Promise<string> {
    return this.stringValues.has(key) ? (this.stringValues.get(key) as string) : defaultValue;
  }

  async putString(key: string, value: string): Promise<void> {
    this.stringValues.set(key, value);
  }
}

class FakeOrientationPreferenceApplier implements OrientationPreferenceApplier {
  public appliedValues: boolean[] = [];

  async applyPortraitLock(enabled: boolean): Promise<void> {
    this.appliedValues.push(enabled);
  }
}

export default function featureSettingsServiceTest() {
  describe('featureSettingsServiceTest', () => {
    it('updates each setting without relying on object spread', 0, async () => {
      const store: FakeFeatureSettingsStore = new FakeFeatureSettingsStore();
      const applier: FakeOrientationPreferenceApplier = new FakeOrientationPreferenceApplier();
      const service: FeatureSettingsService = new FeatureSettingsService(store, applier);

      let state: FeatureSettingsState = await service.setAnonymousShare(true);
      expect(state.anonymousShare).assertTrue();
      expect(state.autoFillLogin).assertTrue();
      expect(state.autoPanguSpacing).assertFalse();
      expect(state.portraitLock).assertFalse();
      expect(state.stickerSource).assertEqual(FeatureSettingsService.DEFAULT_STICKER_SOURCE);

      state = await service.setAutoFillLogin(false);
      expect(state.anonymousShare).assertTrue();
      expect(state.autoFillLogin).assertFalse();

      state = await service.setAutoPanguSpacing(true);
      expect(state.autoPanguSpacing).assertTrue();

      state = await service.setPortraitLock(true);
      expect(state.portraitLock).assertTrue();
      expect(applier.appliedValues.length).assertEqual(1);
      expect(applier.appliedValues[0]).assertTrue();

      state = await service.setStickerSource('https://example.com');
      expect(state.stickerSource).assertEqual('https://example.com');
      expect(state.anonymousShare).assertTrue();
      expect(state.autoFillLogin).assertFalse();
      expect(state.autoPanguSpacing).assertTrue();
      expect(state.portraitLock).assertTrue();
    });
  });
}
