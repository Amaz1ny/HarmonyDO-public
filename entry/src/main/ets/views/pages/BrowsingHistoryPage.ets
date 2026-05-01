import {
  HdsNavDestination,
  HdsNavDestinationTitleMode
} from '@kit.UIDesignKit';
import { Topic, TopicUser } from '../../models/Topic';
import { Category } from '../../models/Category';
import { SearchInType } from '../../models/SearchFilter';
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

@ComponentV2
export struct BrowsingHistoryPage {
  @Local topics: Topic[] = [];
  @Local isLoading: boolean = true;
  @Local isRefreshing: boolean = false;
  @Local isLoadingMore: boolean = false;
  @Local hasMore: boolean = false;
  @Local errorMessage: string = '';
  @Local loadMoreFailed: boolean = false;

  @Local isTopicPreviewVisible: boolean = false;
  @Local previewTopic: Topic | null = null;
  @Local previewCategory: Category | null = null;
  @Local previewParentCategory: Category | null = null;

  private page: number = 0;
  private categoryMap: Map<number, Category> = new Map();
  private isResetLoading: boolean = false;
  private contentScroller: Scroller = new Scroller();

  aboutToAppear(): void {
    this.loadTopics(true, this.topics.length === 0, false).catch(() => {
    });
  }

  private normalizeErrorMessage(err: Object): string {
    if (err === undefined || err === null) {
      return '加载浏览历史失败';
    }
    const text: string = err.toString().replace('Error: ', '').trim();
    return text.length > 0 ? text : '加载浏览历史失败';
  }

  private async ensureContext(): Promise<void> {
    const auth: AuthService = AuthService.getInstance();
    await auth.init();
    if (!auth.getIsLoggedIn()) {
      throw new Error('请先登录');
    }
    if (this.categoryMap.size === 0) {
      const site = await ApiClient.getInstance().getSiteInfo();
      const map: Map<number, Category> = new Map();
      for (let i = 0; i < site.categories.length; i++) {
        const category: Category = site.categories[i];
        map.set(category.id, category);
      }
      this.categoryMap = map;
    }
  }

  private async loadTopics(
    reset: boolean,
    showLoading: boolean = false,
    showRefreshIndicator: boolean = !showLoading
  ): Promise<void> {
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
      if (!this.hasMore || this.isLoading) {
        return;
      }
      this.isLoadingMore = true;
      this.loadMoreFailed = false;
    }

