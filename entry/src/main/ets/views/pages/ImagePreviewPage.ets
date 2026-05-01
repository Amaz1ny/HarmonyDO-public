import { HdsNavDestination } from '@kit.UIDesignKit';
import { WindowManager } from '../../common/utils/WindowManager';
import { RouterManager } from '../../common/utils/RouterManager';
import { AppContext } from '../../common/utils/AppContext';
import { ClipboardService } from '../../common/utils/ClipboardService';
import { ExternalLinkService } from '../../common/utils/ExternalLinkService';
import { MediaSaveService } from '../../common/utils/MediaSaveService';
import { SystemShareService } from '../../common/utils/SystemShareService';
import { ToastService } from '../../common/utils/ToastService';
import { DownloadedImage, ImageDownloadService } from '../../common/utils/ImageDownloadService';
import { ZoomableImage } from '../components/ZoomableImage';
import { ImagePreviewChromeHelper } from '../components/ImagePreviewChromeHelper';

@ComponentV2
export struct ImagePreviewPage {
  @Param urls: string[] = [];
  @Param initialIndex: number = 0;

  @Local currentIndex: number = 0;
  @Local private isActionSheetVisible: boolean = false;
  @Local private isDownloading: boolean = false;
  @Local private swipeDisabled: boolean = false;
  @Local private downloaded: DownloadedImage | null = null;

  aboutToAppear(): void {
    const total: number = this.urls.length;
    let idx: number = this.initialIndex;
    if (idx < 0) idx = 0;
    if (total > 0 && idx >= total) idx = total - 1;
    this.currentIndex = idx;
  }

  private getCurrentUrl(): string {
    if (this.urls.length === 0) return '';
    let idx: number = this.currentIndex;
    if (idx < 0) idx = 0;
    if (idx >= this.urls.length) idx = this.urls.length - 1;
    const u: string = this.urls[idx] !== undefined && this.urls[idx] !== null ? (this.urls[idx] as string).trim() : '';
    return u;
  }

  private clearDownloadedCache(): void {
    this.downloaded = null;
  }

  private async ensureDownloaded(): Promise<DownloadedImage | null> {
    const url: string = this.getCurrentUrl();
    if (url.length === 0) {
      ToastService.show('图片链接为空');
      return null;
    }

    if (this.downloaded !== null) {
      const cached: DownloadedImage = this.downloaded as DownloadedImage;
      if (cached.ok && cached.url === url && cached.bytes !== null && (cached.bytes as ArrayBuffer).byteLength > 0) {
        return cached;
      }
    }

    if (this.isDownloading) return null;
    this.isDownloading = true;
    const result: DownloadedImage = await ImageDownloadService.download(url);
    this.isDownloading = false;

    if (!result.ok) {
      ToastService.show(result.errorMessage.length > 0 ? result.errorMessage : '下载失败');
      return null;
    }
    this.downloaded = result;
    return result;
  }

  private async saveToGallery(): Promise<void> {
    const ctx = AppContext.getUIAbilityContext();
    if (ctx === null) {
      ToastService.show('系统能力不可用');
      return;
    }

    const d: DownloadedImage | null = await this.ensureDownloaded();
    if (d === null) return;
    if (d.bytes === null) {
      ToastService.show('图片数据不可用');
      return;
    }

    const ok: boolean = await MediaSaveService.saveImageBytesToGallery(
      ctx,
      d.bytes as ArrayBuffer,
      d.mime.length > 0 ? d.mime : d.ext,
      'image'
    );
    if (ok) {
      ToastService.show('已保存到相册');
    } else {
      ToastService.show('保存失败，请检查权限或系统限制');
    }
  }

  private async shareCurrentImage(): Promise<void> {
    const d: DownloadedImage | null = await this.ensureDownloaded();
    if (d === null) return;
    const ok: boolean = await SystemShareService.shareImage(d.fileUri, '', false);
    if (!ok) {
      ToastService.showShareFailed();
    }
  }

  private copyLink(): void {
    const url: string = this.getCurrentUrl();
    if (url.length === 0) return;
    ClipboardService.copyText(url, true).catch((_: Object) => {
    });
  }

  private getIndexText(): string {
    const total: number = this.urls.length;
    if (total <= 0) return '';
    const cur: number = this.currentIndex + 1;
    return `${cur}/${total}`;
  }

