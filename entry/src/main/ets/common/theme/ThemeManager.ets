/**
 * 主题管理器
 *
 * 管理应用主题状态和动态切换
 * 注意：颜色值主要通过 $r('app.color.xxx') 资源引用实现自动深色模式
 * 此类提供额外的主题相关工具方法
 */
export class ThemeManager {
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
