import { ApiClient, PostEnqueuedError } from '../../services/network/ApiClient';
import { Category, SiteResponse } from '../../models/Category';
import { Draft, DraftData } from '../../models/Draft';
import { WindowManager } from '../../common/utils/WindowManager';
import { LoadingSpinner } from './LoadingSpinner';
import { ToastService } from '../../common/utils/ToastService';

@ComponentV2
export struct CreateTopicComposerSheet {
  @Event onDismiss: (submitted: boolean) => void = (_: boolean) => {
  };
  @Event onSubmitted: (topicId: number) => void = (_: number) => {
  };

  @Local private title: string = '';
  @Local private content: string = '';
  @Local private tagsText: string = '';
  @Local private categories: Category[] = [];
  @Local private selectedCategoryId: number = 0;
  @Local private isLoadingDraft: boolean = false;
  @Local private isLoadingCategories: boolean = false;
  @Local private isSubmitting: boolean = false;
  @Local private errorMessage: string = '';
  @Local private draftSequence: number = 0;

  private draftSaveTimerId: number = -1;
  private submitted: boolean = false;
  private loadRequestId: number = 0;

  aboutToAppear(): void {
    this.submitted = false;
    this.title = '';
    this.content = '';
    this.tagsText = '';
    this.categories = [];
    this.selectedCategoryId = 0;
    this.isLoadingDraft = false;
    this.isLoadingCategories = false;
    this.isSubmitting = false;
    this.errorMessage = '';
    this.draftSequence = 0;
    this.loadContextAndDraft();
  }

  aboutToDisappear(): void {
    this.clearDraftSaveTimer();
    if (!this.submitted) {
      this.flushDraft().catch((_: Object) => {
      });
    }
  }

