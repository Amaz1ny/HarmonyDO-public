export class AppearanceSettings {
  locale: string = 'system';
  themeMode: string = 'system';
  themeColor: string = 'blue';
  iconVariant: string = 'classic';
  fontFamily: string = 'system';
  contentFontScale: number = 1;
  readingPanguSpacing: boolean = false;

  static fromJson(json: Record<string, Object> | null): AppearanceSettings {
    const settings: AppearanceSettings = new AppearanceSettings();
    if (json === null || json === undefined) {
      return settings;
    }
    const localeVal = json['locale'];
    const themeModeVal = json['themeMode'];
    const themeColorVal = json['themeColor'];
    const iconVariantVal = json['iconVariant'];
    const fontFamilyVal = json['fontFamily'];
    const contentFontScaleVal = json['contentFontScale'];
    const readingPanguSpacingVal = json['readingPanguSpacing'];

    settings.locale = localeVal !== undefined && localeVal !== null ? localeVal.toString().trim() : settings.locale;
    settings.themeMode = themeModeVal !== undefined && themeModeVal !== null
      ? themeModeVal.toString().trim()
      : settings.themeMode;
    settings.themeColor = themeColorVal !== undefined && themeColorVal !== null
      ? themeColorVal.toString().trim()
      : settings.themeColor;
    settings.iconVariant = iconVariantVal !== undefined && iconVariantVal !== null
      ? iconVariantVal.toString().trim()
      : settings.iconVariant;
    settings.fontFamily = fontFamilyVal !== undefined && fontFamilyVal !== null
      ? fontFamilyVal.toString().trim()
      : settings.fontFamily;
    settings.contentFontScale = contentFontScaleVal !== undefined && contentFontScaleVal !== null
      ? Number(contentFontScaleVal.toString())
      : settings.contentFontScale;
    settings.readingPanguSpacing = readingPanguSpacingVal !== undefined && readingPanguSpacingVal !== null
      ? Boolean(readingPanguSpacingVal)
      : settings.readingPanguSpacing;
    if (isNaN(settings.contentFontScale) || settings.contentFontScale <= 0) {
      settings.contentFontScale = 1;
    }
    return settings;
  }

  toJson(): Record<string, Object> {
    const json: Record<string, Object> = {};
    json['locale'] = this.locale;
    json['themeMode'] = this.themeMode;
    json['themeColor'] = this.themeColor;
    json['iconVariant'] = this.iconVariant;
    json['fontFamily'] = this.fontFamily;
    json['contentFontScale'] = this.contentFontScale;
    json['readingPanguSpacing'] = this.readingPanguSpacing;
    return json;
  }
}

export class FeatureSettings {
  longPressPreview: boolean = true;
  hideBarOnScroll: boolean = true;
  openLinksInAppBrowser: boolean = true;
  anonymousShare: boolean = true;
  autoFillLogin: boolean = true;
  portraitLock: boolean = false;
  autoPanguSpacing: boolean = false;

  static fromJson(json: Record<string, Object> | null): FeatureSettings {
    const settings: FeatureSettings = new FeatureSettings();
    if (json === null || json === undefined) {
      return settings;
    }
    const longPressPreviewVal = json['longPressPreview'];
    const hideBarOnScrollVal = json['hideBarOnScroll'];
    const openLinksInAppBrowserVal = json['openLinksInAppBrowser'];
    const anonymousShareVal = json['anonymousShare'];
    const autoFillLoginVal = json['autoFillLogin'];
    const portraitLockVal = json['portraitLock'];
    const autoPanguSpacingVal = json['autoPanguSpacing'];

    settings.longPressPreview = longPressPreviewVal !== undefined && longPressPreviewVal !== null
      ? Boolean(longPressPreviewVal)
      : settings.longPressPreview;
    settings.hideBarOnScroll = hideBarOnScrollVal !== undefined && hideBarOnScrollVal !== null
      ? Boolean(hideBarOnScrollVal)
      : settings.hideBarOnScroll;
    settings.openLinksInAppBrowser = openLinksInAppBrowserVal !== undefined && openLinksInAppBrowserVal !== null
      ? Boolean(openLinksInAppBrowserVal)
      : settings.openLinksInAppBrowser;
    settings.anonymousShare = anonymousShareVal !== undefined && anonymousShareVal !== null
      ? Boolean(anonymousShareVal)
      : settings.anonymousShare;
    settings.autoFillLogin = autoFillLoginVal !== undefined && autoFillLoginVal !== null
      ? Boolean(autoFillLoginVal)
      : settings.autoFillLogin;
    settings.portraitLock = portraitLockVal !== undefined && portraitLockVal !== null
      ? Boolean(portraitLockVal)
      : settings.portraitLock;
    settings.autoPanguSpacing = autoPanguSpacingVal !== undefined && autoPanguSpacingVal !== null
      ? Boolean(autoPanguSpacingVal)
      : settings.autoPanguSpacing;
    return settings;
  }

  toJson(): Record<string, Object> {
    const json: Record<string, Object> = {};
    json['longPressPreview'] = this.longPressPreview;
    json['hideBarOnScroll'] = this.hideBarOnScroll;
    json['openLinksInAppBrowser'] = this.openLinksInAppBrowser;
    json['anonymousShare'] = this.anonymousShare;
    json['autoFillLogin'] = this.autoFillLogin;
    json['portraitLock'] = this.portraitLock;
    json['autoPanguSpacing'] = this.autoPanguSpacing;
    return json;
  }
}
