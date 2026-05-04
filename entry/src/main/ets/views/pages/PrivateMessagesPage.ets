import { HdsNavDestination, HdsNavDestinationTitleMode } from '@kit.UIDesignKit';
import { Topic, TopicListResponse, TopicUser } from '../../models/Topic';
import { AuthService } from '../../services/auth/AuthService';
import { ApiClient } from '../../services/network/ApiClient';
import { UrlUtils } from '../../common/utils/UrlUtils';
import { RouterManager } from '../../common/utils/RouterManager';
import { WindowManager } from '../../common/utils/WindowManager';
import { LoadingSpinner } from '../components/LoadingSpinner';
import { ErrorView } from '../components/ErrorView';
import { TopicCard } from '../components/TopicCard';
import { TopicPreviewDialog } from '../components/TopicPreviewDialog';
import { ImmersiveHdsTitleBarHelper } from '../components/ImmersiveHdsTitleBarHelper';
import { ModalChromeHelper } from '../components/ModalChromeHelper';
import { ThemeManager } from '../../common/theme/ThemeManager';

const PM_TAB_INBOX: number = 0;
const PM_TAB_SENT: number = 1;
const PM_TAB_ARCHIVE: number = 2;

@ComponentV2
export struct PrivateMessagesPage {
  @Local currentTabIndex: number = PM_TAB_INBOX;
  @Local topics: Topic[] = [];
  @Local isLoading: boolean = true;
  @Local isRefreshing: boolean = false;
  @Local isLoadingMore: boolean = false;
  @Local hasMore: boolean = false;
  @Local errorMessage: string = '';
  @Local loadMoreFailed: boolean = false;

  @Local isTopicPreviewVisible: boolean = false;
  @Local previewTopic: Topic | null = null;

  private username: string = '';
  private inboxTopics: Topic[] = [];
  private sentTopics: Topic[] = [];
  private archiveTopics: Topic[] = [];
  private pageByTab: number[] = [0, 0, 0];
  private hasMoreByTab: boolean[] = [false, false, false];
  private loadedByTab: boolean[] = [false, false, false];
  private isResetLoading: boolean = false;
  private contentScroller: Scroller = new Scroller();

  aboutToAppear(): void {
    if (!this.isTabLoaded(this.currentTabIndex)) {
      this.loadMessages(true, true, false).catch(() => {
      });
    }
  }

  private normalizeErrorMessage(err: Object): string {
    if (err === undefined || err === null) {
      return '加载私信失败';
    }
    const text: string = err.toString().replace('Error: ', '').trim();
    return text.length > 0 ? text : '加载私信失败';
  }

  private async ensureContext(): Promise<void> {
    const auth: AuthService = AuthService.getInstance();
    await auth.init();
    this.username = auth.getCurrentUsername().trim();
    if (this.username.length === 0) {
      throw new Error('请先登录');
    }
  }

  private isTabLoaded(index: number): boolean {
    if (index < 0 || index >= this.loadedByTab.length) {
      return false;
    }
    return this.loadedByTab[index];
  }

  private getCachedTopics(index: number): Topic[] {
    if (index === PM_TAB_SENT) {
      return this.sentTopics;
    }
    if (index === PM_TAB_ARCHIVE) {
      return this.archiveTopics;
    }
    return this.inboxTopics;
  }

  private setCachedTopics(index: number, list: Topic[]): void {
    if (index === PM_TAB_SENT) {
      this.sentTopics = list;
      return;
    }
    if (index === PM_TAB_ARCHIVE) {
      this.archiveTopics = list;
      return;
    }
    this.inboxTopics = list;
  }

  private getTabTitle(index: number): Resource {
    if (index === PM_TAB_SENT) {
      return $r('app.string.private_messages_sent');
    }
    if (index === PM_TAB_ARCHIVE) {
      return $r('app.string.private_messages_archive');
    }
    return $r('app.string.private_messages_inbox');
  }

  private getTabTextColor(index: number): ResourceColor {
    return this.currentTabIndex === index ? ThemeManager.getCurrentAccentColorHex() : $r('app.color.on_surface_secondary');
  }

