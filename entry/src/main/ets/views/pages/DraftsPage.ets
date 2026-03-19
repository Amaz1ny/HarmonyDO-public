import { HdsNavDestination } from '@kit.UIDesignKit';
import { Draft } from '../../models/Draft';
import { TimeUtils } from '../../common/utils/TimeUtils';
import { RouterManager } from '../../common/utils/RouterManager';
import { WindowManager } from '../../common/utils/WindowManager';
import { ToastService } from '../../common/utils/ToastService';
import { ApiClient } from '../../services/network/ApiClient';
import { LoadingSpinner } from '../components/LoadingSpinner';
import { ErrorView } from '../components/ErrorView';
import { SmartAvatar } from '../components/SmartAvatar';
import { ReplyComposerSheet } from '../components/ReplyComposerSheet';
import { PrivateMessageComposerSheet } from '../components/PrivateMessageComposerSheet';
import { CreateTopicComposerSheet } from '../components/CreateTopicComposerSheet';

const TOP_BAR_HEIGHT: number = 56;

@ComponentV2
export struct DraftsPage {
  @Local drafts: Draft[] = [];
  @Local isLoading: boolean = true;
  @Local isRefreshing: boolean = false;
  @Local isLoadingMore: boolean = false;
  @Local hasMore: boolean = false;
  @Local errorMessage: string = '';
  @Local loadMoreFailed: boolean = false;
  @Local deletingDraftKey: string = '';

  @Local isReplySheetVisible: boolean = false;
  @Local activeReplyDraft: Draft | null = null;
  @Local isPrivateMessageSheetVisible: boolean = false;
  @Local activePrivateMessageDraft: Draft | null = null;
  @Local isTopicSheetVisible: boolean = false;
  @Local activeTopicDraft: Draft | null = null;

  private createdTopicId: number = 0;

  aboutToAppear(): void {
    if (this.drafts.length === 0) {
      this.loadDrafts(true, true).catch(() => {
      });
    }
  }

  private normalizeErrorMessage(err: Object): string {
    if (err === undefined || err === null) {
      return '加载草稿失败';
    }
    const text: string = err.toString().replace('Error: ', '').trim();
    return text.length > 0 ? text : '加载草稿失败';
  }

  private async loadDrafts(reset: boolean, showLoading: boolean = false): Promise<void> {
    if (this.isLoadingMore || this.deletingDraftKey.length > 0) {
      return;
    }
    if (reset) {
      if (showLoading) {
        this.isLoading = true;
      } else {
        this.isRefreshing = true;
      }
      this.errorMessage = '';
      this.loadMoreFailed = false;
    } else {
      if (!this.hasMore || this.isLoading) {
        return;
      }
      this.isLoadingMore = true;
      this.loadMoreFailed = false;
    }

    try {
      const offset: number = reset ? 0 : this.drafts.length;
      const response = await ApiClient.getInstance().getDrafts(offset, 20);
      if (reset) {
        this.drafts = response.drafts;
      } else {
        const merged: Draft[] = [];
        for (let i = 0; i < this.drafts.length; i++) {
          merged.push(this.drafts[i]);
        }
        for (let i = 0; i < response.drafts.length; i++) {
          const item: Draft = response.drafts[i];
          let exists: boolean = false;
          for (let j = 0; j < merged.length; j++) {
            if (merged[j].draftKey === item.draftKey) {
              exists = true;
              break;
            }
          }
          if (!exists) {
            merged.push(item);
          }
        }
        this.drafts = merged;
      }
      this.hasMore = response.hasMore;
    } catch (err) {
      if (reset) {
        this.errorMessage = this.normalizeErrorMessage(err);
      } else {
        this.loadMoreFailed = true;
      }
    } finally {
      this.isLoading = false;
      this.isRefreshing = false;
      this.isLoadingMore = false;
    }
  }

  private getDraftTypeLabel(draft: Draft): string {
    if (draft.draftKey === Draft.newTopicKey) {
      return '新话题';
    }
    if (draft.draftKey === Draft.newPrivateMessageKey) {
      return '私信';
    }
    const replyToPostNumber: number | null = draft.replyToPostNumberFromKey;
    if (replyToPostNumber !== null && (replyToPostNumber as number) > 0) {
      return `回复 #${replyToPostNumber as number}`;
    }
    if (draft.draftKey.startsWith('topic_')) {
      return '回复';
    }
    return '草稿';
  }

