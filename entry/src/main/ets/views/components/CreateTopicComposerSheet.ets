import { ApiClient, PostEnqueuedError } from '../../services/network/ApiClient';
import { Category, SiteResponse } from '../../models/Category';
import { Draft, DraftData } from '../../models/Draft';
import { ThemeManager } from '../../common/theme/ThemeManager';
import { WindowManager } from '../../common/utils/WindowManager';
import { LoadingSpinner } from './LoadingSpinner';
import { ToastService } from '../../common/utils/ToastService';
import { TagSelectionSheet } from './TagControls';
import { CategoryIcon } from './CategoryIcon';
import { MarkdownComposerToolbar } from './MarkdownComposerToolbar';
import { ComposerEmojiStickerPanel } from './ComposerEmojiStickerPanel';
import { MarkdownComposerUtils } from '../../common/utils/MarkdownComposerUtils';
import { ComposerPreviewResourceResolver } from '../../common/utils/ComposerPreviewResourceResolver';
import { ComposerUploadUrlCache } from '../../common/utils/ComposerUploadUrlCache';
import { PostRichContent } from './PostRichContent';
import { Emoji } from '../../models/Emoji';
import { ComposerImageUploadService } from '../../common/utils/ComposerImageUploadService';
import { FeatureSettingsService } from '../../services/storage/FeatureSettingsService';

@ComponentV2
export struct CreateTopicComposerSheet {
  @Param requestKey: string = '';
  @Param draftKey: string = '';
  @Param initialCategoryId: number = 0;
  @Param initialTags: string[] = [];
  @Param openedFromDrafts: boolean = false;
  @Event onDismiss: (submitted: boolean) => void = (_: boolean) => {
  };
  @Event onSubmitted: (topicId: number) => void = (_: number) => {
  };

  @Local private title: string = '';
  @Local private content: string = '';
  @Local private categories: Category[] = [];
  @Local private selectedCategoryId: number = 0;
  @Local private selectedTags: string[] = [];
  @Local private draftSelectedTags: string[] = [];
  @Local private minTitleLength: number = SiteResponse.DEFAULT_MIN_TOPIC_TITLE_LENGTH;
  @Local private minContentLength: number = SiteResponse.DEFAULT_MIN_FIRST_POST_LENGTH;
  @Local private isLoadingDraft: boolean = false;
  @Local private isLoadingCategories: boolean = false;
  @Local private isSubmitting: boolean = false;
  @Local private errorMessage: string = '';
  @Local private draftSequence: number = 0;
  @Local private isCategorySheetVisible: boolean = false;
  @Local private isTagSheetVisible: boolean = false;
  @Local private isPreview: boolean = false;
  @Local private isEmojiPanelVisible: boolean = false;
  @Local private isRestorePromptVisible: boolean = false;
  @Local private isDiscardConfirmVisible: boolean = false;
  @Local private pendingRestoreDraft: Draft | null = null;
  @Local private contentSelectionStart: number = 0;
  @Local private contentSelectionEnd: number = 0;
  @Local private isImageUploading: boolean = false;
  @Local private imageUploadProgressLabel: string = '';
  @Local private previewRenderVersion: number = 0;

  private draftSaveTimerId: number = -1;
  private submitted: boolean = false;
  private loadRequestId: number = 0;
  private readonly titleController: TextInputController = new TextInputController();
  private readonly contentController: TextAreaController = new TextAreaController();
  private readonly emojiPanelHeight: number = 320;

  aboutToAppear(): void {
    this.resetComposerState();
    this.hydratePreviewResources();
    this.loadContextAndDraft();
  }