  private async fetchMessages(index: number, page: number, forceRefresh: boolean): Promise<TopicListResponse> {
    if (index === PM_TAB_SENT) {
      return await ApiClient.getInstance().getPrivateMessagesSent(this.username, page, forceRefresh);
    }
    if (index === PM_TAB_ARCHIVE) {
      return await ApiClient.getInstance().getPrivateMessagesArchive(this.username, page, forceRefresh);
    }
    return await ApiClient.getInstance().getPrivateMessages(this.username, page, forceRefresh);
  }

  private mergeTopics(oldList: Topic[], newItems: Topic[]): Topic[] {
    const merged: Topic[] = [];
    for (let i = 0; i < oldList.length; i++) {
      merged.push(oldList[i]);
    }
    for (let i = 0; i < newItems.length; i++) {
      const item: Topic = newItems[i];
      let exists: boolean = false;
      for (let j = 0; j < merged.length; j++) {
        if (merged[j].id === item.id) {
          exists = true;
          break;
        }
      }
      if (!exists) {
        merged.push(item);
      }
    }
    return merged;
  }

  private syncVisibleState(index: number): void {
    if (this.currentTabIndex !== index) {
      return;
    }
    this.topics = this.getCachedTopics(index);
    this.hasMore = this.hasMoreByTab[index];
  }

  private async loadMessages(
    reset: boolean,
    showLoading: boolean = false,
    showRefreshIndicator: boolean = !showLoading
  ): Promise<void> {
    const targetIndex: number = this.currentTabIndex;
    if (this.isLoadingMore || (reset && this.isResetLoading)) {
      return;
    }
    if (reset) {
      this.isResetLoading = true;
      if (showLoading) {
        this.isLoading = true;
      } else if (showRefreshIndicator) {
        this.isRefreshing = true;
      }
      this.errorMessage = '';
      this.loadMoreFailed = false;
    } else {
      if (!this.hasMoreByTab[targetIndex] || this.isLoading) {
        return;
      }
      this.isLoadingMore = true;
      this.loadMoreFailed = false;
    }

    try {
      await this.ensureContext();
      const targetPage: number = reset ? 0 : (this.pageByTab[targetIndex] + 1);
      const response: TopicListResponse = await this.fetchMessages(targetIndex, targetPage, reset);
      if (reset) {
        this.setCachedTopics(targetIndex, response.topics);
        this.pageByTab[targetIndex] = 0;
      } else {
        this.setCachedTopics(targetIndex, this.mergeTopics(this.getCachedTopics(targetIndex), response.topics));
        this.pageByTab[targetIndex] = targetPage;
      }
      this.hasMoreByTab[targetIndex] = response.moreTopicsUrl !== null && (response.moreTopicsUrl as string).trim().length > 0;
      this.loadedByTab[targetIndex] = true;
      this.syncVisibleState(targetIndex);
    } catch (err) {
      if (reset && this.currentTabIndex === targetIndex) {
        this.errorMessage = this.normalizeErrorMessage(err);
      } else if (!reset && this.currentTabIndex === targetIndex) {
        this.loadMoreFailed = true;
      }
    } finally {
      if (reset) {
        this.isResetLoading = false;
      }
      if (this.currentTabIndex === targetIndex) {
        this.isLoading = false;
        this.isRefreshing = false;
        this.isLoadingMore = false;
      }
    }
  }

  private selectTab(index: number): void {
    if (index === this.currentTabIndex) {
      return;
    }
    this.currentTabIndex = index;
    this.topics = this.getCachedTopics(index);
    this.hasMore = this.hasMoreByTab[index];
    this.errorMessage = '';
    this.loadMoreFailed = false;
    this.isLoadingMore = false;
    this.isRefreshing = false;

    try {
      this.contentScroller.scrollTo({ xOffset: 0, yOffset: 0, animation: { duration: 180, curve: Curve.EaseOut } });
    } catch (_) {
    }

    if (!this.isTabLoaded(index)) {
      this.loadMessages(true, true, false).catch(() => {
      });
    } else {
      this.isLoading = false;
    }
  }

