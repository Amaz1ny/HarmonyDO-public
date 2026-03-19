import { ApiClient, PostEnqueuedError } from '../../services/network/ApiClient';
import { Draft, DraftData } from '../../models/Draft';
import { AppSettingsService } from '../../services/storage/AppSettingsService';
import { WindowManager } from '../../common/utils/WindowManager';
import { LoadingSpinner } from './LoadingSpinner';
import { SmartAvatar } from './SmartAvatar';
import { ToastService } from '../../common/utils/ToastService';

@ComponentV2
export struct PrivateMessageComposerSheet {
  @Param targetUsername: string = '';
  @Param targetAvatarUrl: string = '';
  @Param requestKey: string = '';
  @Event onDismiss: (submitted: boolean) => void = (_: boolean) => {
  };

  @Local private title: string = '';
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
    this.title = '';
    this.content = '';
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
    return Draft.newPrivateMessageKey;
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

  private isDraftForCurrentRecipient(draft: Draft): boolean {
    const recipients: string[] | null = draft.data.recipients;
    if (recipients === null || recipients.length === 0) {
      return true;
    }
    const target: string = this.targetUsername.trim().toLowerCase();
    for (let i = 0; i < recipients.length; i++) {
      const recipient: string = recipients[i].trim().toLowerCase();
      if (recipient === target) {
        return true;
      }
    }
    return false;
  }

  private async loadDraft(): Promise<void> {
    const target: string = this.targetUsername.trim();
    if (target.length === 0) return;
    const requestId: number = this.loadRequestId + 1;
    this.loadRequestId = requestId;
    this.isLoadingDraft = true;
    try {
      const apiClient: ApiClient = ApiClient.getInstance();
      const draft: Draft | null = await apiClient.getDraft(this.getDraftKey());
      if (requestId !== this.loadRequestId || draft === null || !this.isDraftForCurrentRecipient(draft)) {
        return;
      }
      this.draftSequence = draft.sequence;
      this.title = draft.data.title !== null ? draft.data.title as string : '';
      this.content = draft.data.reply !== null ? draft.data.reply as string : '';
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
    const target: string = this.targetUsername.trim();
    if (target.length === 0 || this.submitted) return;
    const apiClient: ApiClient = ApiClient.getInstance();
    const spacedTitle: string = AppSettingsService.getInstance().applyEditorSpacing(this.title);
    const spacedContent: string = AppSettingsService.getInstance().applyEditorSpacing(this.content);
    if (spacedTitle !== this.title) {
      this.title = spacedTitle;
    }
    if (spacedContent !== this.content) {
      this.content = spacedContent;
    }
    const title: string = spacedTitle.trim();
    const content: string = spacedContent.trim();
    if (title.length === 0 && content.length === 0) {
      await apiClient.deleteDraft(this.getDraftKey(), this.draftSequence);
      this.draftSequence = 0;
      return;
    }

    const data: DraftData = new DraftData();
    data.title = spacedTitle;
    data.reply = spacedContent;
    data.action = 'privateMessage';
    data.archetypeId = 'private_message';
    data.recipients = [target];
    this.draftSequence = await apiClient.saveDraft(this.getDraftKey(), data, this.draftSequence);
  }

  private async flushDraft(): Promise<void> {
    try {
      await this.persistDraft();
    } catch (_) {
    }
  }

  private async closeSheet(submitted: boolean = false): Promise<void> {
    if (!submitted) {
      await this.flushDraft();
    }
    this.onDismiss(submitted);
  }

  private async submit(): Promise<void> {
    const target: string = this.targetUsername.trim();
    const spacedTitle: string = AppSettingsService.getInstance().applyEditorSpacing(this.title);
    const spacedContent: string = AppSettingsService.getInstance().applyEditorSpacing(this.content);
    if (spacedTitle !== this.title) {
      this.title = spacedTitle;
    }
    if (spacedContent !== this.content) {
      this.content = spacedContent;
    }
    const title: string = spacedTitle.trim();
    const content: string = spacedContent.trim();
    if (target.length === 0) {
      this.errorMessage = '无效的用户名';
      return;
    }
    if (title.length === 0) {
      this.errorMessage = '请输入标题';
      return;
    }
    if (content.length === 0) {
      this.errorMessage = '请输入内容';
      return;
    }

    this.isSubmitting = true;
    this.errorMessage = '';
    try {
      const apiClient: ApiClient = ApiClient.getInstance();
      await apiClient.createPrivateMessage([target], title, content);
      this.submitted = true;
      await apiClient.deleteDraft(this.getDraftKey(), this.draftSequence);
      ToastService.show('私信已发送');
      this.onDismiss(true);
    } catch (err) {
      if (err instanceof PostEnqueuedError) {
        this.submitted = true;
        try {
          const apiClient: ApiClient = ApiClient.getInstance();
          await apiClient.deleteDraft(this.getDraftKey(), this.draftSequence);
        } catch (_) {
        }
        ToastService.show('你的私信已提交，正在等待审核');
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
        Text('发送私信')
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
            this.closeSheet(false).catch((_: Object) => {
            });
          })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .padding({ left: 16, right: 16 })

      Row() {
        SmartAvatar({
          avatarUrl: this.targetAvatarUrl,
          avatarSize: 32,
          avatarRadius: 16,
          fallbackText: this.targetUsername,
          bgColor: '#E8EAF0'
        })

        Column() {
          Text(`发送给 @${this.targetUsername}`)
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.on_surface'))

          Text('支持 Markdown，发送后会进入 Linux.do 私信')
            .fontSize(12)
            .fontColor($r('app.color.on_surface_secondary'))
            .margin({ top: 4 })
        }
        .margin({ left: 12 })
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .padding({ left: 16, right: 16, top: 14, bottom: 4 })

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

      TextInput({ text: this.title, placeholder: '输入私信标题' })
        .width('100%')
        .height(48)
        .padding({ left: 14, right: 14 })
        .margin({ left: 16, right: 16, top: 12 })
        .backgroundColor($r('app.color.surface_variant'))
        .borderRadius(14)
        .fontSize(15)
        .fontColor($r('app.color.on_surface'))
        .placeholderColor($r('app.color.on_surface_tertiary'))
        .onChange((value: string) => {
          this.title = value;
          this.errorMessage = '';
          this.scheduleDraftSave();
        })

      TextArea({ text: this.content, placeholder: '写下你的私信内容...' })
        .width('100%')
        .height(240)
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

      Row() {
        Button('稍后继续')
          .type(ButtonType.Capsule)
          .layoutWeight(1)
          .height(44)
          .backgroundColor($r('app.color.surface_variant'))
          .fontColor($r('app.color.on_surface_secondary'))
          .onClick(() => {
            this.closeSheet(false).catch((_: Object) => {
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