  @Monitor('requestKey')
  private onRequestKeyChange(): void {
    this.resetComposerState();
    this.hydratePreviewResources();
    this.loadContextAndDraft();
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
    this.title = '';
    this.content = '';
    this.categories = [];
    this.selectedCategoryId = 0;
    this.selectedTags = [];
    this.draftSelectedTags = [];
    this.minTitleLength = SiteResponse.DEFAULT_MIN_TOPIC_TITLE_LENGTH;
    this.minContentLength = SiteResponse.DEFAULT_MIN_FIRST_POST_LENGTH;
    this.isLoadingDraft = false;
    this.isLoadingCategories = false;
    this.isSubmitting = false;
    this.errorMessage = '';
    this.draftSequence = 0;
    this.isCategorySheetVisible = false;
    this.isTagSheetVisible = false;
    this.isPreview = false;
    this.isEmojiPanelVisible = false;
    this.isRestorePromptVisible = false;
    this.isDiscardConfirmVisible = false;
    this.pendingRestoreDraft = null;
    this.contentSelectionStart = 0;
    this.contentSelectionEnd = 0;
    this.isImageUploading = false;
    this.imageUploadProgressLabel = '';
    this.previewRenderVersion = 0;
  }

  private hydratePreviewResources(): void {
    ComposerUploadUrlCache.hydrate().then(() => {
      this.previewRenderVersion = this.previewRenderVersion + 1;
    }).catch(() => {
    });
  }

  private getDraftKey(): string {
    if (this.draftKey.trim().length > 0) {
      return this.draftKey.trim();
    }
    return Draft.newTopicKey;
  }

  private getMinTitleLength(): number {
    return this.minTitleLength;
  }

  private getMinContentLength(): number {
    return this.minContentLength;
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
    if (this.submitted || this.isRestorePromptVisible) {
      return;
    }
    this.clearDraftSaveTimer();
    this.draftSaveTimerId = setTimeout(() => {
      this.persistDraft().catch((_: Object) => {
      });
    }, 700);
  }

  private normalizeTags(source: string[]): string[] {
    const next: string[] = [];
    for (let i: number = 0; i < source.length; i++) {
      const tag: string = source[i] !== undefined && source[i] !== null ? source[i].trim() : '';
      if (tag.length === 0 || next.indexOf(tag) >= 0) {
        continue;
      }
      next.push(tag);
    }
    return next;
  }

  private isCategorySelectable(category: Category): boolean {
    return category.canCreateTopic;
  }

  private applyInitialContext(): void {
    if (this.selectedTags.length === 0 && this.initialTags.length > 0) {
      const next: string[] = this.normalizeTags(this.initialTags);
      this.selectedTags = next;
      this.draftSelectedTags = [...next];
    }

    if (this.selectedCategoryId > 0) {
      return;
    }

    if (this.initialCategoryId > 0) {
      for (let i: number = 0; i < this.categories.length; i++) {
        if (this.categories[i].id === this.initialCategoryId) {
          this.selectedCategoryId = this.initialCategoryId;
          return;
        }
      }
    }

    if (this.categories.length > 0) {
      this.selectedCategoryId = this.categories[0].id;
    }
  }

  private getSelectedCategory(): Category | null {
    for (let i: number = 0; i < this.categories.length; i++) {
      if (this.categories[i].id === this.selectedCategoryId) {
        return this.categories[i];
      }
    }
    return null;
  }

  private hasSelectedCategory(): boolean {
    return this.getSelectedCategory() !== null;
  }

  private getSelectedCategoryName(): string {
    const selectedCategory: Category | null = this.getSelectedCategory();
    return selectedCategory !== null ? (selectedCategory as Category).name : '选择分类';
  }

  private getSelectedCategoryColor(): string {
    const selectedCategory: Category | null = this.getSelectedCategory();
    return selectedCategory !== null ? (selectedCategory as Category).colorValue : '#999999';
  }

  private buildAvailableComposerTags(): string[] {
    const next: string[] = [];
    const selected: string[] = this.normalizeTags(this.selectedTags);
    for (let i: number = 0; i < selected.length; i++) {
      next.push(selected[i]);
    }
    const initial: string[] = this.normalizeTags(this.initialTags);
    for (let i: number = 0; i < initial.length; i++) {
      if (next.indexOf(initial[i]) < 0) {
        next.push(initial[i]);
      }
    }
    return next;
  }