  private getDraftPreviewText(draft: Draft): string {
    return draft.data.reply !== null ? (draft.data.reply as string).trim() : '';
  }

  private getPrivateMessageTarget(draft: Draft): string {
    if (draft.data.recipients === null || (draft.data.recipients as string[]).length === 0) {
      return '';
    }
    return (draft.data.recipients as string[])[0].trim();
  }

  private removeDraftLocally(draftKey: string): void {
    const next: Draft[] = [];
    for (let i = 0; i < this.drafts.length; i++) {
      if (this.drafts[i].draftKey !== draftKey) {
        next.push(this.drafts[i]);
      }
    }
    this.drafts = next;
  }

  private async openDraft(draft: Draft): Promise<void> {
    if (draft.draftKey === Draft.newTopicKey) {
      this.activeTopicDraft = draft;
      this.isTopicSheetVisible = true;
      return;
    }
    if (draft.draftKey === Draft.newPrivateMessageKey) {
      const targetUsername: string = this.getPrivateMessageTarget(draft);
      if (targetUsername.length === 0) {
        ToastService.show('私信草稿数据不完整');
        return;
      }
      this.activePrivateMessageDraft = draft;
      this.isPrivateMessageSheetVisible = true;
      return;
    }
    if (draft.topicId !== null && (draft.topicId as number) > 0) {
      this.activeReplyDraft = draft;
      this.isReplySheetVisible = true;
      return;
    }
    ToastService.show('该草稿暂未支持打开');
  }

  private async deleteDraft(draft: Draft): Promise<void> {
    if (this.deletingDraftKey.length > 0) {
      return;
    }
    this.deletingDraftKey = draft.draftKey;
    try {
      await ApiClient.getInstance().deleteDraft(draft.draftKey, draft.sequence);
      this.removeDraftLocally(draft.draftKey);
      ToastService.show('草稿已删除');
    } catch (err) {
      ToastService.show(this.normalizeErrorMessage(err));
    } finally {
      this.deletingDraftKey = '';
    }
  }

  private handleReplySheetDismiss(submitted: boolean): void {
    const draftKey: string = this.activeReplyDraft !== null ? (this.activeReplyDraft as Draft).draftKey : '';
    this.isReplySheetVisible = false;
    this.activeReplyDraft = null;
    if (submitted && draftKey.length > 0) {
      this.removeDraftLocally(draftKey);
      return;
    }
    this.loadDrafts(true, false).catch(() => {
    });
  }

  private handlePrivateMessageSheetDismiss(submitted: boolean): void {
    const draftKey: string = this.activePrivateMessageDraft !== null ? (this.activePrivateMessageDraft as Draft).draftKey : '';
    this.isPrivateMessageSheetVisible = false;
    this.activePrivateMessageDraft = null;
    if (submitted && draftKey.length > 0) {
      this.removeDraftLocally(draftKey);
      return;
    }
    this.loadDrafts(true, false).catch(() => {
    });
  }

  private handleTopicSheetDismiss(submitted: boolean): void {
    const draftKey: string = this.activeTopicDraft !== null ? (this.activeTopicDraft as Draft).draftKey : '';
    this.isTopicSheetVisible = false;
    this.activeTopicDraft = null;
    if (submitted && draftKey.length > 0) {
      this.removeDraftLocally(draftKey);
      if (this.createdTopicId > 0) {
        RouterManager.pushTopicDetail(this.createdTopicId);
      }
      this.createdTopicId = 0;
      return;
    }
    this.createdTopicId = 0;
    this.loadDrafts(true, false).catch(() => {
    });
  }

