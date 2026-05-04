import { Emoji } from '../../models/Emoji';
import { ComposerEmojiPanel } from './ComposerEmojiPanel';
import { ComposerStickerPanel } from './ComposerStickerPanel';
import { ThemeManager } from '../../common/theme/ThemeManager';

type ComposerPanelTabKey = 'emoji' | 'sticker';

@ComponentV2
export struct ComposerEmojiStickerPanel {
  @Param panelHeight: number = 320;
  @Param showHandle: boolean = true;
  @Event onSelectEmoji: (emoji: Emoji) => void = (_: Emoji) => {
  };
  @Event onSelectSticker: (markdown: string) => void = (_: string) => {
  };

  @Local private selectedTabKey: ComposerPanelTabKey = 'emoji';

  private getContentHeight(): number {
    const reservedHeight: number = (this.showHandle ? 14 : 0) + 52;
    const nextHeight: number = this.panelHeight - reservedHeight;
    return nextHeight > 220 ? nextHeight : 220;
  }

  @Builder
  private Handle() {
    if (this.showHandle) {
      Rect()
        .width(32)
        .height(4)
        .radius(2)
        .fill($r('app.color.divider_light'))
        .margin({ top: 6, bottom: 4 })
    }
  }

  @Builder
  private TabButton(key: ComposerPanelTabKey, label: string) {
    Row() {
      Text(label)
        .fontSize(13)
        .fontWeight(this.selectedTabKey === key ? FontWeight.Medium : FontWeight.Regular)
        .fontColor(this.selectedTabKey === key ? ThemeManager.getCurrentAccentColorHex() : $r('app.color.on_surface_secondary'))
    }
    .padding({ left: 16, right: 16, top: 9, bottom: 9 })
    .backgroundColor(this.selectedTabKey === key
      ? ThemeManager.getCurrentAccentSelectedBackgroundColorHex()
      : ThemeManager.getCurrentAccentSurfaceVariantColorHex())
    .borderRadius(18)
    .onClick(() => {
      this.selectedTabKey = key;
    })
  }

  build() {
    Column() {
      this.Handle()

      Row() {
        this.TabButton('emoji', '表情')
        Blank().width(8)
        this.TabButton('sticker', '表情包')
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 4, bottom: 8 })
      .alignItems(VerticalAlign.Center)

      if (this.selectedTabKey === 'emoji') {
        ComposerEmojiPanel({
          panelHeight: this.getContentHeight(),
          showHandle: false,
          onSelectEmoji: (emoji: Emoji) => {
            this.onSelectEmoji(emoji);
          }
        })
      } else {
        ComposerStickerPanel({
          panelHeight: this.getContentHeight(),
          showHandle: false,
          onSelectSticker: (markdown: string) => {
            this.onSelectSticker(markdown);
          }
        })
      }
    }
    .width('100%')
    .height(this.panelHeight)
    .backgroundColor(ThemeManager.getCurrentAccentSurfaceColorHex())
  }
}