  private restoreDraft(draft: Draft): void {
    this.draftSequence = draft.sequence;
    this.title = draft.data.title !== null ? draft.data.title as string : '';
    this.content = draft.data.reply !== null ? draft.data.reply as string : '';
    this.syncContentSelection(this.content.length, this.content.length);
    const nextTags: string[] = draft.data.tags !== null ? this.normalizeTags(draft.data.tags as string[]) : [];
    this.selectedTags = nextTags;
    this.draftSelectedTags = [...nextTags];
    if (draft.data.categoryId !== null && (draft.data.categoryId as number) > 0) {
      this.selectedCategoryId = draft.data.categoryId as number;
    }
    this.errorMessage = '';
    this.preparePreviewResources();
  }

  private preparePreviewResources(): void {
    const snapshot: string = this.content;
    if (snapshot.trim().length === 0) {
      return;
    }
    ComposerPreviewResourceResolver.ensureMarkdownResources(snapshot).then((updated: boolean) => {
      if (!updated || snapshot !== this.content) {
        return;
      }
      this.previewRenderVersion = this.previewRenderVersion + 1;
    }).catch(() => {
    });
  }

  private async loadContextAndDraft(): Promise<void> {
    const requestId: number = this.loadRequestId + 1;
    this.loadRequestId = requestId;
    this.isLoadingCategories = true;
    this.isLoadingDraft = true;
    this.errorMessage = '';
    try {
      const api: ApiClient = ApiClient.getInstance();
      const siteResponse: SiteResponse = await api.getSiteInfo();
      if (requestId !== this.loadRequestId) {
        return;
      }
      this.minTitleLength = siteResponse.getTopicTitleMinLength();
      this.minContentLength = siteResponse.getTopicBodyMinLength();

      const writableCategories: Category[] = [];
      for (let i: number = 0; i < siteResponse.categories.length; i++) {
        const category: Category = siteResponse.categories[i];
        if (this.isCategorySelectable(category)) {
          writableCategories.push(category);
        }
      }
      this.categories = writableCategories;
      this.applyInitialContext();
      this.isLoadingCategories = false;

      const draft: Draft | null = await api.getDraft(this.getDraftKey());
      if (requestId !== this.loadRequestId || draft === null || !draft.hasContent) {
        return;
      }

      if (this.openedFromDrafts) {
        this.restoreDraft(draft);
        ToastService.show('已恢复草稿');
        return;
      }

      this.pendingRestoreDraft = draft;
      this.isRestorePromptVisible = true;
    } catch (err) {
      if (requestId === this.loadRequestId) {
        this.errorMessage = err !== undefined && err !== null
          ? err.toString().replace('Error: ', '')
          : '加载发帖上下文失败';
      }
    } finally {
      if (requestId === this.loadRequestId) {
        this.isLoadingCategories = false;
        this.isLoadingDraft = false;
      }
    }
  }

