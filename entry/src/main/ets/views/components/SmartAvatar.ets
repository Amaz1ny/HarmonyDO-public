/**
 * 智能头像组件
 *
 * 行为：
 * - 有 URL 时：CachedNetworkImage 加载圆形裁剪头像
 * - 无 URL 但有 fallbackText 时：取首字母大写居中，主色背景
 * - 都没有时：👤 图标占位
 *
 * 支持按 URL、文本与默认图标回退显示头像。
 */
import { UrlUtils } from '../../common/utils/UrlUtils';
import { PreloadedDataService } from '../../services/messagebus/PreloadedDataService';
import { AnimatedGifImage } from './AnimatedGifImage';
import { ThemeManager } from '../../common/theme/ThemeManager';

@ComponentV2
export struct SmartAvatar {
  @Param avatarUrl: string = '';
  @Param avatarSize: number = 36;
  @Param avatarRadius: number = -1;
  @Param fallbackText: string = '';
  @Param bgColor: string = '';
  @Param fallbackFontColor: string | Resource = ThemeManager.getCurrentAccentColorHex();
  @Param useNeutralPlaceholderResource: boolean = true;
  @Local private displayUrl: string = '';
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

  private isNeutralPlaceholderBg(): boolean {
    const raw: string = this.bgColor !== undefined && this.bgColor !== null ? this.bgColor.trim().toUpperCase() : '';
    return raw === '#E8EAF0';
  }

  private shouldUseNeutralPlaceholderResource(): boolean {
    return this.useNeutralPlaceholderResource && this.isNeutralPlaceholderBg();
  }

  aboutToAppear(): void {
    this.refreshDisplayUrl(true);
    this.ensureImageHostConfigLoaded();
  }

  @Monitor('avatarUrl')
  onAvatarUrlChange(): void {
    this.refreshDisplayUrl(true);
    this.ensureImageHostConfigLoaded();
  }

  private refreshDisplayUrl(resetFailedState: boolean = false): void {
    const nextUrl: string = UrlUtils.resolveUrl(this.avatarUrl);
    if (resetFailedState && nextUrl !== this.displayUrl) {
      this.failedUrl = '';
    }
    this.displayUrl = nextUrl;
  }

  private ensureImageHostConfigLoaded(): void {
    const raw: string = this.avatarUrl !== undefined && this.avatarUrl !== null ? this.avatarUrl.trim() : '';
    if (raw.length === 0) {
      return;
    }
    PreloadedDataService.getInstance().ensureConfigLoaded(true)
      .then(() => {
        const nextUrl: string = UrlUtils.resolveUrl(this.avatarUrl);
        if (nextUrl !== this.displayUrl) {
          this.failedUrl = '';
          this.displayUrl = nextUrl;
        }
      })
      .catch(() => {
      });
  }

  build() {
    if (this.displayUrl.length > 0 && this.displayUrl !== this.failedUrl) {
      if (this.isGifUrl(this.displayUrl)) {
        AnimatedGifImage({
          url: this.displayUrl,
          imageSize: this.avatarSize,
          radius: this.getRadius(),
          onDecodeFailed: () => {
            // GIF 解码失败时仍保留静态兜底，但避免无限重试
            this.failedUrl = this.displayUrl;
          }
        })
      } else {
        Image(this.displayUrl)
          .width(this.avatarSize)
          .height(this.avatarSize)
          .borderRadius(this.getRadius())
          .objectFit(ImageFit.Cover)
          .interpolation(ImageInterpolation.Medium)
          .onError(() => {
            this.failedUrl = this.displayUrl;
          })
      }
    } else if (this.fallbackText.length > 0) {
      // Fallback：首字母大写 + 主色背景
      if (this.bgColor.length > 0 && !this.shouldUseNeutralPlaceholderResource()) {
        Text(this.fallbackText.charAt(0).toUpperCase())
          .width(this.avatarSize)
          .height(this.avatarSize)
          .borderRadius(this.getRadius())
          .backgroundColor(this.bgColor)
          .textAlign(TextAlign.Center)
          .fontSize(this.avatarSize * 0.45)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.fallbackFontColor)
      } else if (this.bgColor.length > 0) {
        Text(this.fallbackText.charAt(0).toUpperCase())
          .width(this.avatarSize)
          .height(this.avatarSize)
          .borderRadius(this.getRadius())
          .backgroundColor($r('app.color.avatar_placeholder'))
          .textAlign(TextAlign.Center)
          .fontSize(this.avatarSize * 0.45)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.fallbackFontColor)
      } else {
        Text(this.fallbackText.charAt(0).toUpperCase())
          .width(this.avatarSize)
          .height(this.avatarSize)
          .borderRadius(this.getRadius())
          .backgroundColor(ThemeManager.getCurrentAccentSelectedBackgroundColorHex())
          .textAlign(TextAlign.Center)
          .fontSize(this.avatarSize * 0.45)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.fallbackFontColor)
      }
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
      .backgroundColor($r('app.color.avatar_placeholder'))
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
    }
  }
}