  private getOpAvatarUrl(topic: Topic): string {
    if (topic.posters.length > 0) {
      const user: TopicUser | null = topic.posters[0].user;
      if (user !== null) {
        return UrlUtils.getAvatarUrl((user as TopicUser).avatarTemplate, 68);
      }
    }
    return '';
  }

  private openTopicPreview(topic: Topic): void {
    this.previewTopic = topic;
    this.isTopicPreviewVisible = true;
  }

  private closeTopicPreview(): void {
    this.isTopicPreviewVisible = false;
    this.previewTopic = null;
  }

  private openTopicFromPreview(topic: Topic): void {
    this.closeTopicPreview();
    RouterManager.pushTopicDetail(topic.id, topic.lastReadPostNumber);
  }

  build() {
    HdsNavDestination() {
      Stack({ alignContent: Alignment.TopStart }) {
        Column() {
          Column() {
            Blank()
              .height(ImmersiveHdsTitleBarHelper.getContentTopSpacerHeightVp())
              .width('100%')

            this.FilterTabs()
          }
          .width('100%')
          .backgroundColor(ThemeManager.getCurrentAccentBackgroundColorHex())

          Divider()
            .color($r('app.color.divider_light'))
            .strokeWidth(0.5)

          Refresh({ refreshing: this.isRefreshing }) {
            if (this.isLoading && this.topics.length === 0 && this.errorMessage.length === 0) {
              Column() {
                LoadingSpinner({ message: '' })
              }
              .width('100%')
              .height('100%')
              .justifyContent(FlexAlign.Center)
              .alignItems(HorizontalAlign.Center)
            } else if (this.errorMessage.length > 0 && this.topics.length === 0) {
              Column() {
                ErrorView({
                  title: '加载失败',
                  message: this.errorMessage,
                  onRetry: () => {
                    this.loadMessages(true, true).catch(() => {
                    });
                  }
                })
              }
              .width('100%')
              .height('100%')
              .justifyContent(FlexAlign.Center)
            } else {
              Scroll(this.contentScroller) {
                Column() {
                  if (!this.isLoading && this.topics.length === 0) {
                    Column() {
                      SymbolGlyph($r('sys.symbol.message'))
                        .fontSize(34)
                        .fontColor([$r('app.color.on_surface_tertiary')])
                        .margin({ bottom: 12 })
                      Text($r('app.string.private_messages_empty'))
                        .fontSize(14)
                        .fontColor($r('app.color.on_surface_secondary'))
                    }
                    .width('100%')
                    .padding({ top: 96, bottom: 96 })
                    .alignItems(HorizontalAlign.Center)
                  } else {
                    ForEach(this.topics, (topic: Topic) => {
                      TopicCard({
                        topic: topic,
                        category: null,
                        opAvatarUrl: this.getOpAvatarUrl(topic),
                        onCardClick: (t: Topic) => {
                          RouterManager.pushTopicDetail(t.id, t.lastReadPostNumber);
                        },
                        onCardLongPress: (t: Topic) => {
                          this.openTopicPreview(t);
                        }
                      })
                    }, (topic: Topic) => topic.id.toString())
                  }

                  if (this.loadMoreFailed) {
                    Row() {
                      SymbolGlyph($r('sys.symbol.arrow_clockwise'))
                        .fontSize(14)
                        .fontColor([ThemeManager.getCurrentAccentColorHex()])
                      Text($r('app.string.private_messages_load_more_failed'))
                        .fontSize(13)
                        .fontColor(ThemeManager.getCurrentAccentColorHex())
                        .margin({ left: 6 })
                    }
                    .width('100%')
                    .height(44)
                    .justifyContent(FlexAlign.Center)
                    .onClick(() => {
                      this.loadMessages(false, false).catch(() => {
                      });
                    })
                  } else if (this.isLoadingMore) {
                    Row() {
                      LoadingProgress().width(18).height(18)
                      Text($r('app.string.loading'))
                        .fontSize(13)
                        .fontColor($r('app.color.on_surface_tertiary'))
                        .margin({ left: 8 })
                    }
                    .width('100%')
                    .height(44)
                    .justifyContent(FlexAlign.Center)
                  } else if (!this.hasMore && this.topics.length > 0) {
                    Text($r('app.string.no_more_data'))
                      .fontSize(12)
                      .fontColor($r('app.color.on_surface_tertiary'))
                      .width('100%')
                      .textAlign(TextAlign.Center)
                      .padding({ top: 16, bottom: 12 })
                  }
                }
                .width('100%')
                .constraintSize({ minHeight: '100%' })
                .padding({ left: 12, right: 12, top: 12, bottom: 12 + WindowManager.getSystemAvoidAreaBottomVp() })
                .justifyContent(FlexAlign.Start)
              }
              .width('100%')
              .height('100%')
              .backgroundColor(ThemeManager.getCurrentAccentBackgroundColorHex())
              .scrollBar(BarState.Off)
              .edgeEffect(EdgeEffect.Spring)
              .onReachEnd(() => {
                this.loadMessages(false, false).catch(() => {
                });
              })
            }
          }
          .onRefreshing(() => {
            this.loadMessages(true, false, true).catch(() => {
            });
          })
          .layoutWeight(1)
        }
        .width('100%')
        .height('100%')
        .backgroundColor(ThemeManager.getCurrentAccentBackgroundColorHex())

        this.TopicPreviewOverlay()
      }
      .width('100%')
      .height('100%')
    }
    .backgroundColor(ThemeManager.getCurrentAccentBackgroundColorHex())
    .titleMode(HdsNavDestinationTitleMode.MINI)
    .titleBar(ImmersiveHdsTitleBarHelper.buildImmersiveTitleBar($r('app.string.private_messages_title')))
    .hideTitleBar(false)
    .hideBackButton(false)
    .hideToolBar(true)
    .bindToScrollable([this.contentScroller])
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
    .systemBarStyle(
      { statusBarContentColor: ImmersiveHdsTitleBarHelper.getStatusBarContentColor() },
      { statusBarContentColor: ImmersiveHdsTitleBarHelper.getStatusBarContentColor() }
    )
  }

