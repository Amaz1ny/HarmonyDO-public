import {
  APPEARANCE_ACCENT_COLOR_AMBER,
  APPEARANCE_ACCENT_COLOR_CYAN,
  APPEARANCE_ACCENT_COLOR_GREEN,
  APPEARANCE_ACCENT_COLOR_INDIGO,
  APPEARANCE_ACCENT_COLOR_ORANGE,
  APPEARANCE_ACCENT_COLOR_PINK,
  APPEARANCE_ACCENT_COLOR_PURPLE,
  APPEARANCE_ACCENT_COLOR_RED,
  APPEARANCE_ACCENT_COLOR_TEAL,
  AppearanceAccentColor,
  AppearanceSettingsService
} from '../../services/storage/AppearanceSettingsService';
import { WindowManager } from '../utils/WindowManager';

/**
 * 主题管理器
 *
 * 管理应用主题状态和动态切换
 * 注意：颜色值主要通过 $r('app.color.xxx') 资源引用实现自动深色模式
 * 此类提供额外的主题相关工具方法
 */
export class ThemeManager {
  /**
   * 主题色预设映射。
   * 默认蓝色沿用 HarmonyDO 现有主色，其他色相采用常见 Material 色系。
   */
  static getAccentColorHex(accentColor: AppearanceAccentColor): string {
    switch (accentColor) {
      case APPEARANCE_ACCENT_COLOR_PURPLE:
        return '#9C27B0';
      case APPEARANCE_ACCENT_COLOR_GREEN:
        return '#4CAF50';
      case APPEARANCE_ACCENT_COLOR_ORANGE:
        return '#FF9800';
      case APPEARANCE_ACCENT_COLOR_PINK:
        return '#E91E63';
      case APPEARANCE_ACCENT_COLOR_TEAL:
        return '#009688';
      case APPEARANCE_ACCENT_COLOR_RED:
        return '#F44336';
      case APPEARANCE_ACCENT_COLOR_INDIGO:
        return '#3F51B5';
      case APPEARANCE_ACCENT_COLOR_AMBER:
        return '#FFC107';
      case APPEARANCE_ACCENT_COLOR_CYAN:
        return '#00BCD4';
      default:
        return '#0088CC';
    }
  }

  static getAccentSecondaryColorHex(accentColor: AppearanceAccentColor): string {
    switch (accentColor) {
      case APPEARANCE_ACCENT_COLOR_PURPLE:
        return '#CE93D8';
      case APPEARANCE_ACCENT_COLOR_GREEN:
        return '#81C784';
      case APPEARANCE_ACCENT_COLOR_ORANGE:
        return '#FFB74D';
      case APPEARANCE_ACCENT_COLOR_PINK:
        return '#F48FB1';
      case APPEARANCE_ACCENT_COLOR_TEAL:
        return '#4DB6AC';
      case APPEARANCE_ACCENT_COLOR_RED:
        return '#EF9A9A';
      case APPEARANCE_ACCENT_COLOR_INDIGO:
        return '#7986CB';
      case APPEARANCE_ACCENT_COLOR_AMBER:
        return '#FFD54F';
      case APPEARANCE_ACCENT_COLOR_CYAN:
        return '#4DD0E1';
      default:
        return '#6CB6E8';
    }
  }

  static getAccentTertiaryColorHex(accentColor: AppearanceAccentColor): string {
    switch (accentColor) {
      case APPEARANCE_ACCENT_COLOR_PURPLE:
        return '#EC407A';
      case APPEARANCE_ACCENT_COLOR_GREEN:
        return '#26A69A';
      case APPEARANCE_ACCENT_COLOR_ORANGE:
        return '#8BC34A';
      case APPEARANCE_ACCENT_COLOR_PINK:
        return '#7E57C2';
      case APPEARANCE_ACCENT_COLOR_TEAL:
        return '#42A5F5';
      case APPEARANCE_ACCENT_COLOR_RED:
        return '#FF7043';
      case APPEARANCE_ACCENT_COLOR_INDIGO:
        return '#29B6F6';
      case APPEARANCE_ACCENT_COLOR_AMBER:
        return '#FF8F00';
      case APPEARANCE_ACCENT_COLOR_CYAN:
        return '#26C6DA';
      default:
        return '#7E57C2';
    }
  }

  static getCurrentAccentColorHex(): string {
    return ThemeManager.getAccentColorHex(AppearanceSettingsService.getInstance().getSnapshot().accentColor);
  }

  private static clamp01(value: number): number {
    return Math.max(0, Math.min(1, value));
  }

  private static clamp255(value: number): number {
    return Math.max(0, Math.min(255, Math.round(value)));
  }

  private static normalizeHex6(hex: string): string {
    let colorHex: string = hex;
    if (colorHex.startsWith('#')) {
      colorHex = colorHex.substring(1);
    }
    if (colorHex.length === 8) {
      colorHex = colorHex.substring(2);
    }
    if (colorHex.length !== 6) {
      return '0088CC';
    }
    return colorHex;
  }

  private static channelToHex(value: number): string {
    return ThemeManager.clamp255(value).toString(16).padStart(2, '0').toUpperCase();
  }

