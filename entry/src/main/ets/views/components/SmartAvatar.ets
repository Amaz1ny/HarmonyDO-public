/**
 * 智能头像组件 — 100% 复刻安卓版 SmartAvatar
 *
 * 行为：
 * - 有 URL 时：CachedNetworkImage 加载圆形裁剪头像
 * - 无 URL 但有 fallbackText 时：取首字母大写居中，主色背景
 * - 都没有时：👤 图标占位
 *
 * 对应 Flutter: SmartAvatar(imageUrl, radius, fallbackText, backgroundColor)
 */
import { AnimatedGifImage } from './AnimatedGifImage';

@ComponentV2
export struct SmartAvatar {
  @Param avatarUrl: string = '';
  @Param avatarSize: number = 36;
  @Param avatarRadius: number = -1;
  @Param fallbackText: string = '';
  @Param bgColor: string = '';
  @Local private failedUrl: string = '';

  private getRadius(): number {
    return this.avatarRadius >= 0 ? this.avatarRadius : this.avatarSize / 2;
  }

  private isGifUrl(url: string): boolean {
    const raw: string = url !== undefined && url !== null ? url.trim().toLowerCase() : '';
    if (raw.length === 0) return false;
    const q: number = raw.indexOf('?');
    const path: string = q >= 0 ? raw.substring(0, q) : raw;
    if (path.endsWith('.gif')) return true;
    return false;
  }

  build() {
    if (this.avatarUrl.length > 0 && this.avatarUrl !== this.failedUrl) {
      if (this.isGifUrl(this.avatarUrl)) {
        AnimatedGifImage({
          url: this.avatarUrl,
          imageSize: this.avatarSize,
          radius: this.getRadius(),
          onDecodeFailed: () => {
            // GIF 解码失败时仍保留静态兜底，但避免无限重试
            this.failedUrl = this.avatarUrl;
          }
        })
      } else {
        Image(this.avatarUrl)
          .width(this.avatarSize)
          .height(this.avatarSize)
          .borderRadius(this.getRadius())
          .objectFit(ImageFit.Cover)
          .interpolation(ImageInterpolation.Medium)
          .onError(() => {
            this.failedUrl = this.avatarUrl;
          })
      }
    } else if (this.fallbackText.length > 0) {
      // Fallback：首字母大写 + 主色背景
      Text(this.fallbackText.charAt(0).toUpperCase())
        .width(this.avatarSize)
        .height(this.avatarSize)
        .borderRadius(this.getRadius())
        .backgroundColor(this.bgColor.length > 0 ? this.bgColor : '#E0E7FF')
        .textAlign(TextAlign.Center)
        .fontSize(this.avatarSize * 0.45)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.primary'))
    } else {
      // 默认占位：人像图标
      Column() {
        SymbolGlyph($r('sys.symbol.person'))
          .fontSize(this.avatarSize * 0.55)
          .fontColor([$r('app.color.on_surface_secondary')])
      }
      .width(this.avatarSize)
      .height(this.avatarSize)
      .borderRadius(this.getRadius())
      .backgroundColor('#E8EAF0')
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
    }
  }
}
