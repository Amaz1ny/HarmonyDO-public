import { hilog } from '@kit.PerformanceAnalysisKit';
import { PreferencesUtil } from './PreferencesUtil';
import { ShareUtils } from '../../common/utils/ShareUtils';
import { MarkdownComposerUtils } from '../../common/utils/MarkdownComposerUtils';
import { WindowManager } from '../../common/utils/WindowManager';

const TAG: string = 'FeatureSettingsService';

export interface FeatureSettingsState {
  anonymousShare: boolean;
  autoFillLogin: boolean;
  autoPanguSpacing: boolean;
  portraitLock: boolean;
  stickerSource: string;
}

export interface FeatureSettingsStore {
  getBoolean(key: string, defaultValue: boolean): Promise<boolean>;
  putBoolean(key: string, value: boolean): Promise<void>;
  getString(key: string, defaultValue: string): Promise<string>;
  putString(key: string, value: string): Promise<void>;
}

export interface OrientationPreferenceApplier {
  applyPortraitLock(enabled: boolean): Promise<void>;
}

class PreferencesFeatureSettingsStore implements FeatureSettingsStore {
  async getBoolean(key: string, defaultValue: boolean): Promise<boolean> {
    await PreferencesUtil.ensureInit();
    return PreferencesUtil.getBoolean(key, defaultValue);
  }

  async putBoolean(key: string, value: boolean): Promise<void> {
    await PreferencesUtil.ensureInit();
    await PreferencesUtil.putBoolean(key, value);
  }

  async getString(key: string, defaultValue: string): Promise<string> {
    await PreferencesUtil.ensureInit();
    return PreferencesUtil.getString(key, defaultValue);
  }

  async putString(key: string, value: string): Promise<void> {
    await PreferencesUtil.ensureInit();
    await PreferencesUtil.putString(key, value);
  }
}

class WindowOrientationPreferenceApplier implements OrientationPreferenceApplier {
  async applyPortraitLock(enabled: boolean): Promise<void> {
    await WindowManager.applyPortraitLock(enabled);
  }
}

export class FeatureSettingsService {
  static readonly DEFAULT_STICKER_SOURCE: string = 'https://s.pwsh.us.kg';

  private static readonly KEY_ANONYMOUS_SHARE: string = 'feature_settings_anonymous_share';
  private static readonly KEY_AUTO_FILL_LOGIN: string = 'feature_settings_auto_fill_login';
  private static readonly KEY_AUTO_PANGU_SPACING: string = 'feature_settings_auto_pangu_spacing';
  private static readonly KEY_PORTRAIT_LOCK: string = 'feature_settings_portrait_lock';
  private static readonly KEY_STICKER_SOURCE: string = 'feature_settings_sticker_source';

  private static instance: FeatureSettingsService | null = null;

  private readonly store: FeatureSettingsStore;
  private readonly orientationApplier: OrientationPreferenceApplier;
  private state: FeatureSettingsState = FeatureSettingsService.makeDefaultState();
  private loaded: boolean = false;

  static getInstance(): FeatureSettingsService {
    if (FeatureSettingsService.instance === null) {
      FeatureSettingsService.instance = new FeatureSettingsService();
    }
    return FeatureSettingsService.instance;
  }

  private static makeDefaultState(): FeatureSettingsState {
    return {
      anonymousShare: false,
      autoFillLogin: true,
      autoPanguSpacing: false,
      portraitLock: false,
      stickerSource: FeatureSettingsService.DEFAULT_STICKER_SOURCE
    };
  }

  constructor(
    store: FeatureSettingsStore = new PreferencesFeatureSettingsStore(),
    orientationApplier: OrientationPreferenceApplier = new WindowOrientationPreferenceApplier()
  ) {
    this.store = store;
    this.orientationApplier = orientationApplier;
  }

  getSnapshot(): FeatureSettingsState {
    return {
      anonymousShare: this.state.anonymousShare,
      autoFillLogin: this.state.autoFillLogin,
      autoPanguSpacing: this.state.autoPanguSpacing,
      portraitLock: this.state.portraitLock,
      stickerSource: this.state.stickerSource
    };
  }

  private buildState(
    anonymousShare: boolean = this.state.anonymousShare,
    autoFillLogin: boolean = this.state.autoFillLogin,
    autoPanguSpacing: boolean = this.state.autoPanguSpacing,
    portraitLock: boolean = this.state.portraitLock,
    stickerSource: string = this.state.stickerSource
  ): FeatureSettingsState {
    return {
      anonymousShare: anonymousShare,
      autoFillLogin: autoFillLogin,
      autoPanguSpacing: autoPanguSpacing,
      portraitLock: portraitLock,
      stickerSource: stickerSource
    };
  }

  private applyState(nextState: FeatureSettingsState): FeatureSettingsState {
    this.state = {
      anonymousShare: nextState.anonymousShare,
      autoFillLogin: nextState.autoFillLogin,
      autoPanguSpacing: nextState.autoPanguSpacing,
      portraitLock: nextState.portraitLock,
      stickerSource: nextState.stickerSource
    };
    this.loaded = true;
    return this.getSnapshot();
  }

  private async ensureLoaded(): Promise<FeatureSettingsState> {
    if (!this.loaded) {
      return this.loadSettings();
    }
    return this.getSnapshot();
  }

