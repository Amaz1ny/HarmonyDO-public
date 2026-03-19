import { HdsNavDestination } from '@kit.UIDesignKit';
import { Topic } from '../../models/Topic';
import { Category } from '../../models/Category';
import { SearchInType } from '../../models/SearchFilter';
import { ApiClient } from '../../services/network/ApiClient';
import { AppSettingsService } from '../../services/storage/AppSettingsService';
import { RouterManager } from '../../common/utils/RouterManager';
import { WindowManager } from '../../common/utils/WindowManager';
import { LoadingSpinner } from '../components/LoadingSpinner';
import { ErrorView } from '../components/ErrorView';
import { TopicCard, CompactTopicCard } from '../components/TopicCard';
import { TopicPreviewDialog } from '../components/TopicPreviewDialog';

const TOP_BAR_HEIGHT: number = 56;

@ComponentV2
export struct BrowsingHistoryPage {
  @Local topics: Topic[] = [];
  @Local isLoading: boolean = true;
  @Local isRefreshing: boolean = false;
  @Local isLoadingMore: boolean = false;
  @Local hasMore: boolean = false;
  @Local errorMessage: string = '';
  @Local loadMoreFailed: boolean = false;
  @Local searchMode: boolean = false;
  @Local searchQuery: string = '';
  @Local filterMode: string = 'all';
  @Local enableLongPressPreview: boolean = true;
  @Local previewTopic: Topic | null = null;
  @Local previewCategory: Category | null = null;
  @Local previewParentCategory: Category | null = null;
  @Local isTopicPreviewVisible: boolean = false;

  private categoryMap: Map<number, Category> = new Map();
  private page: number = 0;
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

  private async ensureCategoryMap(): Promise<void> {
    if (this.categoryMap.size > 0) {
      return;
    }
    const site = await ApiClient.getInstance().getSiteInfo();
    const map: Map<number, Category> = new Map();
    for (let i: number = 0; i < site.categories.length; i++) {
      const category: Category = site.categories[i];
      map.set(category.id, category);
    }
    this.categoryMap = map;
  }

  private async loadTopics(reset: boolean, showLoading: boolean = false): Promise<void> {
    if (this.isLoadingMore) {
      return;
    }
    if (reset) {
      if (showLoading) {
        this.isLoading = true;
      }
      this.errorMessage = '';
      this.loadMoreFailed = false;
      this.page = 0;
    } else {
      if (!this.hasMore) {
        return;
      }
      this.isLoadingMore = true;
      this.loadMoreFailed = false;
    }

    try {
      await this.ensureCategoryMap();
      const nextPage: number = reset ? 0 : this.page + 1;
      const response = await ApiClient.getInstance().getBrowsingHistory(nextPage);
      if (reset) {
        this.topics = response.topics;
      } else {
        const merged: Topic[] = [];
        for (let i: number = 0; i < this.topics.length; i++) {
          merged.push(this.topics[i]);
        }
        for (let i: number = 0; i < response.topics.length; i++) {
          merged.push(response.topics[i]);
        }
        this.topics = merged;
      }
      this.page = nextPage;
      this.hasMore = (response.moreTopicsUrl !== null && (response.moreTopicsUrl as string).trim().length > 0)
        || response.topics.length >= response.perPage;
      this.errorMessage = '';
    } catch (err) {
      const message: string = this.normalizeErrorMessage(err);
      if (reset) {
        this.errorMessage = message;
      } else {
        this.loadMoreFailed = true;
      }
    } finally {
      this.isLoading = false;
      this.isRefreshing = false;
      this.isLoadingMore = false;
    }
  }

  private normalizeErrorMessage(err: Object): string {
    if (err === undefined || err === null) {
      return '加载浏览历史失败';
    }
    const text: string = err.toString().replace('Error: ', '').trim();
    return text.length > 0 ? text : '加载浏览历史失败';
  }

  private getCategory(topic: Topic): Category | null {
    const id: number = Number(topic.categoryId);
    return this.categoryMap.has(id) ? this.categoryMap.get(id) as Category : null;
  }

