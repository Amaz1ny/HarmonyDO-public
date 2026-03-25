import { ApiClient, PostEnqueuedError } from '../../services/network/ApiClient';
import { Draft, DraftData } from '../../models/Draft';
import { Post } from '../../models/Post';
import { ThemeManager } from '../../common/theme/ThemeManager';
import { WindowManager } from '../../common/utils/WindowManager';
import { LoadingSpinner } from './LoadingSpinner';
import { SmartAvatar } from './SmartAvatar';
import { ToastService } from '../../common/utils/ToastService';
import { UrlUtils } from '../../common/utils/UrlUtils';
import { MarkdownComposerToolbar } from './MarkdownComposerToolbar';
import { ComposerEmojiStickerPanel } from './ComposerEmojiStickerPanel';
import { MarkdownComposerUtils } from '../../common/utils/MarkdownComposerUtils';
import { PostRichContent } from './PostRichContent';
import { Emoji } from '../../models/Emoji';
import { ComposerImageUploadService } from '../../common/utils/ComposerImageUploadService';

@ComponentV2
export struct ReplyComposerSheet {
  @Param topicId: number = 0;
  @Param replyToPostNumber: number = 0;
  @Param replyToUsername: string = '';
  @Param replyToAvatarTemplate: string = '';
  @Param initialContent: string = '';
  @Param requestKey: string = '';
  @Event onSubmitted: (post: Post) => void = (_: Post) => {
  };
  @Event onDismiss: (submitted: boolean) => void = (_: boolean) => {
  };

  @Local private content: string = '';
  @Local private isLoadingDraft: boolean = false;
  @Local private isSubmitting: boolean = false;
  @Local private errorMessage: string = '';
  @Local private draftSequence: number = 0;
  @Local private isPreview: boolean = false;
  @Local private isEmojiPanelVisible: boolean = false;
  @Local private isDiscardConfirmVisible: boolean = false;
  @Local private contentSelectionStart: number = 0;
  @Local private contentSelectionEnd: number = 0;
  @Local private isImageUploading: boolean = false;
  @Local private imageUploadProgressLabel: string = '';

  private draftSaveTimerId: number = -1;
  private submitted: boolean = false;
  private loadRequestId: number = 0;
  private readonly contentController: TextAreaController = new TextAreaController();
  private readonly emojiPanelHeight: number = 320;

  aboutToAppear(): void {
    this.resetComposerState();
    ApiClient.getInstance().getSiteInfo().catch((_: Object) => {
    });
    this.loadDraft();
  }

  @Monitor('requestKey')
  private onRequestKeyChange(): void {
    this.resetComposerState();
    this.loadDraft();
  }

  aboutToDisappear(): void {
    this.clearDraftSaveTimer();
    if (!this.submitted) {
      this.flushDraft().catch((_: Object) => {
      });
    }
  }

  private resetComposerState(): void {
    this.submitted = false;
    this.content = this.initialContent;
    this.syncContentSelection(this.content.length, this.content.length);
    this.errorMessage = '';
    this.draftSequence = 0;
    this.isLoadingDraft = false;
    this.isSubmitting = false;
    this.isPreview = false;
    this.isEmojiPanelVisible = false;
    this.isDiscardConfirmVisible = false;
    this.isImageUploading = false;
    this.imageUploadProgressLabel = '';
  }

  private getDraftKey(): string {
    return Draft.replyKey(this.topicId, this.replyToPostNumber);
  }

  private getMinContentLength(): number {
    return 10;
  }

  /**
   * CJK 字符计为 2 个有效字符（与 Discourse 服务端一致）
   */
  private getEffectiveLength(text: string): number {
    let length: number = 0;
    for (let i: number = 0; i < text.length; i++) {
      const code: number = text.charCodeAt(i);
      if ((code >= 0x4E00 && code <= 0x9FFF) ||
        (code >= 0x3400 && code <= 0x4DBF) ||
        (code >= 0x3040 && code <= 0x309F) ||
        (code >= 0x30A0 && code <= 0x30FF) ||
        (code >= 0xAC00 && code <= 0xD7AF) ||
        (code >= 0xFF01 && code <= 0xFF5E)) {
        length = length + 2;
      } else {
        length = length + 1;
      }
    }
    return length;
  }

  private getToolbarHeight(): number {
    return 56 + WindowManager.getSystemAvoidAreaBottomVp();
  }

  private getBottomToolbarSpacerHeight(): number {
    let height: number = this.getToolbarHeight();
    if (this.isEmojiPanelVisible && !this.isPreview) {
      height = height + this.emojiPanelHeight;
    }
    return height;
  }

