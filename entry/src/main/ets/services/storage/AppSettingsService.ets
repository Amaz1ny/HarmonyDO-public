import { common, ConfigurationConstant } from '@kit.AbilityKit';
import { ThemeManager } from '../../common/theme/ThemeManager';
import { AppContext } from '../../common/utils/AppContext';
import { WindowManager } from '../../common/utils/WindowManager';
import { AuthService } from '../auth/AuthService';
import { AppearanceSettings, FeatureSettings } from '../../models/AppSettings';
import { PreferencesUtil } from './PreferencesUtil';
import { AppLogStore } from './AppLogStore';

const APPEARANCE_KEY: string = 'settings.appearance';
const FEATURE_KEY: string = 'settings.feature';

export class AppSettingsService {
  private static instance: AppSettingsService | null = null;

  private appearanceSettings: AppearanceSettings = new AppearanceSettings();
  private featureSettings: FeatureSettings = new FeatureSettings();
  private listeners: Set<() => void> = new Set();
  private initPromise: Promise<void> | null = null;

  static getInstance(): AppSettingsService {
    if (AppSettingsService.instance === null) {
      AppSettingsService.instance = new AppSettingsService();
    }
    return AppSettingsService.instance;
  }

  ensureInit(): Promise<void> {
    if (this.initPromise !== null) {
      return this.initPromise;
    }
    this.initPromise = (async () => {
      await PreferencesUtil.ensureInit();
      const appearanceRaw: string = await PreferencesUtil.getString(APPEARANCE_KEY, '{}');
      const featureRaw: string = await PreferencesUtil.getString(FEATURE_KEY, '{}');
      this.appearanceSettings = AppearanceSettings.fromJson(this.parseJsonObject(appearanceRaw));
      this.featureSettings = FeatureSettings.fromJson(this.parseJsonObject(featureRaw));
    })();
    return this.initPromise;
  }

  addListener(listener: () => void): void {
    this.listeners.add(listener);
  }

  removeListener(listener: () => void): void {
    this.listeners.delete(listener);
  }

  getAppearanceSettings(): AppearanceSettings {
    return this.appearanceSettings;
  }

  getFeatureSettings(): FeatureSettings {
    return this.featureSettings;
  }

  getPrimaryColor(): string {
    return this.resolveThemeColorHex(this.appearanceSettings.themeColor);
  }

  getPrimaryColorWithAlpha(alpha: number): string {
    return ThemeManager.hexWithAlpha(this.getPrimaryColor(), alpha);
  }

  getResolvedFontFamily(): string {
    const fontFamily: string = this.appearanceSettings.fontFamily;
    if (fontFamily === 'serif') return 'serif';
    if (fontFamily === 'monospace') return 'monospace';
    return '';
  }

  scaleContentFont(baseSize: number): number {
    const scale: number = this.appearanceSettings.contentFontScale;
    return Math.round(baseSize * scale * 10) / 10;
  }

  scaleContentLineHeight(baseLineHeight: number): number {
    const scale: number = this.appearanceSettings.contentFontScale;
    return Math.round(baseLineHeight * scale * 10) / 10;
  }

  applyReadingSpacing(text: string): string {
    if (!this.appearanceSettings.readingPanguSpacing) {
      return text;
    }
    return AppSettingsService.applyPanguSpacing(text);
  }

  applyEditorSpacing(text: string): string {
    if (!this.featureSettings.autoPanguSpacing) {
      return text;
    }
    return AppSettingsService.applyPanguSpacing(text);
  }

  buildConfiguredShareUrl(path: string): string {
    const username: string = AuthService.getInstance().getCurrentUsername().trim();
    const anonymousShare: boolean = this.featureSettings.anonymousShare;
    const normalizedPath: string = path !== undefined && path !== null ? path : '';
    const base: string = `https://linux.do${normalizedPath}`;
    if (anonymousShare || username.length === 0) {
      return base;
    }
    const separator: string = base.indexOf('?') >= 0 ? '&' : '?';
    return `${base}${separator}u=${encodeURIComponent(username)}`;
  }

  async setLocale(locale: string): Promise<void> {
    await this.ensureInit();
    this.appearanceSettings.locale = this.normalizeLocale(locale);
    await this.persistAppearance();
  }

  async setThemeMode(themeMode: string): Promise<void> {
    await this.ensureInit();
    this.appearanceSettings.themeMode = this.normalizeThemeMode(themeMode);
    await this.persistAppearance();
    this.applyThemeModeToApplication();
  }

  async setThemeColor(themeColor: string): Promise<void> {
    await this.ensureInit();
    this.appearanceSettings.themeColor = this.normalizeThemeColor(themeColor);
    await this.persistAppearance();
  }

  async setIconVariant(iconVariant: string): Promise<void> {
    await this.ensureInit();
    this.appearanceSettings.iconVariant = this.normalizeIconVariant(iconVariant);
    await this.persistAppearance();
  }

  async setFontFamily(fontFamily: string): Promise<void> {
    await this.ensureInit();
    this.appearanceSettings.fontFamily = this.normalizeFontFamily(fontFamily);
    await this.persistAppearance();
  }

  async setContentFontScale(scale: number): Promise<void> {
    await this.ensureInit();
    let next: number = scale;
    if (isNaN(next)) {
      next = 1;
    }
    next = Math.max(0.8, Math.min(1.4, next));
    this.appearanceSettings.contentFontScale = next;
    await this.persistAppearance();
  }

  async setReadingPanguSpacing(enabled: boolean): Promise<void> {
    await this.ensureInit();
    this.appearanceSettings.readingPanguSpacing = enabled;
    await this.persistAppearance();
  }