  private async persistDraft(): Promise<void> {
    if (this.submitted || this.isRestorePromptVisible) {
      return;
    }
    const title: string = this.title.trim();
    const content: string = this.content.trim();
    if (title.length === 0 && content.length === 0 && this.selectedTags.length === 0) {
      await ApiClient.getInstance().deleteDraft(this.getDraftKey(), this.draftSequence);
      this.draftSequence = 0;
      return;
    }

    const data: DraftData = new DraftData();
    data.title = this.title;
    data.reply = this.content;
    data.categoryId = this.selectedCategoryId > 0 ? this.selectedCategoryId : null;
    data.tags = this.selectedTags.length > 0 ? [...this.selectedTags] : null;
    data.action = 'createTopic';
    data.archetypeId = 'regular';
    this.draftSequence = await ApiClient.getInstance().saveDraft(this.getDraftKey(), data, this.draftSequence);
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
    return this.title.trim().length > 0 || this.content.trim().length > 0 || this.selectedTags.length > 0 ||
      this.draftSequence > 0 || this.pendingRestoreDraft !== null;
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

  private restorePendingDraft(): void {
    if (this.pendingRestoreDraft === null) {
      return;
    }
    this.restoreDraft(this.pendingRestoreDraft as Draft);
    this.pendingRestoreDraft = null;
    this.isRestorePromptVisible = false;
    ToastService.show('已恢复草稿');
  }

  private async discardPendingRestoreDraft(): Promise<void> {
    if (this.pendingRestoreDraft === null) {
      this.isRestorePromptVisible = false;
      return;
    }

    const draft: Draft = this.pendingRestoreDraft as Draft;
    try {
      await ApiClient.getInstance().deleteDraft(draft.draftKey, draft.sequence);
      this.draftSequence = 0;
    } catch (_) {
    } finally {
      this.pendingRestoreDraft = null;
      this.isRestorePromptVisible = false;
    }
  }

  private validateBeforeSubmit(): boolean {
    const normalizedTitle: string = this.title.trim();
    const normalizedContent: string = this.content.trim();
    if (normalizedTitle.length === 0) {
      this.errorMessage = '请输入标题';
      return false;
    }
    if (normalizedTitle.length < this.getMinTitleLength()) {
      this.errorMessage = `标题至少需要 ${this.getMinTitleLength()} 个字符`;
      return false;
    }
    if (normalizedContent.length === 0) {
      this.errorMessage = '请输入内容';
      return false;
    }
    if (normalizedContent.length < this.getMinContentLength()) {
      this.errorMessage = `正文至少需要 ${this.getMinContentLength()} 个字符`;
      return false;
    }
    if (this.selectedCategoryId <= 0) {
      this.errorMessage = '请选择分类';
      return false;
    }
    return true;
  }

  private async submit(): Promise<void> {
    if (!this.validateBeforeSubmit()) {
      this.isPreview = false;
      return;
    }

    this.isSubmitting = true;
    this.errorMessage = '';
    try {
      const submitContent: string = await FeatureSettingsService.getInstance().transformComposerContentBeforeSubmit(
        this.content
      );
      if (submitContent !== this.content) {
        this.content = submitContent;
        this.syncSelectionToTail();
      }
      const topicId: number = await ApiClient.getInstance().createTopic(
        this.title.trim(),
        submitContent,
        this.selectedCategoryId,
        this.selectedTags.length > 0 ? [...this.selectedTags] : null
      );
      this.submitted = true;
      await ApiClient.getInstance().deleteDraft(this.getDraftKey(), this.draftSequence);
      ToastService.show('话题已发布');
      this.onSubmitted(topicId);
      this.onDismiss(true);
    } catch (err) {
      if (err instanceof PostEnqueuedError) {
        this.submitted = true;
        try {
          await ApiClient.getInstance().deleteDraft(this.getDraftKey(), this.draftSequence);
        } catch (_) {
        }
        ToastService.show('你的话题已提交，正在等待审核');
        this.onDismiss(true);
      } else {
        this.errorMessage = err !== undefined && err !== null
          ? err.toString().replace('Error: ', '')
          : '发布话题失败';
      }
    } finally {
      this.isSubmitting = false;
    }
  }

  private toggleDraftTag(tagName: string): void {
    const currentIndex: number = this.draftSelectedTags.indexOf(tagName);
    if (currentIndex >= 0) {
      const next: string[] = [];
      for (let i: number = 0; i < this.draftSelectedTags.length; i++) {
        if (this.draftSelectedTags[i] !== tagName) {
          next.push(this.draftSelectedTags[i]);
        }
      }
      this.draftSelectedTags = next;
      return;
    }
    this.draftSelectedTags = [...this.draftSelectedTags, tagName];
  }

  private removeTag(tagName: string): void {
    const next: string[] = [];
    for (let i: number = 0; i < this.selectedTags.length; i++) {
      if (this.selectedTags[i] !== tagName) {
        next.push(this.selectedTags[i]);
      }
    }
    this.selectedTags = next;
    this.draftSelectedTags = [...next];
    this.errorMessage = '';
    this.scheduleDraftSave();
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

  private stopInputEditing(): void {
    try {
      this.titleController.stopEditing();
    } catch (_) {
    }
    try {
      this.contentController.stopEditing();
    } catch (_) {
    }
  }

  private closeEmojiPanel(): void {
    this.isEmojiPanelVisible = false;
  }

  private toggleEmojiPanel(): void {
    this.isPreview = false;
    const nextVisible: boolean = !this.isEmojiPanelVisible;
    if (nextVisible) {
      this.stopInputEditing();
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
    this.stopInputEditing();
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
    if (this.previewRenderVersion < 0) {
      return '';
    }
    return MarkdownComposerUtils.toPreviewHtml(this.content);
  }

  @Builder
  private CategorySelectorButton() {
    Row() {
      if (this.hasSelectedCategory()) {
        CategoryIcon({
          category: this.getSelectedCategory(),
          iconSize: 18,
          color: this.getSelectedCategoryColor(),
          preferImage: false
        })
          .margin({ right: 8 })
      } else {
        SymbolGlyph($r('sys.symbol.plus'))
          .fontSize(18)
          .fontColor([$r('app.color.on_surface_secondary')])
          .margin({ right: 8 })
      }

      Text(this.getSelectedCategoryName())
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.on_surface'))
        .layoutWeight(1)

      SymbolGlyph($r('sys.symbol.chevron_down'))
        .fontSize(14)
        .fontColor([$r('app.color.on_surface_secondary')])
        .margin({ left: 8 })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 12 })
    .backgroundColor($r('app.color.surface_variant'))
    .borderRadius(16)
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      this.isCategorySheetVisible = true;
    })
  }