  private clearDraftSaveTimer(): void {
    if (this.draftSaveTimerId >= 0) {
      clearTimeout(this.draftSaveTimerId);
      this.draftSaveTimerId = -1;
    }
  }

  private scheduleDraftSave(): void {
    if (this.submitted) {
      return;
    }
    this.clearDraftSaveTimer();
    this.draftSaveTimerId = setTimeout(() => {
      this.persistDraft().catch((_: Object) => {
      });
    }, 700);
  }

  private async loadDraft(): Promise<void> {
    if (this.topicId <= 0) {
      return;
    }
    const requestId: number = this.loadRequestId + 1;
    this.loadRequestId = requestId;
    this.isLoadingDraft = true;
    try {
      const apiClient: ApiClient = ApiClient.getInstance();
      const draft: Draft | null = await apiClient.getDraft(this.getDraftKey());
      if (requestId !== this.loadRequestId) {
        return;
      }
      if (draft !== null && draft.hasContent) {
        this.draftSequence = draft.sequence;
        const draftReply: string = draft.data.reply !== null ? draft.data.reply as string : '';
        if (draftReply.trim().length > 0) {
          if (this.initialContent.trim().length > 0) {
            this.content = `${this.initialContent}${draftReply}`;
          } else {
            this.content = draftReply;
          }
          this.syncContentSelection(this.content.length, this.content.length);
        }
      }
    } catch (err) {
      this.errorMessage = err !== undefined && err !== null
        ? err.toString().replace('Error: ', '')
        : '加载草稿失败';
    } finally {
      if (requestId === this.loadRequestId) {
        this.isLoadingDraft = false;
      }
    }
  }

  private async persistDraft(): Promise<void> {
    if (this.topicId <= 0 || this.submitted) {
      return;
    }
    const apiClient: ApiClient = ApiClient.getInstance();
    const trimmed: string = this.content.trim();
    if (trimmed.length === 0) {
      await apiClient.deleteDraft(this.getDraftKey(), this.draftSequence);
      this.draftSequence = 0;
      return;
    }

    const data: DraftData = new DraftData();
    data.reply = this.content;
    data.replyToPostNumber = this.replyToPostNumber > 0 ? this.replyToPostNumber : null;
    data.action = 'reply';
    data.archetypeId = 'regular';
    this.draftSequence = await apiClient.saveDraft(this.getDraftKey(), data, this.draftSequence);
  }

  private async flushDraft(): Promise<void> {
    try {
      await this.persistDraft();
    } catch (_) {
    }
  }

  private async closeSheet(): Promise<void> {
    this.isDiscardConfirmVisible = false;
    await this.flushDraft();
    this.onDismiss(false);
  }

  private hasDraftLikeContent(): boolean {
    return this.content.trim().length > 0 || this.draftSequence > 0;
  }

  private requestDiscardDraft(): void {
    if (!this.hasDraftLikeContent()) {
      this.onDismiss(false);
      return;
    }
    this.isDiscardConfirmVisible = true;
  }

  private cancelDiscardDraft(): void {
    this.isDiscardConfirmVisible = false;
  }

  private async discardDraft(): Promise<void> {
    this.submitted = true;
    this.isDiscardConfirmVisible = false;
    this.clearDraftSaveTimer();
    try {
      await ApiClient.getInstance().deleteDraft(this.getDraftKey(), this.draftSequence);
    } catch (_) {
    }
    this.onDismiss(false);
  }

  private async submit(): Promise<void> {
    const trimmed: string = this.content.trim();
    if (trimmed.length === 0) {
      this.errorMessage = '请输入内容';
      this.isPreview = false;
      return;
    }
    if (this.getEffectiveLength(trimmed) < this.getMinContentLength()) {
      this.errorMessage = '回复内容太短';
      this.isPreview = false;
      return;
    }

    this.isSubmitting = true;
    this.errorMessage = '';
    try {
      const apiClient: ApiClient = ApiClient.getInstance();
      const post: Post = await apiClient.createReply(this.topicId, this.content, this.replyToPostNumber);
      this.submitted = true;
      await apiClient.deleteDraft(this.getDraftKey(), this.draftSequence);
      this.onSubmitted(post);
      this.onDismiss(true);
    } catch (err) {
      if (err instanceof PostEnqueuedError) {
        this.submitted = true;
        try {
          await ApiClient.getInstance().deleteDraft(this.getDraftKey(), this.draftSequence);
        } catch (_) {
        }
        ToastService.show('你的帖子已提交，正在等待审核');
        this.onDismiss(true);
      } else {
        this.errorMessage = err !== undefined && err !== null
          ? err.toString().replace('Error: ', '')
          : '发送失败';
      }
    } finally {
      this.isSubmitting = false;
    }
  }

