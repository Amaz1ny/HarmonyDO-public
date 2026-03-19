import { EmojiResolver } from '../../common/utils/EmojiResolver';

@ComponentV2
export struct UserStatusEmoji {
  @Param rawEmoji: string = '';
  @Param iconSize: number = 16;
  @Param marginLeft: number = 4;

  @Local private failedUrl: string = '';

  @Monitor('rawEmoji')
  onRawEmojiChange(): void {
    this.failedUrl = '';
  }

  private getRawEmojiText(): string {
    return this.rawEmoji !== undefined && this.rawEmoji !== null ? this.rawEmoji.toString().trim() : '';
  }

  private getEmojiUrl(): string {
    const raw: string = this.getRawEmojiText();
    if (raw.length === 0) return '';
    return EmojiResolver.resolveEmojiUrl(raw);
  }

  build() {
    Row() {
      if (this.getRawEmojiText().length > 0) {
        if (this.getEmojiUrl().length > 0 && this.failedUrl !== this.getEmojiUrl()) {
          Image(this.getEmojiUrl())
            .width(this.iconSize)
            .height(this.iconSize)
            .objectFit(ImageFit.Contain)
            .margin({ left: this.marginLeft })
            .onError(() => {
              this.failedUrl = this.getEmojiUrl();
            })
        } else {
          Text(this.getRawEmojiText())
            .fontSize(this.iconSize)
            .fontColor($r('app.color.on_surface'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .margin({ left: this.marginLeft })
        }
      }
    }
  }
}
