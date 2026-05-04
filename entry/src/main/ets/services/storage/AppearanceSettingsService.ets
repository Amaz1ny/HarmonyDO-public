import { common, ConfigurationConstant } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { PreferencesUtil } from './PreferencesUtil';
import { AppContext } from '../../common/utils/AppContext';
import { WindowManager } from '../../common/utils/WindowManager';

const TAG: string = 'AppearanceSettingsService';

export type AppearanceThemeMode = 'system' | 'light' | 'dark';
export type AppearanceAccentColor =
  'blue'
  | 'purple'
  | 'green'
  | 'orange'
  | 'pink'
  | 'teal'
  | 'red'
  | 'indigo'
  | 'amber'
  | 'cyan';

export const APPEARANCE_THEME_MODE_SYSTEM: AppearanceThemeMode = 'system';
export const APPEARANCE_THEME_MODE_LIGHT: AppearanceThemeMode = 'light';
export const APPEARANCE_THEME_MODE_DARK: AppearanceThemeMode = 'dark';

export const APPEARANCE_ACCENT_COLOR_BLUE: AppearanceAccentColor = 'blue';
export const APPEARANCE_ACCENT_COLOR_PURPLE: AppearanceAccentColor = 'purple';
export const APPEARANCE_ACCENT_COLOR_GREEN: AppearanceAccentColor = 'green';
export const APPEARANCE_ACCENT_COLOR_ORANGE: AppearanceAccentColor = 'orange';
export const APPEARANCE_ACCENT_COLOR_PINK: AppearanceAccentColor = 'pink';
export const APPEARANCE_ACCENT_COLOR_TEAL: AppearanceAccentColor = 'teal';
export const APPEARANCE_ACCENT_COLOR_RED: AppearanceAccentColor = 'red';
export const APPEARANCE_ACCENT_COLOR_INDIGO: AppearanceAccentColor = 'indigo';
export const APPEARANCE_ACCENT_COLOR_AMBER: AppearanceAccentColor = 'amber';
export const APPEARANCE_ACCENT_COLOR_CYAN: AppearanceAccentColor = 'cyan';

export interface AppearanceSettingsState {
  themeMode: AppearanceThemeMode;
  accentColor: AppearanceAccentColor;
}

export interface AppearanceSettingsStore {
  getString(key: string, defaultValue: string): Promise<string>;
  putString(key: string, value: string): Promise<void>;
}

class PreferencesAppearanceSettingsStore implements AppearanceSettingsStore {
  async getString(key: string, defaultValue: string): Promise<string> {
    await PreferencesUtil.ensureInit();
    return PreferencesUtil.getString(key, defaultValue);
  }

  async putString(key: string, value: string): Promise<void> {
    await PreferencesUtil.ensureInit();
    await PreferencesUtil.putString(key, value);
  }

}

export class AppearanceSettingsService {
  private static readonly KEY_THEME_MODE: string = 'appearance_settings_theme_mode';
  private static readonly KEY_ACCENT_COLOR: string = 'appearance_settings_accent_color';

  private static instance: AppearanceSettingsService | null = null;

  private readonly store: AppearanceSettingsStore;
  private state: AppearanceSettingsState = AppearanceSettingsService.makeDefaultState();
  private loaded: boolean = false;
  private listeners: ((state: AppearanceSettingsState) => void)[] = [];
  private notifyScheduled: boolean = false;

  static getInstance(): AppearanceSettingsService {
    if (AppearanceSettingsService.instance === null) {
      AppearanceSettingsService.instance = new AppearanceSettingsService();
    }
    return AppearanceSettingsService.instance;
  }

  private static makeDefaultState(): AppearanceSettingsState {
    return {
      themeMode: APPEARANCE_THEME_MODE_SYSTEM,
      accentColor: APPEARANCE_ACCENT_COLOR_BLUE
    };
  }

  constructor(store: AppearanceSettingsStore = new PreferencesAppearanceSettingsStore()) {
    this.store = store;
  }

  getSnapshot(): AppearanceSettingsState {
    return {
      themeMode: this.state.themeMode,
      accentColor: this.state.accentColor
    };
  }

  private applyState(nextState: AppearanceSettingsState): AppearanceSettingsState {
    this.state = {
      themeMode: nextState.themeMode,
      accentColor: nextState.accentColor
    };
    this.loaded = true;
    return this.getSnapshot();
  }

  addListener(listener: (state: AppearanceSettingsState) => void): void {
    for (let i = 0; i < this.listeners.length; i++) {
      if (this.listeners[i] === listener) {
        try {
          listener(this.getSnapshot());
        } catch (_) {
        }
        return;
      }
    }
    this.listeners.push(listener);
    try {
      listener(this.getSnapshot());
    } catch (_) {
    }
  }

  removeListener(listener: (state: AppearanceSettingsState) => void): void {
    const next: ((state: AppearanceSettingsState) => void)[] = [];
    for (let i = 0; i < this.listeners.length; i++) {
      if (this.listeners[i] !== listener) {
        next.push(this.listeners[i]);
      }
    }
    this.listeners = next;
  }

  private notifyListeners(): void {
    if (this.notifyScheduled) {
      return;
    }
    this.notifyScheduled = true;
    setTimeout(() => {
      this.notifyScheduled = false;
      const snapshot: AppearanceSettingsState = this.getSnapshot();
      for (let i = 0; i < this.listeners.length; i++) {
        try {
          this.listeners[i](snapshot);
        } catch (_) {
        }
      }
    }, 0);
  }