  @Builder
  private AddTagButton() {
    Row() {
      SymbolGlyph($r('sys.symbol.plus'))
        .fontSize(18)
        .fontColor([$r('app.color.primary')])
        .margin({ right: 8 })

      Text(this.selectedTags.length > 0 ? '编辑标签' : '添加标签')
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.primary'))
        .layoutWeight(1)
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 12 })
    .backgroundColor($r('app.color.surface'))
    .border({ width: 1, color: $r('app.color.divider_light') })
    .borderRadius(16)
    .alignItems(VerticalAlign.Center)
    .margin({ top: 12 })
    .onClick(() => {
      this.draftSelectedTags = [...this.selectedTags];
      this.isTagSheetVisible = true;
    })
  }

  @Builder
  private SelectedTagArea() {
    if (this.selectedTags.length > 0) {
      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach(this.selectedTags, (tag: string) => {
          Row() {
            Text(tag)
              .fontSize(12)
              .fontColor($r('app.color.primary'))
            Text('×')
              .fontSize(12)
              .fontColor($r('app.color.primary'))
              .margin({ left: 6 })
          }
          .padding({ left: 12, right: 10, top: 7, bottom: 7 })
          .backgroundColor($r('app.color.badge_background_light'))
          .borderRadius(12)
          .margin({ right: 8, top: 10 })
          .onClick(() => {
            this.removeTag(tag);
          })
        }, (tag: string) => tag)
      }
      .width('100%')
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
        .padding({ left: 20, right: 20, top: 16, bottom: 24 })
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
    } else {
      TextArea({
        text: this.content,
        placeholder: '输入正文，支持 Markdown...',
        controller: this.contentController
      })
        .width('100%')
        .layoutWeight(1)
        .padding({ left: 20, right: 20, top: 16, bottom: 24 })
        .backgroundColor(Color.Transparent)
        .borderRadius(0)
        .fontSize(18)
        .lineHeight(28)
        .fontColor($r('app.color.on_surface'))
        .placeholderColor($r('app.color.on_surface_secondary'))
        .maxLength(30000)
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
  private CategorySheetBuilder() {
    Column() {
      Text('选择分类')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.on_surface'))
        .width('100%')
        .padding({ left: 20, right: 20, top: 14, bottom: 12 })

      Scroll() {
        Column() {
          ForEach(this.categories, (category: Category) => {
            Row() {
              CategoryIcon({
                category: category,
                iconSize: 20,
                color: category.colorValue,
                preferImage: false
              })
                .margin({ right: 12 })

              Text(category.name)
                .fontSize(15)
                .fontColor($r('app.color.on_surface'))
                .layoutWeight(1)

              if (this.selectedCategoryId === category.id) {
                SymbolGlyph($r('sys.symbol.checkmark'))
                  .fontSize(16)
                  .fontColor([$r('app.color.primary')])
              }
            }
            .width('100%')
            .padding({ left: 20, right: 20, top: 14, bottom: 14 })
            .border({ width: { bottom: 0.5 }, color: $r('app.color.divider_light') })
            .alignItems(VerticalAlign.Center)
            .onClick(() => {
              this.selectedCategoryId = category.id;
              this.errorMessage = '';
              this.scheduleDraftSave();
              this.isCategorySheetVisible = false;
            })
          }, (category: Category) => category.id.toString())
        }
      }
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.surface'))
  }

  @Builder
  private TagSheetBuilder() {
    TagSelectionSheet({
      title: '选择标签',
      doneText: '确定',
      availableTags: this.buildAvailableComposerTags(),
      selectedTags: this.draftSelectedTags,
      categoryId: this.selectedCategoryId > 0 ? this.selectedCategoryId : null,
      maxTags: 5,
      showDragHandle: false,
      onToggleTag: (tagName: string) => {
        this.toggleDraftTag(tagName);
      },
      onDone: () => {
        this.selectedTags = [...this.draftSelectedTags];
        this.errorMessage = '';
        this.isTagSheetVisible = false;
        this.scheduleDraftSave();
      },
      onClear: () => {
        this.draftSelectedTags = [];
      }
    })
  }

  @Builder
  private RestorePromptOverlay() {
    if (this.isRestorePromptVisible && this.pendingRestoreDraft !== null) {
      Stack({ alignContent: Alignment.Center }) {
        Column() {
        }
        .width('100%')
        .height('100%')
        .backgroundColor('#66000000')

        Column() {
          Text('恢复草稿？')
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.on_surface'))
            .width('100%')

          Text('检测到你上次未发布的话题，是否继续编辑？')
            .fontSize(14)
            .fontColor($r('app.color.on_surface_secondary'))
            .width('100%')
            .margin({ top: 10 })

          Row() {
            Button('丢弃')
              .type(ButtonType.Capsule)
              .layoutWeight(1)
              .height(44)
              .backgroundColor($r('app.color.surface_variant'))
              .fontColor($r('app.color.on_surface_secondary'))
              .onClick(() => {
                this.discardPendingRestoreDraft().catch((_: Object) => {
                });
              })

            Blank().width(12)

            Button('恢复')
              .type(ButtonType.Capsule)
              .layoutWeight(1)
              .height(44)
              .backgroundColor($r('app.color.primary'))
              .fontColor(Color.White)
              .onClick(() => {
                this.restorePendingDraft();
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
          Text('舍弃草稿？')
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.on_surface'))
            .width('100%')

          Text('当前已输入的标题、正文和草稿内容都会被删除。')
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

  private getLoadingOverlayBackground(): string {
    return WindowManager.isDarkMode()
      ? ThemeManager.hexWithAlpha('#000000', 0.42)
      : '#66FFFFFF';
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      Column() {
        Row() {
          Row() {
            SymbolGlyph($r('sys.symbol.chevron_left'))
              .fontSize(18)
              .fontColor([$r('app.color.on_surface')])
          }
          .width(44)
          .height(44)
          .justifyContent(FlexAlign.Center)
          .alignItems(VerticalAlign.Center)
          .onClick(() => {
            this.closeSheet().catch((_: Object) => {
            });
          })

          Text('创建话题')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.on_surface'))
            .layoutWeight(1)
            .margin({ left: 8 })

          Text('舍弃')
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.on_surface_secondary'))
            .padding({ left: 12, right: 12, top: 10, bottom: 10 })
            .onClick(() => {
              this.requestDiscardDraft();
            })

          Button(this.isSubmitting ? '发布中...' : '发布')
            .type(ButtonType.Capsule)
            .height(42)
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
        .padding({ left: 8, right: 16, top: 8, bottom: 8 })
        .alignItems(VerticalAlign.Center)

        if (this.errorMessage.length > 0) {
          Text(this.errorMessage)
            .fontSize(12)
            .fontColor($r('app.color.warning'))
            .width('100%')
            .padding({ left: 20, right: 20, top: 4, bottom: 8 })
        }

        TextInput({
          text: this.title,
          placeholder: '输入一个清晰的标题...',
          controller: this.titleController
        })
          .width('100%')
          .margin({ left: 20, right: 20, top: 14 })
          .padding({ top: 8, bottom: 8 })
          .backgroundColor(Color.Transparent)
          .fontSize(30)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.on_surface'))
          .placeholderColor($r('app.color.on_surface_secondary'))
          .maxLength(200)
          .onFocus(() => {
            this.closeEmojiPanel();
          })
          .onChange((value: string) => {
            this.title = value;
            this.errorMessage = '';
            this.scheduleDraftSave();
          })

        Column() {
          this.CategorySelectorButton()
          this.AddTagButton()
          this.SelectedTagArea()
        }
        .width('100%')
        .padding({ left: 20, right: 20, top: 12 })
        .alignItems(HorizontalAlign.Start)

        Divider()
          .strokeWidth(1)
          .color($r('app.color.divider_light'))
          .margin({ left: 20, right: 20, top: 18 })

        Text(`${this.content.length} 字符`)
          .fontSize(12)
          .fontColor($r('app.color.on_surface_secondary'))
          .width('100%')
          .textAlign(TextAlign.End)
          .padding({ left: 20, right: 20, top: 10 })

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
              this.stopInputEditing();
              this.closeEmojiPanel();
              this.preparePreviewResources();
            }
          }
        })
      }
      .width('100%')
      .padding({ bottom: WindowManager.getSystemAvoidAreaBottomVp() })
      .backgroundColor($r('app.color.surface'))

      Column() {
      }
      .width(0)
      .height(0)
      .bindSheet($$this.isCategorySheetVisible, this.CategorySheetBuilder, {
        detents: [SheetSize.MEDIUM, SheetSize.LARGE],
        showClose: false,
        enableFloatingDragBar: true,
        backgroundColor: $r('app.color.surface')
      })

      Column() {
      }
      .width(0)
      .height(0)
      .bindSheet($$this.isTagSheetVisible, this.TagSheetBuilder, {
        detents: [SheetSize.MEDIUM, SheetSize.LARGE],
        showClose: false,
        enableFloatingDragBar: true,
        backgroundColor: $r('app.color.surface')
      })

      if (this.isLoadingDraft || this.isLoadingCategories) {
        Column() {
          LoadingSpinner({ message: '' })
          Text('正在加载草稿...')
            .fontSize(12)
            .fontColor($r('app.color.on_surface_secondary'))
            .margin({ top: 8 })
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .backgroundColor(this.getLoadingOverlayBackground())
      }

      this.RestorePromptOverlay()
      this.DiscardConfirmOverlay()
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.surface'))
  }
}
