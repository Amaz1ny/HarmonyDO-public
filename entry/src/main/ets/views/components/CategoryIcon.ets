import { Category } from '../../models/Category';
import { UrlUtils } from '../../common/utils/UrlUtils';

@ComponentV2
export struct CategoryIcon {
  @Param category: Category | null = null;
  @Param parent: Category | null = null;
  // 不能命名为 size（会与 ArkUI 的内置属性冲突，导致编译失败）
  @Param iconSize: number = 20;
  @Param color: string = '#999999';
  @Param preferImage: boolean = false; // 保留参数位，避免调用方大面积改动（当前始终优先图片）

  @Local private failedUrl: string = '';

  private getLogoUrl(): string {
    if (this.category === null) return '';
    const own: string | null = (this.category as Category).uploadedLogo;
    if (own !== null && (own as string).length > 0) return own as string;

    if (this.parent !== null) {
      const p: string | null = (this.parent as Category).uploadedLogo;
      if (p !== null && (p as string).length > 0) return p as string;
    }
    return '';
  }

  private getDotSize(): number {
    return Math.max(6, this.iconSize * 0.5);
  }

  build() {
    // 分类图标：按你反馈“可直接获取到”——统一优先渲染后端 uploaded_logo（含父级兜底）
    // 仅标签 icon 才做 sys.symbol 近似映射（分类不做 symbol 映射，避免不一致）。
    Row() {
      if (this.getLogoUrl().length > 0 && this.getLogoUrl() !== this.failedUrl) {
        Image(UrlUtils.resolveUrl(this.getLogoUrl()))
          .width(this.iconSize)
          .height(this.iconSize)
          .objectFit(ImageFit.Contain)
          .onError(() => {
            this.failedUrl = this.getLogoUrl();
          })
      } else if (this.category !== null && (this.category as Category).readRestricted) {
        SymbolGlyph($r('sys.symbol.lock'))
          .fontSize(this.iconSize * 0.7)
          .fontColor([this.color])
      } else {
        Circle()
          .width(this.getDotSize())
          .height(this.getDotSize())
          .fill(this.color)
      }
    }
    .width(this.iconSize)
    .height(this.iconSize)
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
  }
}