  private getDisplayTopics(): Topic[] {
    const query: string = this.searchQuery.trim().toLowerCase();
    const filtered: Topic[] = [];
    for (let i: number = 0; i < this.topics.length; i++) {
      const topic: Topic = this.topics[i];
      if (this.filterMode === 'unseen' && !topic.unseen) {
        continue;
      }
      if (this.filterMode === 'unread' && topic.unread <= 0) {
        continue;
      }
      if (this.filterMode === 'read' && (topic.unseen || topic.unread > 0 || topic.lastReadPostNumber <= 0)) {
        continue;
      }
      if (query.length > 0) {
        const title: string = topic.title.toLowerCase();
        const excerpt: string = topic.excerpt !== null ? (topic.excerpt as string).toLowerCase() : '';
        if (title.indexOf(query) < 0 && excerpt.indexOf(query) < 0) {
          continue;
        }
      }
      filtered.push(topic);
    }
    return filtered;
  }

  private openTopic(topic: Topic): void {
    const targetPostNumber: number = topic.lastReadPostNumber > 0 ? topic.lastReadPostNumber : 0;
    RouterManager.pushTopicDetail(topic.id, targetPostNumber);
  }

  private openTopicPreview(topic: Topic): void {
    this.previewTopic = topic;
    this.previewCategory = this.getCategory(topic);
    this.previewParentCategory = null;
    this.isTopicPreviewVisible = true;
  }