  async setLongPressPreview(enabled: boolean): Promise<void> {
    await this.ensureInit();
    this.featureSettings.longPressPreview = enabled;
    await this.persistFeature();
  }

  async setHideBarOnScroll(enabled: boolean): Promise<void> {
    await this.ensureInit();
    this.featureSettings.hideBarOnScroll = enabled;
    await this.persistFeature();
  }

  async setOpenLinksInAppBrowser(enabled: boolean): Promise<void> {
    await this.ensureInit();
    this.featureSettings.openLinksInAppBrowser = enabled;
    await this.persistFeature();
  }

  async setAnonymousShare(enabled: boolean): Promise<void> {
    await this.ensureInit();
    this.featureSettings.anonymousShare = enabled;
    await this.persistFeature();
  }

  async setAutoFillLogin(enabled: boolean): Promise<void> {
    await this.ensureInit();
    this.featureSettings.autoFillLogin = enabled;
    await this.persistFeature();
  }

  async setPortraitLock(enabled: boolean): Promise<void> {
    await this.ensureInit();
    this.featureSettings.portraitLock = enabled;
    await this.persistFeature();
    WindowManager.applyPortraitLock(enabled);
  }

  async setAutoPanguSpacing(enabled: boolean): Promise<void> {
    await this.ensureInit();
    this.featureSettings.autoPanguSpacing = enabled;
    await this.persistFeature();
  }

  applyThemeModeToApplication(): void {
    const ctx: common.UIAbilityContext | null = AppContext.getUIAbilityContext();
    if (ctx === null) {
      return;
    }
    try {
      const appContext = ctx.getApplicationContext();
      const themeMode: string = this.appearanceSettings.themeMode;
      if (themeMode === 'dark') {
        appContext.setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
      } else if (themeMode === 'light') {
        appContext.setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT);
      } else {
        appContext.setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
      }
    } catch (_) {
    }
  }

  private async persistAppearance(): Promise<void> {
    await PreferencesUtil.putString(APPEARANCE_KEY, JSON.stringify(this.appearanceSettings.toJson()));
    this.notifyChanged();
    AppLogStore.getInstance().info(
      'SETTINGS',
      `appearance updated mode=${this.appearanceSettings.themeMode} color=${this.appearanceSettings.themeColor}`
    );
  }

  private async persistFeature(): Promise<void> {
    await PreferencesUtil.putString(FEATURE_KEY, JSON.stringify(this.featureSettings.toJson()));
    this.notifyChanged();
    AppLogStore.getInstance().info('SETTINGS', 'feature settings updated');
  }

  private notifyChanged(): void {
    this.listeners.forEach((listener: () => void) => {
      listener();
    });
  }

  private parseJsonObject(raw: string): Record<string, Object> | null {
    try {
      const parsed: Object = JSON.parse(raw) as Object;
      if (parsed !== null && parsed !== undefined && typeof parsed === 'object' && !Array.isArray(parsed)) {
        return parsed as Record<string, Object>;
      }
    } catch (_) {
    }
    return null;
  }

  private static applyPanguSpacing(text: string): string {
    let next: string = text;
    next = next.replace(/([\u4e00-\u9fff])([A-Za-z0-9@#&\[\(\{])/g, '$1 $2');
    next = next.replace(/([A-Za-z0-9!%:;,.?，。！？、\]\)\}])([\u4e00-\u9fff])/g, '$1 $2');
    next = next.replace(/\s{2,}/g, ' ');
    return next;
  }

  private resolveThemeColorHex(themeColor: string): string {
    const key: string = this.normalizeThemeColor(themeColor);
    if (key === 'purple') return '#8B5CF6';
    if (key === 'green') return '#2E7D32';
    if (key === 'orange') return '#F57C00';
    if (key === 'pink') return '#D81B60';
    if (key === 'teal') return '#0F8B8D';
    if (key === 'red') return '#E53935';
    if (key === 'indigo') return '#3949AB';
    if (key === 'amber') return '#FFB300';
    return '#0088CC';
  }

  private normalizeLocale(locale: string): string {
    const key: string = locale !== undefined && locale !== null ? locale.trim() : '';
    if (key === 'zh_CN' || key === 'zh_TW' || key === 'zh_HK' || key === 'en_US') {
      return key;
    }
    return 'system';
  }

  private normalizeThemeMode(themeMode: string): string {
    const key: string = themeMode !== undefined && themeMode !== null ? themeMode.trim().toLowerCase() : '';
    if (key === 'light' || key === 'dark') {
      return key;
    }
    return 'system';
  }

  private normalizeThemeColor(themeColor: string): string {
    const key: string = themeColor !== undefined && themeColor !== null ? themeColor.trim().toLowerCase() : '';
    if (key === 'blue'
      || key === 'purple'
      || key === 'green'
      || key === 'orange'
      || key === 'pink'
      || key === 'teal'
      || key === 'red'
      || key === 'indigo'
      || key === 'amber') {
      return key;
    }
    return 'blue';
  }

  private normalizeIconVariant(iconVariant: string): string {
    const key: string = iconVariant !== undefined && iconVariant !== null ? iconVariant.trim().toLowerCase() : '';
    if (key === 'modern') {
      return 'modern';
    }
    return 'classic';
  }

  private normalizeFontFamily(fontFamily: string): string {
    const key: string = fontFamily !== undefined && fontFamily !== null ? fontFamily.trim().toLowerCase() : '';
    if (key === 'serif' || key === 'monospace' || key === 'misans') {
      return key;
    }
    return 'system';
  }
}