  private normalizeStickerSource(rawValue: string, fallbackToDefault: boolean): string {
    let value: string = rawValue !== undefined && rawValue !== null ? rawValue.trim() : '';
    if (value.length === 0) {
      if (fallbackToDefault) {
        return FeatureSettingsService.DEFAULT_STICKER_SOURCE;
      }
      throw new Error('Sticker 源地址不能为空');
    }
    while (value.endsWith('/')) {
      value = value.substring(0, value.length - 1);
    }
    if (!/^https?:\/\/[^\s]+$/i.test(value)) {
      if (fallbackToDefault) {
        return FeatureSettingsService.DEFAULT_STICKER_SOURCE;
      }
      throw new Error('Sticker 源地址必须以 http:// 或 https:// 开头');
    }
    return value;
  }

  async loadSettings(): Promise<FeatureSettingsState> {
    const defaults: FeatureSettingsState = FeatureSettingsService.makeDefaultState();
    const anonymousShare: boolean = await this.store.getBoolean(
      FeatureSettingsService.KEY_ANONYMOUS_SHARE,
      defaults.anonymousShare
    );
    const autoFillLogin: boolean = await this.store.getBoolean(
      FeatureSettingsService.KEY_AUTO_FILL_LOGIN,
      defaults.autoFillLogin
    );
    const autoPanguSpacing: boolean = await this.store.getBoolean(
      FeatureSettingsService.KEY_AUTO_PANGU_SPACING,
      defaults.autoPanguSpacing
    );
    const portraitLock: boolean = await this.store.getBoolean(
      FeatureSettingsService.KEY_PORTRAIT_LOCK,
      defaults.portraitLock
    );
    const stickerSourceRaw: string = await this.store.getString(
      FeatureSettingsService.KEY_STICKER_SOURCE,
      defaults.stickerSource
    );
    return this.applyState({
      anonymousShare: anonymousShare,
      autoFillLogin: autoFillLogin,
      autoPanguSpacing: autoPanguSpacing,
      portraitLock: portraitLock,
      stickerSource: this.normalizeStickerSource(stickerSourceRaw, true)
    });
  }

  async setAnonymousShare(enabled: boolean): Promise<FeatureSettingsState> {
    await this.ensureLoaded();
    await this.store.putBoolean(FeatureSettingsService.KEY_ANONYMOUS_SHARE, enabled);
    return this.applyState(this.buildState(enabled));
  }

  async setAutoFillLogin(enabled: boolean): Promise<FeatureSettingsState> {
    await this.ensureLoaded();
    await this.store.putBoolean(FeatureSettingsService.KEY_AUTO_FILL_LOGIN, enabled);
    return this.applyState(this.buildState(this.state.anonymousShare, enabled));
  }

  async setAutoPanguSpacing(enabled: boolean): Promise<FeatureSettingsState> {
    await this.ensureLoaded();
    await this.store.putBoolean(FeatureSettingsService.KEY_AUTO_PANGU_SPACING, enabled);
    return this.applyState(this.buildState(this.state.anonymousShare, this.state.autoFillLogin, enabled));
  }

  async setPortraitLock(enabled: boolean): Promise<FeatureSettingsState> {
    await this.ensureLoaded();
    await this.store.putBoolean(FeatureSettingsService.KEY_PORTRAIT_LOCK, enabled);
    const nextState: FeatureSettingsState = this.applyState(this.buildState(
      this.state.anonymousShare,
      this.state.autoFillLogin,
      this.state.autoPanguSpacing,
      enabled
    ));
    await this.orientationApplier.applyPortraitLock(enabled);
    return nextState;
  }

  async replayPortraitLockPreference(): Promise<void> {
    const state: FeatureSettingsState = await this.ensureLoaded();
    try {
      await this.orientationApplier.applyPortraitLock(state.portraitLock);
    } catch (err) {
      hilog.error(0x0000, TAG, 'Replay portrait lock failed: %{public}s', JSON.stringify(err));
    }
  }

  async setStickerSource(source: string): Promise<FeatureSettingsState> {
    await this.ensureLoaded();
    const normalized: string = this.normalizeStickerSource(source, false);
    await this.store.putString(FeatureSettingsService.KEY_STICKER_SOURCE, normalized);
    return this.applyState(this.buildState(
      this.state.anonymousShare,
      this.state.autoFillLogin,
      this.state.autoPanguSpacing,
      this.state.portraitLock,
      normalized
    ));
  }

  async resetStickerSource(): Promise<FeatureSettingsState> {
    return this.setStickerSource(FeatureSettingsService.DEFAULT_STICKER_SOURCE);
  }

  async isAutoFillLoginEnabled(): Promise<boolean> {
    const state: FeatureSettingsState = await this.ensureLoaded();
    return state.autoFillLogin;
  }

  async getStickerSource(): Promise<string> {
    const state: FeatureSettingsState = await this.ensureLoaded();
    return state.stickerSource;
  }

  async buildShareUrl(path: string, username: string = ''): Promise<string> {
    const state: FeatureSettingsState = await this.ensureLoaded();
    return ShareUtils.buildShareUrl(path, username, state.anonymousShare);
  }

  async transformComposerContentBeforeSubmit(text: string): Promise<string> {
    const safeText: string = text !== undefined && text !== null ? text : '';
    const state: FeatureSettingsState = await this.ensureLoaded();
    if (!state.autoPanguSpacing) {
      return safeText;
    }
    return MarkdownComposerUtils.applyPanguSpacing(safeText);
  }
}