  @Builder
  private FilterTabs() {
    Row() {
      this.FilterTabItem(PM_TAB_INBOX)
      this.FilterTabItem(PM_TAB_SENT)
      this.FilterTabItem(PM_TAB_ARCHIVE)
    }
    .width('100%')
    .height(56)
    .padding({ left: 20, right: 20 })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private FilterTabItem(index: number) {
    Column() {
      Text(this.getTabTitle(index))
        .fontSize(16)
        .fontWeight(this.currentTabIndex === index ? FontWeight.Bold : FontWeight.Medium)
        .fontColor(this.getTabTextColor(index))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      Blank()
        .width(34)
        .height(4)
        .borderRadius(2)
        .backgroundColor(this.currentTabIndex === index ? ThemeManager.getCurrentAccentColorHex() : Color.Transparent)
        .margin({ top: 8 })
    }
    .layoutWeight(1)
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .onClick(() => {
      this.selectTab(index);
    })
  }

  @Builder
  private TopicPreviewOverlay() {
    if (this.isTopicPreviewVisible && this.previewTopic !== null) {
      Stack({ alignContent: Alignment.Center }) {
        Column() {
        }
        .width('100%')
        .height('100%')
        .backgroundColor(ModalChromeHelper.getMaskColor())
        .backgroundBlurStyle(ModalChromeHelper.getDialogBlurStyle())
        .onClick(() => {
          this.closeTopicPreview();
        })

        TopicPreviewDialog({
          topic: this.previewTopic as Topic,
          category: null,
          parentCategory: null,
          onClose: () => {
            this.closeTopicPreview();
          },
          onOpen: (topic: Topic) => {
            this.openTopicFromPreview(topic);
          }
        })
      }
      .width('100%')
      .height('100%')
    }
  }
}