    try {
      await this.ensureContext();
      const targetPage: number = reset ? 0 : (this.page + 1);
      const response = await ApiClient.getInstance().getBrowsingHistory(targetPage, reset);
      if (reset) {
        this.topics = response.topics;
        this.page = 0;
      } else {
        const merged: Topic[] = [];
        for (let i = 0; i < this.topics.length; i++) {
          merged.push(this.topics[i]);
        }
        for (let i = 0; i < response.topics.length; i++) {
          const item: Topic = response.topics[i];
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
        this.topics = merged;
        this.page = targetPage;
      }
      this.hasMore = response.moreTopicsUrl !== null && (response.moreTopicsUrl as string).trim().length > 0;
    } catch (err) {
      if (reset) {
        this.errorMessage = this.normalizeErrorMessage(err);
      } else {
        this.loadMoreFailed = true;
      }
    } finally {
      if (reset) {
        this.isResetLoading = false;
      }
      this.isLoading = false;
      this.isRefreshing = false;
      this.isLoadingMore = false;
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

  private getCategory(topic: Topic): Category | null {
    const catId: number = Number(topic.categoryId);
    if (isNaN(catId)) {
      return null;
    }
    return this.categoryMap.has(catId) ? this.categoryMap.get(catId) as Category : null;
  }

  private getParentCategory(category: Category): Category | null {
    const parentId: number | null = category.parentCategoryId;
    if (parentId === null || !this.categoryMap.has(parentId)) {
      return null;
    }
    return this.categoryMap.get(parentId) as Category;
  }

  private openTopicPreview(topic: Topic): void {
    const category: Category | null = this.getCategory(topic);
    this.previewTopic = topic;
    this.previewCategory = category;
    this.previewParentCategory = category !== null ? this.getParentCategory(category as Category) : null;
    this.isTopicPreviewVisible = true;
  }

  private closeTopicPreview(): void {
    this.isTopicPreviewVisible = false;
    this.previewTopic = null;
    this.previewCategory = null;
    this.previewParentCategory = null;
  }

  private openTopicFromPreview(topic: Topic): void {
    this.closeTopicPreview();
    RouterManager.pushTopicDetail(topic.id, topic.lastReadPostNumber);
  }

  private openSearch(): void {
    RouterManager.pushSearch('', SearchInType.SEEN.value);
  }

  private getStatusBarContentColor(): string {
    return ImmersiveHdsTitleBarHelper.getStatusBarContentColor();
  }

  private getContentTopSpacerHeight(): number {
    return ImmersiveHdsTitleBarHelper.getContentTopSpacerHeightVp();
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      HdsNavDestination() {
        Stack({ alignContent: Alignment.Center }) {
          Column() {
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
                      this.loadTopics(true, true).catch(() => {
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
                    // 参考 chatcube 的沉浸式结构：NavDestination 自身延伸进状态栏，
                    // 内容列表只在首项留出“状态栏 + MINI 标题栏 + 渐变蒙版”高度。
                    // 这样首屏不被标题栏遮挡，滚动时内容仍可进入状态栏/标题栏背后。
                    Blank()
                      .height(this.getContentTopSpacerHeight())
                      .width('100%')

                    if (!this.isLoading && this.topics.length === 0) {
                      Column() {
                        SymbolGlyph($r('sys.symbol.clock'))
                          .fontSize(30)
                          .fontColor([$r('app.color.on_surface_tertiary')])
                          .margin({ bottom: 12 })
                        Text('暂无浏览历史')
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
                          category: this.getCategory(topic),
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
                      Text('加载更多失败，点击重试')
                        .fontSize(13)
                        .fontColor($r('app.color.primary'))
                        .width('100%')
                        .textAlign(TextAlign.Center)
                        .padding({ top: 12, bottom: 12 })
                        .onClick(() => {
                          this.loadTopics(false, false).catch(() => {
                          });
                        })
                    } else if (this.isLoadingMore) {
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
                    } else if (!this.hasMore && this.topics.length > 0) {
                      Text('没有更多了')
                        .fontSize(12)
                        .fontColor($r('app.color.on_surface_tertiary'))
                        .width('100%')
                        .textAlign(TextAlign.Center)
                        .padding({ top: 16, bottom: 12 })
                    }
                  }
                  .width('100%')
                  .padding({ left: 12, right: 12, top: 12, bottom: 12 + WindowManager.getSystemAvoidAreaBottomVp() })
                  .alignItems(HorizontalAlign.Center)
                }
                .width('100%')
                .height('100%')
                .backgroundColor($r('app.color.background'))
                .scrollBar(BarState.Off)
                .edgeEffect(EdgeEffect.Spring)
                .onReachEnd(() => {
                  this.loadTopics(false, false).catch(() => {
                  });
                })
              }
            }
            .onRefreshing(() => {
              this.loadTopics(true, false, true).catch(() => {
              });
            })
            .layoutWeight(1)
          }
          .width('100%')
          .height('100%')
          .backgroundColor($r('app.color.background'))

          this.TopicPreviewOverlay()
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.background'))
      .titleMode(HdsNavDestinationTitleMode.MINI)
      .titleBar(ImmersiveHdsTitleBarHelper.buildImmersiveTitleBarWithMenu(
        '浏览历史',
        $r('sys.symbol.magnifyingglass'),
        '搜索浏览历史',
        () => {
          this.openSearch();
        }
      ))
      .hideTitleBar(false)
      .hideBackButton(false)
      .hideToolBar(true)
      .bindToScrollable([this.contentScroller])
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
      .systemBarStyle(
        { statusBarContentColor: this.getStatusBarContentColor() },
        { statusBarContentColor: this.getStatusBarContentColor() }
      )
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.background'))
  }

  @Builder
  private TopicPreviewOverlay() {
    if (this.isTopicPreviewVisible && this.previewTopic !== null) {
      Stack({ alignContent: Alignment.Center }) {
        Column() {
        }
        .width('100%')
        .height('100%')
        .backgroundColor('#66000000')
        .onClick(() => {
          this.closeTopicPreview();
        })

        TopicPreviewDialog({
          topic: this.previewTopic as Topic,
          category: this.previewCategory,
          parentCategory: this.previewParentCategory,
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