  private getHeaderTitle(): string {
    if (this.replyToPostNumber > 0) {
      return `回复 #${this.replyToPostNumber}`;
    }
    return '回复话题';
  }

  private getReplyTargetAvatarUrl(): string {
    if (this.replyToAvatarTemplate.trim().length === 0) {
      return '';
    }
    return UrlUtils.getAvatarUrl(this.replyToAvatarTemplate, 80);
  }

  private getReplyTargetText(): string {
    if (this.replyToUsername.trim().length > 0) {
      return `回复 @${this.replyToUsername}`;
    }
    return `回复帖子 #${this.replyToPostNumber}`;
  }

  private syncContentSelection(selectionStart: number, selectionEnd: number): void {
    const max: number = this.content.length;
    let start: number = selectionStart;
    let end: number = selectionEnd;
    if (start < 0) {
      start = 0;
    }
    if (end < 0) {
      end = 0;
    }
    if (start > max) {
      start = max;
    }
    if (end > max) {
      end = max;
    }
    if (start > end) {
      const temp: number = start;
      start = end;
      end = temp;
    }
    this.contentSelectionStart = start;
    this.contentSelectionEnd = end;
  }

  private syncSelectionToTail(): void {
    this.syncContentSelection(this.content.length, this.content.length);
  }

  private restoreContentCaretAsync(selectionStart: number, selectionEnd: number): void {
    setTimeout(() => {
      try {
        this.contentController.setTextSelection(selectionStart, selectionEnd);
      } catch (_) {
        try {
          if (selectionStart === selectionEnd) {
            this.contentController.caretPosition(selectionStart);
          }
        } catch (_) {
        }
      }
    }, 16);
  }

  private closeEmojiPanel(): void {
    this.isEmojiPanelVisible = false;
  }

  private toggleEmojiPanel(): void {
    this.isPreview = false;
    const nextVisible: boolean = !this.isEmojiPanelVisible;
    if (nextVisible) {
      try {
        this.contentController.stopEditing();
      } catch (_) {
      }
    }
    this.isEmojiPanelVisible = nextVisible;
  }

  private insertEmoji(emoji: Emoji): void {
    const result = MarkdownComposerUtils.insertEmojiShortcode(
      this.content,
      emoji.name,
      this.contentSelectionStart,
      this.contentSelectionEnd
    );
    if (result.text === this.content) {
      return;
    }
    this.content = result.text;
    this.syncContentSelection(result.selectionStart, result.selectionEnd);
    this.isPreview = false;
    this.errorMessage = '';
    this.scheduleDraftSave();
    this.restoreContentCaretAsync(result.selectionStart, result.selectionEnd);
  }

  private insertSticker(markdown: string): void {
    const result = MarkdownComposerUtils.insertStickerMarkdown(
      this.content,
      markdown,
      this.contentSelectionStart,
      this.contentSelectionEnd
    );
    if (result.text === this.content) {
      return;
    }
    this.content = result.text;
    this.syncContentSelection(result.selectionStart, result.selectionEnd);
    this.isPreview = false;
    this.errorMessage = '';
    this.scheduleDraftSave();
    this.restoreContentCaretAsync(result.selectionStart, result.selectionEnd);
  }

  private async pickAndUploadImages(): Promise<void> {
    if (this.isSubmitting || this.isImageUploading) {
      return;
    }

    this.isPreview = false;
    this.closeEmojiPanel();
    try {
      this.contentController.stopEditing();
    } catch (_) {
    }
    this.errorMessage = '';
    this.isImageUploading = true;
    this.imageUploadProgressLabel = '';

    try {
      const markdowns: string[] = await ComposerImageUploadService.pickAndUploadMarkdowns(
        9,
        (current: number, total: number): void => {
          this.imageUploadProgressLabel = total > 1 ? `${current}/${total}` : '';
        }
      );
      if (markdowns.length === 0) {
        return;
      }

      const result = MarkdownComposerUtils.insertImageMarkdowns(
        this.content,
        markdowns,
        this.contentSelectionStart,
        this.contentSelectionEnd
      );
      if (result.text === this.content) {
        return;
      }

      this.content = result.text;
      this.syncContentSelection(result.selectionStart, result.selectionEnd);
      this.errorMessage = '';
      this.scheduleDraftSave();
      this.restoreContentCaretAsync(result.selectionStart, result.selectionEnd);
      if (MarkdownComposerUtils.shouldWrapImagesWithGrid(markdowns.length)) {
        ToastService.show(`已插入 ${markdowns.length} 张图片（网格）`);
      } else {
        ToastService.show(markdowns.length > 1 ? `已插入 ${markdowns.length} 张图片` : '图片已插入');
      }
    } catch (err) {
      const message: string = err !== undefined && err !== null
        ? err.toString().replace('Error: ', '')
        : '图片上传失败';
      this.errorMessage = message;
      ToastService.show(message);
    } finally {
      this.isImageUploading = false;
      this.imageUploadProgressLabel = '';
    }
  }

