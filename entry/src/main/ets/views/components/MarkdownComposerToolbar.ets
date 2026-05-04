import { ThemeManager } from '../../common/theme/ThemeManager';

@ComponentV2
export struct MarkdownComposerToolbar {
  @Param isPreview: boolean = false;
  @Param showPreviewButton: boolean = true;
  @Param isEmojiActive: boolean = false;
  @Param isImageUploading: boolean = false;
  @Param imageUploadProgressLabel: string = '';
  @Event onInsertEmoji: () => void = () => {
  };
  @Event onInsertImage: () => void = () => {
  };
  @Event onInsertHeading: () => void = () => {
  };
  @Event onInsertBold: () => void = () => {
  };
  @Event onInsertItalic: () => void = () => {
  };
  @Event onApplyPangu: () => void = () => {
  };
  @Event onTogglePreview: () => void = () => {
  };

  @Builder
  private DividerLine() {
    Column() {
    }
    .width(1)
    .height(22)
    .backgroundColor($r('app.color.divider_light'))
    .margin({ left: 4, right: 4 })
  }

  private getImageButtonWidth(): number {
    return this.isImageUploading && this.imageUploadProgressLabel.length > 0 ? 56 : 44;
  }

  @Builder
  private GlyphButton(symbol: Resource, onTap: () => void, active: boolean = false) {
    Row() {
      SymbolGlyph(symbol)
        .fontSize(20)
        .fontColor([active ? ThemeManager.getCurrentAccentColorHex() : $r('app.color.on_surface_secondary')])
    }
    .width(44)
    .height(44)
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
    .borderRadius(12)
    .backgroundColor(active ? ThemeManager.getCurrentAccentSelectedBackgroundColorHex() : Color.Transparent)
    .onClick(() => {
      onTap();
    })
  }

  @Builder
  private ImageButton() {
    Row() {
      if (this.isImageUploading && this.imageUploadProgressLabel.length > 0) {
        Text(this.imageUploadProgressLabel)
          .fontSize(11)
          .fontWeight(FontWeight.Medium)
          .fontColor(ThemeManager.getCurrentAccentColorHex())
      } else if (this.isImageUploading) {
        LoadingProgress()
          .width(18)
          .height(18)
      } else {
        Text('图')
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.on_surface_secondary'))
      }
    }
    .width(this.getImageButtonWidth())
    .height(44)
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
    .borderRadius(12)
    .onClick(() => {
      if (!this.isImageUploading) {
        this.onInsertImage();
      }
    })
  }

  @Builder
  private TextButton(label: string, onTap: () => void, bold: boolean = false, italic: boolean = false) {
    Row() {
      Text(label)
        .fontSize(label.length > 1 ? 13 : 18)
        .fontWeight(bold ? FontWeight.Bold : FontWeight.Medium)
        .fontStyle(italic ? FontStyle.Italic : FontStyle.Normal)
        .fontColor($r('app.color.on_surface_secondary'))
    }
    .padding({ left: 10, right: 10 })
    .height(44)
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
    .borderRadius(12)
    .onClick(() => {
      onTap();
    })
  }

  build() {
    Row() {
      this.GlyphButton($r('sys.symbol.face_smiling'), this.onInsertEmoji, this.isEmojiActive)
      this.DividerLine()

      Scroll() {
        Row() {
          this.ImageButton()
          this.TextButton('H', this.onInsertHeading, true, false)
          this.TextButton('B', this.onInsertBold, true, false)
          this.TextButton('I', this.onInsertItalic, false, true)
          this.DividerLine()
          this.TextButton('A+', this.onApplyPangu, false, false)
        }
        .alignItems(VerticalAlign.Center)
      }
      .layoutWeight(1)
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)

      if (this.showPreviewButton) {
        this.DividerLine()
        this.GlyphButton($r('sys.symbol.eye'), this.onTogglePreview, this.isPreview)
      }
    }
    .width('100%')
    .height(56)
    .padding({ left: 8, right: 8 })
    .alignItems(VerticalAlign.Center)
    .backgroundColor(ThemeManager.getCurrentAccentSurfaceColorHex())
    .border({ width: { top: 0.5 }, color: $r('app.color.divider_light') })
  }
}