  private static mixChannel(foreground: number, background: number, amount: number): number {
    return background + (foreground - background) * ThemeManager.clamp01(amount);
  }

  static mixHex(foregroundHex: string, backgroundHex: string, amount: number): string {
    const foreground: string = ThemeManager.normalizeHex6(foregroundHex);
    const background: string = ThemeManager.normalizeHex6(backgroundHex);
    const foregroundR: number = parseInt(foreground.substring(0, 2), 16);
    const foregroundG: number = parseInt(foreground.substring(2, 4), 16);
    const foregroundB: number = parseInt(foreground.substring(4, 6), 16);
    const backgroundR: number = parseInt(background.substring(0, 2), 16);
    const backgroundG: number = parseInt(background.substring(2, 4), 16);
    const backgroundB: number = parseInt(background.substring(4, 6), 16);
    return `#${ThemeManager.channelToHex(ThemeManager.mixChannel(foregroundR, backgroundR, amount))}` +
      `${ThemeManager.channelToHex(ThemeManager.mixChannel(foregroundG, backgroundG, amount))}` +
      `${ThemeManager.channelToHex(ThemeManager.mixChannel(foregroundB, backgroundB, amount))}`;
  }

  /**
   * 种子色方案会让 background/surfaceContainer 被 seed color 轻微染色。
   * 鸿蒙端资源色不能运行时整体替换，这里先提供同等语义的动态浅染 helper，供主页面逐步接入。
   */
  static getAccentBackgroundColorHex(accentColor: AppearanceAccentColor): string {
    const base: string = WindowManager.isDarkMode() ? '#121212' : '#F5F5F5';
    return ThemeManager.mixHex(ThemeManager.getAccentColorHex(accentColor), base, WindowManager.isDarkMode() ? 0.12 : 0.045);
  }

  static getAccentSurfaceColorHex(accentColor: AppearanceAccentColor): string {
    const base: string = WindowManager.isDarkMode() ? '#1E1E1E' : '#FFFFFF';
    return ThemeManager.mixHex(ThemeManager.getAccentColorHex(accentColor), base, WindowManager.isDarkMode() ? 0.10 : 0.03);
  }

  static getAccentSurfaceVariantColorHex(accentColor: AppearanceAccentColor): string {
    const base: string = WindowManager.isDarkMode() ? '#2A2A2A' : '#F5F5F5';
    return ThemeManager.mixHex(ThemeManager.getAccentColorHex(accentColor), base, WindowManager.isDarkMode() ? 0.14 : 0.06);
  }

  static getAccentSelectedBackgroundColorHex(accentColor: AppearanceAccentColor): string {
    const base: string = WindowManager.isDarkMode() ? '#2A2A2A' : '#FFFFFF';
    return ThemeManager.mixHex(ThemeManager.getAccentColorHex(accentColor), base, WindowManager.isDarkMode() ? 0.24 : 0.12);
  }

  static getCurrentAccentBackgroundColorHex(): string {
    return ThemeManager.getAccentBackgroundColorHex(AppearanceSettingsService.getInstance().getSnapshot().accentColor);
  }

  static getCurrentAccentSurfaceColorHex(): string {
    return ThemeManager.getAccentSurfaceColorHex(AppearanceSettingsService.getInstance().getSnapshot().accentColor);
  }

  static getCurrentAccentSurfaceVariantColorHex(): string {
    return ThemeManager.getAccentSurfaceVariantColorHex(AppearanceSettingsService.getInstance().getSnapshot().accentColor);
  }

  static getCurrentAccentSelectedBackgroundColorHex(): string {
    return ThemeManager.getAccentSelectedBackgroundColorHex(AppearanceSettingsService.getInstance().getSnapshot().accentColor);
  }

  /**
   * 将十六进制颜色字符串转为 number
   * 例如 "FF5733" -> 0xFFFF5733
   */
  static hexToColor(hex: string): number {
    let colorHex: string = hex;
    if (colorHex.startsWith('#')) {
      colorHex = colorHex.substring(1);
    }
    // 补齐 alpha
    if (colorHex.length === 6) {
      colorHex = `FF${colorHex}`;
    }
    return parseInt(colorHex, 16);
  }

  /**
   * 生成带透明度的颜色
   * @param hex 十六进制颜色 (不含 #)
   * @param alpha 透明度 0-1
   */
  static hexWithAlpha(hex: string, alpha: number): string {
    const alphaHex: string = Math.round(alpha * 255).toString(16).padStart(2, '0');
    let colorHex: string = hex;
    if (colorHex.startsWith('#')) {
      colorHex = colorHex.substring(1);
    }
    return `#${alphaHex}${colorHex}`;
  }

  /**
   * 信任等级对应的颜色
   */
  static getTrustLevelColor(level: number): string {
    if (level === 0) return '#999999';
    if (level === 1) return '#4CAF50';
    if (level === 2) return '#2196F3';
    if (level === 3) return '#FF9800';
    if (level === 4) return '#E91E63';
    return '#999999';
  }

  /**
   * 分类颜色安全获取
   */
  static getCategoryColor(color: string | null): string {
    if (color === null || color.length === 0) {
      return '#999999';
    }
    if (color.startsWith('#')) {
      return color;
    }
    return `#${color}`;
  }
}