  build() {
    HdsNavDestination() {
      Stack({ alignContent: Alignment.Bottom }) {
        Column() {
          this.TopBar()

          Refresh({ refreshing: false }) {
            if (this.isLoading && this.drafts.length === 0 && this.errorMessage.length === 0) {
              Column() {
                LoadingSpinner({ message: '' })
              }
              .width('100%')
              .height('100%')
              .justifyContent(FlexAlign.Center)
              .alignItems(HorizontalAlign.Center)
            } else if (this.errorMessage.length > 0 && this.drafts.length === 0) {
              Column() {
                ErrorView({
                  title: '加载失败',
                  message: this.errorMessage,
                  onRetry: () => {
                    this.loadDrafts(true, true).catch(() => {
                    });
                  }
                })
              }
              .width('100%')
              .height('100%')
              .justifyContent(FlexAlign.Center)
            } else {
              List() {
                if (!this.isLoading && this.drafts.length === 0) {
                  ListItem() {
                    Column() {
                      SymbolGlyph($r('sys.symbol.notepad'))
                        .fontSize(30)
                        .fontColor([$r('app.color.on_surface_tertiary')])
                        .margin({ bottom: 12 })
                      Text('暂无草稿')
                        .fontSize(14)
                        .fontColor($r('app.color.on_surface_secondary'))
                    }
                    .width('100%')
                    .padding({ top: 96, bottom: 96 })
                    .alignItems(HorizontalAlign.Center)
                  }
                } else {
                  ForEach(this.drafts, (draft: Draft) => {
                    ListItem() {
                      this.DraftCard(draft)
                    }
                  }, (draft: Draft) => draft.draftKey)
                }

                if (this.loadMoreFailed) {
                  ListItem() {
                    Text('加载更多失败，点击重试')
                      .fontSize(13)
                      .fontColor($r('app.color.primary'))
                      .width('100%')
                      .textAlign(TextAlign.Center)
                      .padding({ top: 12, bottom: 12 })
                      .onClick(() => {
                        this.loadDrafts(false, false).catch(() => {
                        });
                      })
                  }
                } else if (this.isLoadingMore) {
                  ListItem() {
                    Row() {
                      LoadingProgress().width(18).height(18)
                      Text('加载中...')
                        .fontSize(13)
                        .fontColor($r('app.color.on_surface_tertiary'))
                        .margin({ left: 8 })
                    }
                    .width('100%')
                    .height(44)
                    .justifyContent(FlexAlign.Center)
                  }
                } else if (!this.hasMore && this.drafts.length > 0) {
                  ListItem() {
                    Text('没有更多了')
                      .fontSize(12)
                      .fontColor($r('app.color.on_surface_tertiary'))
                      .width('100%')
                      .textAlign(TextAlign.Center)
                      .padding({ top: 16, bottom: 12 })
                  }
                }
              }
              .width('100%')
              .height('100%')
              .padding({ left: 16, right: 16, top: 12, bottom: 12 + WindowManager.getSystemAvoidAreaBottomVp() })
              .backgroundColor($r('app.color.background'))
              .scrollBar(BarState.Off)
              .onReachEnd(() => {
                this.loadDrafts(false, false).catch(() => {
                });
              })
            }
          }
          .onRefreshing(() => {
            this.loadDrafts(true, false).catch(() => {
            });
          })
          .layoutWeight(1)
        }
        .width('100%')
        .height('100%')
        .backgroundColor($r('app.color.background'))
        .padding({ top: WindowManager.getSystemAvoidAreaTopVp() })

        Column() {
        }
        .width(0)
        .height(0)
        .bindSheet($$this.isReplySheetVisible, this.ReplyDraftSheetBuilder, {
          height: SheetSize.LARGE,
          dragBar: false,
          showClose: false,
          backgroundColor: $r('app.color.surface')
        })

        Column() {
        }
        .width(0)
        .height(0)
        .bindSheet($$this.isPrivateMessageSheetVisible, this.PrivateMessageDraftSheetBuilder, {
          height: SheetSize.LARGE,
          dragBar: false,
          showClose: false,
          backgroundColor: $r('app.color.surface')
        })

        Column() {
        }
        .width(0)
        .height(0)
        .bindSheet($$this.isTopicSheetVisible, this.TopicDraftSheetBuilder, {
          height: SheetSize.LARGE,
          dragBar: false,
          showClose: false,
          backgroundColor: $r('app.color.surface')
        })
      }
    }
    .backgroundColor($r('app.color.background'))
    .hideTitleBar(true)
    .hideToolBar(true)
  }

