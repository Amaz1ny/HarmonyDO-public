import { ApiClient, PostEnqueuedError } from '../../services/network/ApiClient';
import { Draft, DraftData } from '../../models/Draft';
import { Post } from '../../models/Post';
import { WindowManager } from '../../common/utils/WindowManager';
import { LoadingSpinner } from './LoadingSpinner';
import { SmartAvatar } from './SmartAvatar';
import { ToastService } from '../../common/utils/ToastService';
import { UrlUtils } from '../../common/utils/UrlUtils';

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

  private draftSaveTimerId: number = -1;
  private submitted: boolean = false;
  private loadRequestId: number = 0;

  aboutToAppear(): void {
    this.submitted = false;
    this.content = this.initialContent;
    this.errorMessage = '';
    this.draftSequence = 0;
    this.loadDraft();
  }

  aboutToDisappear(): void {
    this.clearDraftSaveTimer();
    if (!this.submitted) {
      this.flushDraft().catch((_: Object) => {
      });
    }
  }

  private getDraftKey(): string {
    return Draft.replyKey(this.topicId, this.replyToPostNumber);
  }

  private clearDraftSaveTimer(): void {
    if (this.draftSaveTimerId >= 0) {
      clearTimeout(this.draftSaveTimerId);
      this.draftSaveTimerId = -1;
    }
  }

  private scheduleDraftSave(): void {
    if (this.submitted) return;
    this.clearDraftSaveTimer();
    this.draftSaveTimerId = setTimeout(() => {
      this.persistDraft().catch((_: Object) => {
      });
    }, 700);
  }

  private async loadDraft(): Promise<void> {
    if (this.topicId <= 0) return;
    const requestId: number = this.loadRequestId + 1;
    this.loadRequestId = requestId;
    this.isLoadingDraft = true;
    try {
      const apiClient: ApiClient = ApiClient.getInstance();
      const draft: Draft | null = await apiClient.getDraft(this.getDraftKey());
      if (requestId !== this.loadRequestId) return;
      if (draft !== null) {
        this.draftSequence = draft.sequence;
        const draftReply: string = draft.data.reply !== null ? (draft.data.reply as string) : '';
        if (draftReply.trim().length > 0) {
          if (this.initialContent.trim().length > 0) {
            this.content = `${this.initialContent}${draftReply}`;
          } else {
            this.content = draftReply;
          }
        }
      }
    } catch (err) {
      this.errorMessage = err !== undefined && err !== null ? err.toString() : '草稿加载失败';
    } finally {
      if (requestId === this.loadRequestId) {
        this.isLoadingDraft = false;
      }
    }
  }

  private async persistDraft(): Promise<void> {
    if (this.topicId <= 0 || this.submitted) return;
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
    await this.flushDraft();
    this.onDismiss(false);
  }

  private async submit(): Promise<void> {
    const trimmed: string = this.content.trim();
    if (trimmed.length === 0) {
      this.errorMessage = '请输入内容';
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
          const apiClient: ApiClient = ApiClient.getInstance();
          await apiClient.deleteDraft(this.getDraftKey(), this.draftSequence);
        } catch (_) {
        }
        ToastService.show('你的帖子已提交，正在等待审核');
        this.onDismiss(true);
      } else {
        this.errorMessage = err !== undefined && err !== null ? err.toString().replace('Error: ', '') : '发送失败';
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

  private getReplyToAvatarUrl(): string {
    if (this.replyToAvatarTemplate.trim().length === 0) {
      return '';
    }
    return UrlUtils.getAvatarUrl(this.replyToAvatarTemplate, 80);
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
        Text(this.getHeaderTitle())
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
      .alignItems(VerticalAlign.Center)
      .padding({ left: 16, right: 16 })

      if (this.replyToPostNumber > 0) {
        Row() {
          SmartAvatar({
            avatarUrl: this.getReplyToAvatarUrl(),
            avatarSize: 28,
            fallbackText: this.replyToUsername
          })

          Text(this.replyToUsername.length > 0 ? `回复给 @${this.replyToUsername}` : `回复给 #${this.replyToPostNumber}`)
            .fontSize(13)
            .fontColor($r('app.color.on_surface_secondary'))
            .margin({ left: 10 })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
        .padding({ left: 16, right: 16, top: 10, bottom: 4 })
      }

      if (this.isLoadingDraft) {
        Row() {
          LoadingSpinner({ message: '' })
          Text('正在恢复草稿...')
            .fontSize(12)
            .fontColor($r('app.color.on_surface_secondary'))
            .margin({ left: 8 })
        }
        .width('100%')
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Center)
        .padding({ top: 10, bottom: 6 })
      }

      if (this.errorMessage.length > 0) {
        Text(this.errorMessage)
          .fontSize(12)
          .fontColor($r('app.color.warning'))
          .width('100%')
          .padding({ left: 16, right: 16, top: 8 })
      }

      TextArea({ text: this.content, placeholder: '写下你的回复...' })
        .width('100%')
        .height(260)
        .padding(12)
        .margin({ left: 16, right: 16, top: 12 })
        .backgroundColor($r('app.color.surface_variant'))
        .borderRadius(16)
        .fontSize(15)
        .fontColor($r('app.color.on_surface'))
        .placeholderColor($r('app.color.on_surface_tertiary'))
        .maxLength(20000)
        .copyOption(CopyOptions.LocalDevice)
        .onChange((value: string) => {
          this.content = value;
          this.errorMessage = '';
          this.scheduleDraftSave();
        })

      Text(`草稿 key: ${this.getDraftKey()}`)
        .fontSize(11)
        .fontColor($r('app.color.on_surface_tertiary'))
        .width('100%')
        .padding({ left: 16, right: 16, top: 10 })

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

        Button(this.isSubmitting ? '发送中...' : '发送')
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