  private getDraftKey(): string {
    return Draft.newTopicKey;
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

  private isCategorySelectable(category: Category): boolean {
    if (category.canCreateTopic) {
      return true;
    }
    return !category.readRestricted;
  }

  private parseTagsText(text: string): string[] {
    const normalized: string = text.replace(/，/g, ',').trim();
    if (normalized.length === 0) {
      return [];
    }
    const chunks: string[] = normalized.split(',');
    const seen: Map<string, boolean> = new Map();
    const tags: string[] = [];
    for (let i = 0; i < chunks.length; i++) {
      const tag: string = chunks[i].trim();
      if (tag.length === 0 || seen.has(tag)) {
        continue;
      }
      seen.set(tag, true);
      tags.push(tag);
    }
    return tags;
  }

  private joinTags(tags: string[] | null): string {
    if (tags === null || tags.length === 0) {
      return '';
    }
    return tags.join(', ');
  }

  private async loadContextAndDraft(): Promise<void> {
    const requestId: number = ++this.loadRequestId;
    this.isLoadingCategories = true;
    this.isLoadingDraft = true;
    this.errorMessage = '';
    try {
      const api: ApiClient = ApiClient.getInstance();
      const siteResponse: SiteResponse = await api.getSiteInfo();
      if (requestId !== this.loadRequestId) {
        return;
      }

      const writableCategories: Category[] = [];
      for (let i = 0; i < siteResponse.categories.length; i++) {
        const category: Category = siteResponse.categories[i];
        if (this.isCategorySelectable(category)) {
          writableCategories.push(category);
        }
      }
      this.categories = writableCategories;
      if (this.selectedCategoryId <= 0 && this.categories.length > 0) {
        this.selectedCategoryId = this.categories[0].id;
      }
      this.isLoadingCategories = false;

      const draft: Draft | null = await api.getDraft(this.getDraftKey());
      if (requestId !== this.loadRequestId || draft === null) {
        return;
      }
      this.draftSequence = draft.sequence;
      this.title = draft.data.title !== null ? draft.data.title as string : '';
      this.content = draft.data.reply !== null ? draft.data.reply as string : '';
      this.tagsText = this.joinTags(draft.data.tags);
      if (draft.data.categoryId !== null && (draft.data.categoryId as number) > 0) {
        this.selectedCategoryId = draft.data.categoryId as number;
      }
    } catch (err) {
      if (requestId === this.loadRequestId) {
        this.errorMessage = err !== undefined && err !== null
          ? err.toString().replace('Error: ', '')
          : '加载话题草稿失败';
      }
    } finally {
      if (requestId === this.loadRequestId) {
        this.isLoadingCategories = false;
        this.isLoadingDraft = false;
      }
    }
  }

  private async persistDraft(): Promise<void> {
    if (this.submitted) {
      return;
    }
    const title: string = this.title.trim();
    const content: string = this.content.trim();
    const tags: string[] = this.parseTagsText(this.tagsText);
    if (title.length === 0 && content.length === 0 && tags.length === 0) {
      await ApiClient.getInstance().deleteDraft(this.getDraftKey(), this.draftSequence);
      this.draftSequence = 0;
      return;
    }

    const data: DraftData = new DraftData();
    data.title = this.title;
    data.reply = this.content;
    data.categoryId = this.selectedCategoryId > 0 ? this.selectedCategoryId : null;
    data.tags = tags.length > 0 ? tags : null;
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
    await this.flushDraft();
    this.onDismiss(false);
  }

  private async submit(): Promise<void> {
    const normalizedTitle: string = this.title.trim();
    const normalizedContent: string = this.content.trim();
    if (normalizedTitle.length < 5) {
      this.errorMessage = '标题至少需要 5 个字符';
      return;
    }
    if (normalizedContent.length < 10) {
      this.errorMessage = '内容至少需要 10 个字符';
      return;
    }
    if (this.selectedCategoryId <= 0) {
      this.errorMessage = '请选择分类';
      return;
    }

    this.isSubmitting = true;
    this.errorMessage = '';
    try {
      const topicId: number = await ApiClient.getInstance().createTopic(
        normalizedTitle,
        this.content,
        this.selectedCategoryId,
        this.parseTagsText(this.tagsText)
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

  build() {
    Column() {
      Column() {
      }
      .width(36)
      .height(4)
      .borderRadius(2)
      .backgroundColor($r('app.color.divider_light'))
      .margin({ top: 12, bottom: 12 })

      Row() {
        Text('继续撰写话题')
          .fontSize(17)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.on_surface'))
          .layoutWeight(1)

        Button('关闭')
          .type(ButtonType.Capsule)
          .fontSize(13)
          .height(34)
          .backgroundColor($r('app.color.surface_variant'))
          .fontColor($r('app.color.on_surface_secondary'))
          .onClick(() => {
            this.closeSheet().catch((_: Object) => {
            });
          })
      }
      .width('100%')
      .padding({ left: 16, right: 16 })
      .alignItems(VerticalAlign.Center)

      if (this.isLoadingDraft || this.isLoadingCategories) {
        Row() {
          LoadingSpinner({ message: '' })
          Text('正在恢复话题草稿...')
            .fontSize(12)
            .fontColor($r('app.color.on_surface_secondary'))
            .margin({ left: 8 })
        }
        .width('100%')
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Center)
        .padding({ top: 12 })
      }

      if (this.errorMessage.length > 0) {
        Text(this.errorMessage)
          .fontSize(12)
          .fontColor($r('app.color.warning'))
          .width('100%')
          .padding({ left: 16, right: 16, top: 10 })
      }

      TextInput({ text: this.title, placeholder: '输入话题标题' })
        .width('100%')
        .height(48)
        .padding({ left: 14, right: 14 })
        .margin({ left: 16, right: 16, top: 14 })
        .backgroundColor($r('app.color.surface_variant'))
        .borderRadius(14)
        .fontSize(15)
        .fontColor($r('app.color.on_surface'))
        .placeholderColor($r('app.color.on_surface_tertiary'))
        .maxLength(200)
        .onChange((value: string) => {
          this.title = value;
          this.errorMessage = '';
          this.scheduleDraftSave();
        })

      Text('选择分类')
        .fontSize(13)
        .fontColor($r('app.color.on_surface_secondary'))
        .width('100%')
        .padding({ left: 16, right: 16, top: 16 })

      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach(this.categories, (category: Category) => {
          Text(category.name)
            .fontSize(12)
            .fontWeight(this.selectedCategoryId === category.id ? FontWeight.Medium : FontWeight.Normal)
            .fontColor(this.selectedCategoryId === category.id ? Color.White : $r('app.color.on_surface_secondary'))
            .padding({ left: 12, right: 12, top: 7, bottom: 7 })
            .backgroundColor(this.selectedCategoryId === category.id ? $r('app.color.primary') : $r('app.color.surface_variant'))
            .borderRadius(12)
            .margin({ right: 8, bottom: 8 })
            .onClick(() => {
              this.selectedCategoryId = category.id;
              this.errorMessage = '';
              this.scheduleDraftSave();
            })
        }, (category: Category) => category.id.toString())
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 10 })

      TextInput({ text: this.tagsText, placeholder: '标签，多个标签用逗号分隔（可选）' })
        .width('100%')
        .height(48)
        .padding({ left: 14, right: 14 })
        .margin({ left: 16, right: 16, top: 8 })
        .backgroundColor($r('app.color.surface_variant'))
        .borderRadius(14)
        .fontSize(14)
        .fontColor($r('app.color.on_surface'))
        .placeholderColor($r('app.color.on_surface_tertiary'))
        .onChange((value: string) => {
          this.tagsText = value;
          this.errorMessage = '';
          this.scheduleDraftSave();
        })

      TextArea({ text: this.content, placeholder: '写下你的话题正文...' })
        .width('100%')
        .height(280)
        .padding(12)
        .margin({ left: 16, right: 16, top: 12 })
        .backgroundColor($r('app.color.surface_variant'))
        .borderRadius(16)
        .fontSize(15)
        .fontColor($r('app.color.on_surface'))
        .placeholderColor($r('app.color.on_surface_tertiary'))
        .maxLength(30000)
        .copyOption(CopyOptions.LocalDevice)
        .onChange((value: string) => {
          this.content = value;
          this.errorMessage = '';
          this.scheduleDraftSave();
        })

      Row() {
        Button('稍后继续')
          .type(ButtonType.Capsule)
          .layoutWeight(1)
          .height(44)
          .backgroundColor($r('app.color.surface_variant'))
          .fontColor($r('app.color.on_surface_secondary'))
          .onClick(() => {
            this.closeSheet().catch((_: Object) => {
            });
          })

        Blank().width(12)

        Button(this.isSubmitting ? '发布中...' : '发布')
          .type(ButtonType.Capsule)
          .layoutWeight(1)
          .height(44)
          .enabled(!this.isSubmitting)
          .backgroundColor($r('app.color.primary'))
          .fontColor(Color.White)
          .onClick(() => {
            this.submit().catch((_: Object) => {
            });
          })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 16 })

      Blank().height(20 + WindowManager.getSystemAvoidAreaBottomVp())
    }
    .width('100%')
    .backgroundColor($r('app.color.surface'))
  }
}