  private applyContentTransform(transform: (text: string) => string): void {
    const next: string = transform(this.content);
    if (next === this.content) {
      return;
    }
    this.content = next;
    this.syncSelectionToTail();
    this.isPreview = false;
    this.closeEmojiPanel();
    this.errorMessage = '';
    this.scheduleDraftSave();
    this.restoreContentCaretAsync(this.contentSelectionStart, this.contentSelectionEnd);
  }

  private buildPreviewHtml(): string {
    return MarkdownComposerUtils.toPreviewHtml(this.content);
  }

  @Builder
  private ReplyTargetInfo() {
    if (this.replyToPostNumber > 0) {
      Row() {
        SmartAvatar({
          avatarUrl: this.getReplyTargetAvatarUrl(),
          avatarSize: 28,
          fallbackText: this.replyToUsername
        })

        Text(this.getReplyTargetText())
          .fontSize(13)
          .fontColor($r('app.color.on_surface_secondary'))
          .margin({ left: 10 })
          .layoutWeight(1)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .padding({ left: 16, right: 16, top: 8, bottom: 4 })
    }
  }

  @Builder
  private EditorBody() {
    if (this.isPreview) {
      Scroll() {
        PostRichContent({
          cookedHtml: this.buildPreviewHtml(),
          post: null,
          dense: false,
          quoteMode: false
        })
        .width('100%')
        .padding({ left: 16, right: 16, top: 16, bottom: 24 })
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
    } else {
      TextArea({
        text: this.content,
        placeholder: '输入回复内容...',
        controller: this.contentController
      })
        .width('100%')
        .layoutWeight(1)
        .padding({ left: 16, right: 16, top: 16, bottom: 24 })
        .backgroundColor(Color.Transparent)
        .fontSize(17)
        .lineHeight(27)
        .fontColor($r('app.color.on_surface'))
        .placeholderColor($r('app.color.on_surface_secondary'))
        .maxLength(20000)
        .copyOption(CopyOptions.LocalDevice)
        .onFocus(() => {
          this.closeEmojiPanel();
        })
        .onChange((value: string) => {
          this.content = value;
          this.errorMessage = '';
          this.scheduleDraftSave();
        })
        .onTextSelectionChange((selectionStart: number, selectionEnd: number) => {
          this.syncContentSelection(selectionStart, selectionEnd);
        })
    }
  }

  @Builder
  private DiscardConfirmOverlay() {
    if (this.isDiscardConfirmVisible) {
      Stack({ alignContent: Alignment.Center }) {
        Column() {
        }
        .width('100%')
        .height('100%')
        .backgroundColor('#66000000')
        .onClick(() => {
          this.cancelDiscardDraft();
        })

        Column() {
          Text('舍弃回复草稿？')
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.on_surface'))
            .width('100%')

          Text('当前回复内容和草稿都会被删除。')
            .fontSize(14)
            .fontColor($r('app.color.on_surface_secondary'))
            .width('100%')
            .margin({ top: 10 })

          Row() {
            Button('取消')
              .type(ButtonType.Capsule)
              .layoutWeight(1)
              .height(44)
              .backgroundColor($r('app.color.surface_variant'))
              .fontColor($r('app.color.on_surface_secondary'))
              .onClick(() => {
                this.cancelDiscardDraft();
              })

            Blank().width(12)

            Button('确认舍弃')
              .type(ButtonType.Capsule)
              .layoutWeight(1)
              .height(44)
              .backgroundColor($r('app.color.error'))
              .fontColor(Color.White)
              .onClick(() => {
                this.discardDraft().catch((_: Object) => {
                });
              })
          }
          .width('100%')
          .margin({ top: 20 })
        }
        .width('88%')
        .padding({ left: 20, right: 20, top: 22, bottom: 20 })
        .backgroundColor($r('app.color.surface'))
        .borderRadius(24)
      }
      .width('100%')
      .height('100%')
    }
  }

  private getDraftLoadingOverlayBackground(): string {
    return WindowManager.isDarkMode()
      ? ThemeManager.hexWithAlpha('#000000', 0.38)
      : '#55FFFFFF';
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      Column() {
        Column() {
        }
        .width(36)
        .height(4)
        .borderRadius(2)
        .backgroundColor($r('app.color.divider_light'))
        .margin({ top: 12, bottom: 12 })

        Row() {
          Text(this.getHeaderTitle())
            .fontSize(17)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.on_surface'))
            .layoutWeight(1)

          Text('关闭')
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.on_surface_secondary'))
            .padding({ left: 12, right: 12, top: 10, bottom: 10 })
            .onClick(() => {
              this.closeSheet().catch((_: Object) => {
              });
            })

          Text('舍弃')
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.on_surface_secondary'))
            .padding({ left: 12, right: 12, top: 10, bottom: 10 })
            .onClick(() => {
              this.requestDiscardDraft();
            })

          Button(this.isSubmitting ? '发送中...' : '发送')
            .type(ButtonType.Capsule)
            .height(40)
            .enabled(!this.isSubmitting)
            .backgroundColor($r('app.color.primary'))
            .fontColor(Color.White)
            .margin({ left: 8 })
            .onClick(() => {
              this.submit().catch((_: Object) => {
              });
            })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
        .padding({ left: 16, right: 16, bottom: 4 })

        this.ReplyTargetInfo()

        if (this.errorMessage.length > 0) {
          Text(this.errorMessage)
            .fontSize(12)
            .fontColor($r('app.color.warning'))
            .width('100%')
            .padding({ left: 16, right: 16, top: 4, bottom: 8 })
        }

        Text(`${this.content.length} 字`)
          .fontSize(12)
          .fontColor($r('app.color.on_surface_secondary'))
          .width('100%')
          .textAlign(TextAlign.End)
          .padding({ left: 16, right: 16, top: 4 })

        this.EditorBody()

        Blank().height(this.getBottomToolbarSpacerHeight())
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.surface'))

      if (this.isEmojiPanelVisible && !this.isPreview) {
        Column() {
          ComposerEmojiStickerPanel({
            panelHeight: this.emojiPanelHeight,
            onSelectEmoji: (emoji: Emoji) => {
              this.insertEmoji(emoji);
            },
            onSelectSticker: (markdown: string) => {
              this.insertSticker(markdown);
            }
          })
        }
        .width('100%')
        .margin({ bottom: this.getToolbarHeight() })
        .backgroundColor($r('app.color.surface'))
      }

      Column() {
        MarkdownComposerToolbar({
          isPreview: this.isPreview,
          showPreviewButton: true,
          isEmojiActive: this.isEmojiPanelVisible,
          isImageUploading: this.isImageUploading,
          imageUploadProgressLabel: this.imageUploadProgressLabel,
          onInsertEmoji: () => {
            this.toggleEmojiPanel();
          },
          onInsertImage: () => {
            this.pickAndUploadImages().catch((_: Object) => {
            });
          },
          onInsertHeading: () => {
            this.applyContentTransform(MarkdownComposerUtils.insertHeading);
          },
          onInsertBold: () => {
            this.applyContentTransform(MarkdownComposerUtils.insertBold);
          },
          onInsertItalic: () => {
            this.applyContentTransform(MarkdownComposerUtils.insertItalic);
          },
          onApplyPangu: () => {
            this.applyContentTransform(MarkdownComposerUtils.applyPanguSpacing);
          },
          onTogglePreview: () => {
            this.isPreview = !this.isPreview;
            if (this.isPreview) {
              try {
                this.contentController.stopEditing();
              } catch (_) {
              }
              this.closeEmojiPanel();
            }
          }
        })
      }
      .width('100%')
      .padding({ bottom: WindowManager.getSystemAvoidAreaBottomVp() })
      .backgroundColor($r('app.color.surface'))

      if (this.isLoadingDraft) {
        Column() {
          LoadingSpinner({ message: '' })
          Text('正在恢复草稿...')
            .fontSize(12)
            .fontColor($r('app.color.on_surface_secondary'))
            .margin({ top: 8 })
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .backgroundColor(this.getDraftLoadingOverlayBackground())
      }

      this.DiscardConfirmOverlay()
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.surface'))
  }
}