  build() {
    HdsNavDestination() {
      Stack() {
        if (this.urls.length > 0) {
          Swiper() {
            ForEach(this.urls, (u: string) => {
              Column() {
                ZoomableImage({
                  url: u,
                  onScaleChange: (scale: number) => {
                    const cur: string = this.getCurrentUrl();
                    if (cur === u) {
                      this.swipeDisabled = scale > 1.01;
                    }
                  },
                  onLongPress: () => {
                    const cur: string = this.getCurrentUrl();
                    if (cur === u) {
                      this.isActionSheetVisible = true;
                    }
                  }
                })
                  .width('100%')
                  .height('100%')
              }
              .width('100%')
              .height('100%')
              .justifyContent(FlexAlign.Center)
              .alignItems(HorizontalAlign.Center)
            }, (u: string) => u)
          }
          .index(this.currentIndex)
          .loop(false)
          .indicator(false)
          .disableSwipe(this.swipeDisabled)
          .onChange((index: number) => {
            if (index !== this.currentIndex) {
              this.currentIndex = index;
              this.swipeDisabled = false;
              this.clearDownloadedCache();
            }
          })
          .width('100%')
          .height('100%')
        } else {
          Column() {
            Text('暂无图片')
              .fontSize(14)
              .fontColor($r('app.color.badge_text'))
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
        }

        this.FloatingControls()

        Column() {
        }
        .width(0)
        .height(0)
        .bindSheet($$this.isActionSheetVisible, this.ActionSheetBuilder, {
          height: SheetSize.FIT_CONTENT,
          dragBar: true,
          showClose: false,
          backgroundColor: $r('app.color.surface')
        })
      }
      .width('100%')
      .height('100%')
    }
    .backgroundColor($r('app.color.image_preview_background'))
    .hideTitleBar(true)
    .hideToolBar(true)
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
    .systemBarStyle(
      { statusBarContentColor: ImagePreviewChromeHelper.getStatusBarContentColor() },
      { statusBarContentColor: ImagePreviewChromeHelper.getStatusBarContentColor() }
    )
  }

  @Builder
  FloatingControls() {
    Column() {
      Row() {
        // 返回按钮（左上角浮动圆形）
        this.FloatingIconButton($r('sys.symbol.chevron_left'), 1, () => {
          RouterManager.pop();
        })

        Blank().layoutWeight(1)

        // 画廊指示器（多图时居中显示）
        if (this.urls.length > 1) {
          this.FloatingIndexIndicator()
        }

        Blank().layoutWeight(1)

        // 保存按钮（右上角浮动圆形）
        this.FloatingIconButton($r('sys.symbol.arrow_down'), this.isDownloading ? 0.6 : 1, () => {
          if (this.isDownloading) return;
          this.saveToGallery();
        })
      }
      .width('100%')
      .padding({
        left: ImagePreviewChromeHelper.getControlHorizontalPaddingVp(),
        right: ImagePreviewChromeHelper.getControlHorizontalPaddingVp()
      })
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .position({ x: 0, y: ImagePreviewChromeHelper.getTopControlsOffsetVp() })
  }

  @Builder
  private FloatingIconButton(icon: Resource, buttonOpacity: number, onClick: () => void) {
    Row() {
      SymbolGlyph(icon)
        .fontSize(ImagePreviewChromeHelper.getControlIconSizeVp())
        .fontColor([$r('app.color.image_preview_control_icon')])
    }
    .width(ImagePreviewChromeHelper.getControlSizeVp())
    .height(ImagePreviewChromeHelper.getControlSizeVp())
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
    .backgroundColor(Color.Transparent)
    .backgroundEffect(
      {
        radius: ImagePreviewChromeHelper.getControlBlurRadiusVp(),
        saturation: 1.7,
        brightness: 1.08,
        color: $r('app.color.image_preview_control_tint'),
        adaptiveColor: AdaptiveColor.DEFAULT,
        policy: BlurStyleActivePolicy.ALWAYS_ACTIVE,
        inactiveColor: $r('app.color.image_preview_control_tint')
      },
      { disableSystemAdaptation: true }
    )
    .border({ width: 0.5, color: $r('app.color.image_preview_control_stroke') })
    .borderRadius(ImagePreviewChromeHelper.getControlRadiusVp())
    .shadow({ radius: 14, color: $r('app.color.image_preview_control_shadow'), offsetX: 0, offsetY: 6 })
    .opacity(buttonOpacity)
    .onClick(() => {
      onClick();
    })
  }

  @Builder
  private FloatingIndexIndicator() {
    Row() {
      Text(this.getIndexText())
        .fontSize(14)
        .fontColor($r('app.color.image_preview_control_icon'))
    }
    .height(ImagePreviewChromeHelper.getIndicatorHeightVp())
    .padding({ left: 12, right: 12 })
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
    .backgroundColor(Color.Transparent)
    .backgroundEffect(
      {
        radius: ImagePreviewChromeHelper.getControlBlurRadiusVp(),
        saturation: 1.7,
        brightness: 1.08,
        color: $r('app.color.image_preview_control_tint'),
        adaptiveColor: AdaptiveColor.DEFAULT,
        policy: BlurStyleActivePolicy.ALWAYS_ACTIVE,
        inactiveColor: $r('app.color.image_preview_control_tint')
      },
      { disableSystemAdaptation: true }
    )
    .border({ width: 0.5, color: $r('app.color.image_preview_control_stroke') })
    .borderRadius(ImagePreviewChromeHelper.getControlRadiusVp())
    .shadow({ radius: 14, color: $r('app.color.image_preview_control_shadow'), offsetX: 0, offsetY: 6 })
  }

  @Builder
  ActionSheetBuilder() {
    Column() {
      this.ActionItem($r('sys.symbol.doc_text'), '复制图片', () => {
        this.isActionSheetVisible = false;
        this.copyLink();
      })

      this.ActionItem($r('sys.symbol.link'), '复制链接', () => {
        this.isActionSheetVisible = false;
        this.copyLink();
      })

      this.ActionItem($r('sys.symbol.share'), '分享图片', () => {
        this.isActionSheetVisible = false;
        if (this.isDownloading) return;
        this.shareCurrentImage();
      })

      Blank().height(16 + WindowManager.getSystemAvoidAreaBottomVp())
    }
    .width('100%')
    .padding({ top: 8 })
    .backgroundColor($r('app.color.surface'))
  }

  @Builder
  private ActionItem(icon: Resource, title: string, onClick: () => void) {
    Row() {
      SymbolGlyph(icon)
        .fontSize(20)
        .fontColor([$r('app.color.on_surface')])
        .margin({ right: 16 })
      Text(title)
        .fontSize(16)
        .fontColor($r('app.color.on_surface'))
    }
    .width('100%')
    .height(52)
    .padding({ left: 20, right: 20 })
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      onClick();
    })
  }
}