  private normalizeThemeMode(rawValue: string): AppearanceThemeMode {
    switch (rawValue) {
      case APPEARANCE_THEME_MODE_LIGHT:
        return APPEARANCE_THEME_MODE_LIGHT;
      case APPEARANCE_THEME_MODE_DARK:
        return APPEARANCE_THEME_MODE_DARK;
      default:
        return APPEARANCE_THEME_MODE_SYSTEM;
    }
  }

  private normalizeAccentColor(rawValue: string): AppearanceAccentColor {
    switch (rawValue) {
      case APPEARANCE_ACCENT_COLOR_PURPLE:
        return APPEARANCE_ACCENT_COLOR_PURPLE;
      case APPEARANCE_ACCENT_COLOR_GREEN:
        return APPEARANCE_ACCENT_COLOR_GREEN;
      case APPEARANCE_ACCENT_COLOR_ORANGE:
        return APPEARANCE_ACCENT_COLOR_ORANGE;
      case APPEARANCE_ACCENT_COLOR_PINK:
        return APPEARANCE_ACCENT_COLOR_PINK;
      case APPEARANCE_ACCENT_COLOR_TEAL:
        return APPEARANCE_ACCENT_COLOR_TEAL;
      case APPEARANCE_ACCENT_COLOR_RED:
        return APPEARANCE_ACCENT_COLOR_RED;
      case APPEARANCE_ACCENT_COLOR_INDIGO:
        return APPEARANCE_ACCENT_COLOR_INDIGO;
      case APPEARANCE_ACCENT_COLOR_AMBER:
        return APPEARANCE_ACCENT_COLOR_AMBER;
      case APPEARANCE_ACCENT_COLOR_CYAN:
        return APPEARANCE_ACCENT_COLOR_CYAN;
      default:
        return APPEARANCE_ACCENT_COLOR_BLUE;
    }
  }

  private getAppColorMode(themeMode: AppearanceThemeMode): number {
    if (themeMode === APPEARANCE_THEME_MODE_LIGHT) {
      return ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
    }
    if (themeMode === APPEARANCE_THEME_MODE_DARK) {
      return ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
    }
    return ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET;
  }

  private getWindowColorMode(themeMode: AppearanceThemeMode): number | undefined {
    if (themeMode === APPEARANCE_THEME_MODE_LIGHT) {
      return ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
    }
    if (themeMode === APPEARANCE_THEME_MODE_DARK) {
      return ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
    }
    return undefined;
  }

  private applyThemeModeToApplication(themeMode: AppearanceThemeMode): void {
    const ctx: common.UIAbilityContext | null = AppContext.getUIAbilityContext();
    if (ctx === null) {
      return;
    }

    try {
      ctx.getApplicationContext().setColorMode(this.getAppColorMode(themeMode));
      WindowManager.refreshCurrentSystemChrome(this.getWindowColorMode(themeMode));
    } catch (err) {
      hilog.error(0x0000, TAG, 'Apply theme mode failed: %{public}s', JSON.stringify(err));
    }
  }

  private async ensureLoaded(): Promise<AppearanceSettingsState> {
    if (!this.loaded) {
      return this.loadSettings();
    }
    return this.getSnapshot();
  }

  async loadSettings(): Promise<AppearanceSettingsState> {
    const defaults: AppearanceSettingsState = AppearanceSettingsService.makeDefaultState();
    const themeModeRaw: string = await this.store.getString(
      AppearanceSettingsService.KEY_THEME_MODE,
      defaults.themeMode
    );
    const accentColorRaw: string = await this.store.getString(
      AppearanceSettingsService.KEY_ACCENT_COLOR,
      defaults.accentColor
    );
    return this.applyState({
      themeMode: this.normalizeThemeMode(themeModeRaw),
      accentColor: this.normalizeAccentColor(accentColorRaw)
    });
  }

  async replayThemeModePreference(): Promise<void> {
    const state: AppearanceSettingsState = await this.ensureLoaded();
    this.applyThemeModeToApplication(state.themeMode);
  }

  async setThemeMode(themeMode: AppearanceThemeMode): Promise<AppearanceSettingsState> {
    const normalized: AppearanceThemeMode = this.normalizeThemeMode(themeMode);
    const current: AppearanceSettingsState = await this.ensureLoaded();
    await this.store.putString(AppearanceSettingsService.KEY_THEME_MODE, normalized);
    const nextState: AppearanceSettingsState = this.applyState({
      themeMode: normalized,
      accentColor: current.accentColor
    });
    this.applyThemeModeToApplication(normalized);
    this.notifyListeners();
    return nextState;
  }

  async setAccentColor(accentColor: AppearanceAccentColor): Promise<AppearanceSettingsState> {
    const normalized: AppearanceAccentColor = this.normalizeAccentColor(accentColor);
    const current: AppearanceSettingsState = await this.ensureLoaded();
    await this.store.putString(AppearanceSettingsService.KEY_ACCENT_COLOR, normalized);
    const nextState: AppearanceSettingsState = this.applyState({
      themeMode: current.themeMode,
      accentColor: normalized
    });
    this.notifyListeners();
    return nextState;
  }
}
