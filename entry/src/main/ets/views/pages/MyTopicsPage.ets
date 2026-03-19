import { HdsNavDestination } from '@kit.UIDesignKit';
import { Topic, TopicUser } from '../../models/Topic';
import { Category } from '../../models/Category';
import { SearchInType } from '../../models/SearchFilter';
import { AuthService } from '../../services/auth/AuthService';
import { ApiClient } from '../../services/network/ApiClient';
import { UrlUtils } from '../../common/utils/UrlUtils';
import { RouterManager } from '../../common/utils/RouterManager';
import { WindowManager } from '../../common/utils/WindowManager';
import { AppSettingsService } from '../../services/storage/AppSettingsService';
import { LoadingSpinner } from '../components/LoadingSpinner';
import { ErrorView } from '../components/ErrorView';
import { TopicCard } from '../components/TopicCard';
import { TopicPreviewDialog } from '../components/TopicPreviewDialog';

const TOP_BAR_HEIGHT: number = 56;

@ComponentV2
export struct MyTopicsPage {
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
  @Local enableLongPressPreview: boolean = true;

  private page: number = 0;
  private username: string = '';
  private categoryMap: Map<number, Category> = new Map();
  private settingsListener: (() => void) | null = null;

  aboutToAppear(): void {
    this.attachSettingsListener();
    if (this.topics.length === 0) {
      this.loadTopics(true, true).catch(() => {
      });
    }
  }

  aboutToDisappear(): void {
    if (this.settingsListener !== null) {
      AppSettingsService.getInstance().removeListener(this.settingsListener);
      this.settingsListener = null;
    }
  }

  private attachSettingsListener(): void {
    if (this.settingsListener !== null) {
      return;
    }
    this.settingsListener = () => {
      this.enableLongPressPreview = AppSettingsService.getInstance().getFeatureSettings().longPressPreview;
    };
    AppSettingsService.getInstance().addListener(this.settingsListener);
    AppSettingsService.getInstance().ensureInit().then(() => {
      this.enableLongPressPreview = AppSettingsService.getInstance().getFeatureSettings().longPressPreview;
    }).catch(() => {
    });
  }

  private normalizeErrorMessage(err: Object): string {
    if (err === undefined || err === null) {
      return '加载我的话题失败';
    }
    const text: string = err.toString().replace('Error: ', '').trim();
    return text.length > 0 ? text : '加载我的话题失败';
  }

  private async ensureContext(): Promise<void> {
    const auth: AuthService = AuthService.getInstance();
    await auth.init();
    this.username = auth.getCurrentUsername().trim();
    if (this.username.length === 0) {
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

  private async loadTopics(reset: boolean, showLoading: boolean = false): Promise<void> {
    if (this.isLoadingMore) {
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
      await this.ensureContext();
      const targetPage: number = reset ? 0 : (this.page + 1);
      const response = await ApiClient.getInstance().getUserCreatedTopics(this.username, targetPage);
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
    RouterManager.pushSearch('', SearchInType.CREATED.value);
  }

  build() {
    HdsNavDestination() {
      Stack({ alignContent: Alignment.Center }) {
        Column() {
          this.TopBar()

          Refresh({ refreshing: false }) {
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
              List() {
                if (!this.isLoading && this.topics.length === 0) {
                  ListItem() {
                    Column() {
                      SymbolGlyph($r('sys.symbol.message'))
                        .fontSize(30)
                        .fontColor([$r('app.color.on_surface_tertiary')])
                        .margin({ bottom: 12 })
                      Text('暂无话题')
                        .fontSize(14)
                        .fontColor($r('app.color.on_surface_secondary'))
                    }
                    .width('100%')
                    .padding({ top: 96, bottom: 96 })
                    .alignItems(HorizontalAlign.Center)
                  }
                } else {
                  ForEach(this.topics, (topic: Topic) => {
                    ListItem() {
                      TopicCard({
                        topic: topic,
                        category: this.getCategory(topic),
                        opAvatarUrl: this.getOpAvatarUrl(topic),
                        enableLongPress: this.enableLongPressPreview,
                        onCardClick: (t: Topic) => {
                          RouterManager.pushTopicDetail(t.id, t.lastReadPostNumber);
                        },
                        onCardLongPress: (t: Topic) => {
                          this.openTopicPreview(t);
                        }
                      })
                    }
                  }, (topic: Topic) => topic.id.toString())
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
                        this.loadTopics(false, false).catch(() => {
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
                } else if (!this.hasMore && this.topics.length > 0) {
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
              .padding({ left: 12, right: 12, top: 12, bottom: 12 + WindowManager.getSystemAvoidAreaBottomVp() })
              .backgroundColor($r('app.color.background'))
              .scrollBar(BarState.Off)
              .onReachEnd(() => {
                this.loadTopics(false, false).catch(() => {
                });
              })
            }
          }
          .onRefreshing(() => {
            this.loadTopics(true, false).catch(() => {
            });
          })
          .layoutWeight(1)
        }
        .width('100%')
        .height('100%')
        .backgroundColor($r('app.color.background'))
        .padding({ top: WindowManager.getSystemAvoidAreaTopVp() })

        this.TopicPreviewOverlay()
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

      Text('我的话题')
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.on_surface'))
        .layoutWeight(1)

      Row() {
        SymbolGlyph($r('sys.symbol.magnifyingglass'))
          .fontSize(18)
          .fontColor([$r('app.color.on_surface')])
      }
      .width(44)
      .height(44)
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
      .onClick(() => {
        this.openSearch();
      })
    }
    .width('100%')
    .height(TOP_BAR_HEIGHT)
    .padding({ left: 8, right: 8 })
    .backgroundColor($r('app.color.background'))
    .alignItems(VerticalAlign.Center)
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