  private closeTopicPreview(): void {
    this.isTopicPreviewVisible = false;
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
        if (this.searchMode) {
          this.searchMode = false;
          this.searchQuery = '';
          return;
        }
        RouterManager.pop();
      })

      if (this.searchMode) {
        TextInput({ text: this.searchQuery, placeholder: '搜索浏览历史' })
          .layoutWeight(1)
          .height(38)
          .backgroundColor($r('app.color.search_background'))
          .borderRadius(20)
          .padding({ left: 12, right: 12 })
          .fontSize(14)
          .onChange((value: string) => {
            this.searchQuery = value;
          })
      } else {
        Text('浏览历史')
          .fontSize(17)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.on_surface'))
          .layoutWeight(1)
      }

      if (this.searchMode) {
        Row() {
          SymbolGlyph($r('sys.symbol.line_3_horizontal'))
            .fontSize(18)
            .fontColor([AppSettingsService.getInstance().getPrimaryColor()])
        }
        .width(44)
        .height(44)
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Center)
        .onClick(() => {
          RouterManager.pushSearch(this.searchQuery, SearchInType.SEEN.value);
        })
      }

      Row() {
        SymbolGlyph(this.searchMode ? $r('sys.symbol.xmark') : $r('sys.symbol.magnifyingglass'))
          .fontSize(18)
          .fontColor([AppSettingsService.getInstance().getPrimaryColor()])
      }
      .width(44)
      .height(44)
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
      .onClick(() => {
        if (this.searchMode) {
          this.searchQuery = '';
          this.searchMode = false;
        } else {
          this.searchMode = true;
        }
      })
    }
    .width('100%')
    .height(TOP_BAR_HEIGHT)
    .padding({ left: 8, right: 8 })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private FilterBar() {
    Row() {
      this.FilterChip('全部', 'all')
      this.FilterChip('未浏览', 'unseen')
      this.FilterChip('未读完', 'unread')
      this.FilterChip('已读完', 'read')
    }
    .width('100%')
    .padding({ left: 12, right: 12, bottom: 8 })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private FilterChip(label: string, value: string) {
    Row() {
      Text(label)
        .fontSize(12)
        .fontColor(this.filterMode === value ? AppSettingsService.getInstance().getPrimaryColor() : $r('app.color.on_surface_secondary'))
    }
    .padding({ left: 10, right: 10, top: 6, bottom: 6 })
    .backgroundColor(this.filterMode === value ? AppSettingsService.getInstance().getPrimaryColorWithAlpha(0.12) : $r('app.color.surface_variant'))
    .borderRadius(14)
    .margin({ right: 8 })
    .onClick(() => {
      this.filterMode = value;
    })
  }

  @Builder
  private EmptyState() {
    Column() {
      SymbolGlyph($r('sys.symbol.clock'))
        .fontSize(42)
        .fontColor([$r('app.color.on_surface_tertiary')])
        .margin({ bottom: 12 })
      Text(this.topics.length === 0 ? '还没有浏览历史' : '没有符合条件的浏览记录')
        .fontSize(14)
        .fontColor($r('app.color.on_surface_secondary'))
    }
    .width('100%')
    .padding({ top: 96, bottom: 96 })
    .alignItems(HorizontalAlign.Center)
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
            this.closeTopicPreview();
            this.openTopic(topic);
          }
        })
      }
      .width('100%')
      .height('100%')
    }
  }

  build() {
    HdsNavDestination() {
      Stack() {
        Column() {
          this.TopBar()
          this.FilterBar()

          if (this.isLoading) {
            LoadingSpinner({ message: '正在获取浏览历史...' })
              .layoutWeight(1)
          } else if (this.errorMessage.length > 0) {
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
            .layoutWeight(1)
            .justifyContent(FlexAlign.Center)
          } else {
            Refresh({ refreshing: this.isRefreshing }) {
              List() {
                if (this.getDisplayTopics().length === 0) {
                  ListItem() {
                    this.EmptyState()
                  }
                } else {
                  ForEach(this.getDisplayTopics(), (topic: Topic) => {
                    ListItem() {
                      if (topic.pinned) {
                        CompactTopicCard({
                          topic: topic,
                          category: this.getCategory(topic),
                          enableLongPress: this.enableLongPressPreview,
                          onCardClick: (t: Topic) => {
                            this.openTopic(t);
                          },
                          onCardLongPress: (t: Topic) => {
                            this.openTopicPreview(t);
                          }
                        })
                      } else {
                        TopicCard({
                          topic: topic,
                          category: this.getCategory(topic),
                          enableLongPress: this.enableLongPressPreview,
                          onCardClick: (t: Topic) => {
                            this.openTopic(t);
                          },
                          onCardLongPress: (t: Topic) => {
                            this.openTopicPreview(t);
                          }
                        })
                      }
                    }
                  }, (topic: Topic) => topic.id.toString())
                }

                if (this.loadMoreFailed) {
                  ListItem() {
                    Text('加载更多失败，点击重试')
                      .fontSize(13)
                      .fontColor(AppSettingsService.getInstance().getPrimaryColor())
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
                      LoadingProgress().width(20).height(20)
                      Text('加载中...')
                        .fontSize(13)
                        .fontColor($r('app.color.on_surface_tertiary'))
                        .margin({ left: 8 })
                    }
                    .width('100%')
                    .justifyContent(FlexAlign.Center)
                    .padding({ top: 12, bottom: 12 })
                  }
                } else if (!this.hasMore && this.getDisplayTopics().length > 0) {
                  ListItem() {
                    Text('没有更多了')
                      .fontSize(12)
                      .fontColor($r('app.color.on_surface_tertiary'))
                      .width('100%')
                      .textAlign(TextAlign.Center)
                      .padding({ top: 12, bottom: 12 })
                  }
                }
              }
              .width('100%')
              .height('100%')
              .padding({ left: 12, right: 12, bottom: 12 + WindowManager.getSystemAvoidAreaBottomVp() })
              .backgroundColor($r('app.color.background'))
              .scrollBar(BarState.Off)
              .onReachEnd(() => {
                this.loadTopics(false, false).catch(() => {
                });
              })
            }
            .onRefreshing(() => {
              this.isRefreshing = true;
              this.loadTopics(true, false).catch(() => {
              });
            })
            .layoutWeight(1)
          }
        }
        .width('100%')
        .height('100%')
        .padding({ top: WindowManager.getSystemAvoidAreaTopVp() })
        .backgroundColor($r('app.color.background'))

        this.TopicPreviewOverlay()
      }
    }
    .backgroundColor($r('app.color.background'))
    .hideTitleBar(true)
    .hideToolBar(true)
  }
}