  @Builder
  private TopBar() {
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
        RouterManager.pop();
      })

      Text('我的草稿')
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.on_surface'))
        .layoutWeight(1)

      Blank().width(44)
    }
    .width('100%')
    .height(TOP_BAR_HEIGHT)
    .padding({ left: 8, right: 8 })
    .backgroundColor($r('app.color.background'))
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private DraftCard(draft: Draft) {
    Row() {
      SmartAvatar({
        avatarUrl: draft.getAvatarUrl(96),
        avatarSize: 42,
        avatarRadius: 21,
        fallbackText: draft.username !== null ? draft.username as string : 'D',
        bgColor: '#E8EAF0'
      })

      Column() {
        Row() {
          Text(this.getDraftTypeLabel(draft))
            .fontSize(11)
            .fontColor($r('app.color.primary'))
            .padding({ left: 8, right: 8, top: 3, bottom: 3 })
            .backgroundColor($r('app.color.badge_background_light'))
            .borderRadius(10)

          if (draft.updatedAt !== null) {
            Text(TimeUtils.formatRelativeTime(draft.updatedAt))
              .fontSize(11)
              .fontColor($r('app.color.on_surface_tertiary'))
              .margin({ left: 8 })
          }
        }
        .alignItems(VerticalAlign.Center)

        Text(draft.displayTitle)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.on_surface'))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ top: 10 })

        if (this.getDraftPreviewText(draft).length > 0) {
          Text(this.getDraftPreviewText(draft))
            .fontSize(12)
            .fontColor($r('app.color.on_surface_secondary'))
            .maxLines(3)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .margin({ top: 8 })
        }

        Row() {
          Text('继续编辑')
            .fontSize(12)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.primary'))
            .padding({ left: 8, right: 8, top: 4, bottom: 4 })
            .backgroundColor($r('app.color.badge_background_light'))
            .borderRadius(10)
            .onClick(() => {
              this.openDraft(draft).catch(() => {
              });
            })

          Text(this.deletingDraftKey === draft.draftKey ? '删除中...' : '删除')
            .fontSize(12)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.error'))
            .padding({ left: 8, right: 8, top: 4, bottom: 4 })
            .backgroundColor('#FDECEC')
            .borderRadius(10)
            .margin({ left: 8 })
            .enabled(this.deletingDraftKey.length === 0 || this.deletingDraftKey === draft.draftKey)
            .onClick(() => {
              this.deleteDraft(draft).catch(() => {
              });
            })
        }
        .margin({ top: 12 })
      }
      .layoutWeight(1)
      .margin({ left: 14 })
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .padding({ left: 14, right: 14, top: 14, bottom: 14 })
    .backgroundColor($r('app.color.surface'))
    .borderRadius(16)
    .margin({ bottom: 12 })
    .alignItems(VerticalAlign.Top)
  }

  @Builder
  private ReplyDraftSheetBuilder() {
    if (this.activeReplyDraft !== null && (this.activeReplyDraft as Draft).topicId !== null) {
      ReplyComposerSheet({
        topicId: (this.activeReplyDraft as Draft).topicId as number,
        replyToPostNumber: (this.activeReplyDraft as Draft).replyToPostNumberFromKey !== null
          ? (this.activeReplyDraft as Draft).replyToPostNumberFromKey as number
          : 0,
        requestKey: (this.activeReplyDraft as Draft).draftKey,
        onDismiss: (submitted: boolean) => {
          this.handleReplySheetDismiss(submitted);
        }
      })
    }
  }

  @Builder
  private PrivateMessageDraftSheetBuilder() {
    if (this.activePrivateMessageDraft !== null) {
      PrivateMessageComposerSheet({
        targetUsername: this.getPrivateMessageTarget(this.activePrivateMessageDraft as Draft),
        targetAvatarUrl: (this.activePrivateMessageDraft as Draft).getAvatarUrl(96),
        requestKey: (this.activePrivateMessageDraft as Draft).draftKey,
        onDismiss: (submitted: boolean) => {
          this.handlePrivateMessageSheetDismiss(submitted);
        }
      })
    }
  }

  @Builder
  private TopicDraftSheetBuilder() {
    if (this.activeTopicDraft !== null) {
      CreateTopicComposerSheet({
        onSubmitted: (topicId: number) => {
          this.createdTopicId = topicId;
        },
        onDismiss: (submitted: boolean) => {
          this.handleTopicSheetDismiss(submitted);
        }
      })
    }
  }
}
