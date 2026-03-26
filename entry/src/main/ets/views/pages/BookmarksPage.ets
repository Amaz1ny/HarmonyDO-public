import { HdsNavDestination } from '@kit.UIDesignKit';
import { Topic, TopicUser } from '../../models/Topic';
import { Category } from '../../models/Category';
import { SearchInType } from '../../models/SearchFilter';
import { AuthService } from '../../services/auth/AuthService';
import { ApiClient } from '../../services/network/ApiClient';
import { TimeUtils } from '../../common/utils/TimeUtils';
import { UrlUtils } from '../../common/utils/UrlUtils';
import { RouterManager } from '../../common/utils/RouterManager';
import { ThemeManager } from '../../common/theme/ThemeManager';
import { WindowManager } from '../../common/utils/WindowManager';
import { ToastService } from '../../common/utils/ToastService';
import { LoadingSpinner } from '../components/LoadingSpinner';
import { ErrorView } from '../components/ErrorView';
import { TopicCard } from '../components/TopicCard';
import { TopicPreviewDialog } from '../components/TopicPreviewDialog';
import { BookmarkEditSheet } from '../components/BookmarkEditSheet';

const TOP_BAR_HEIGHT: number = 56;

@ComponentV2
export struct BookmarksPage {
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

  @Local isBookmarkSheetVisible: boolean = false;
  @Local editingTopic: Topic | null = null;
  @Local isPreviewDeleting: boolean = false;

  private page: number = 0;
  private username: string = '';
  private categoryMap: Map<number, Category> = new Map();
  private isResetLoading: boolean = false;

  aboutToAppear(): void {
    this.loadTopics(true, this.topics.length === 0, false).catch(() => {
    });
  }

  private normalizeErrorMessage(err: Object): string {
    if (err === undefined || err === null) {
      return '加载书签失败';
    }
    const text: string = err.toString().replace('Error: ', '').trim();
    return text.length > 0 ? text : '加载书签失败';
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
      const response = await ApiClient.getInstance().getUserBookmarks(this.username, targetPage, reset);
      if (reset) {
        this.topics = this.mergeBookmarkTopics([], response.topics);
        this.page = 0;
      } else {
        this.topics = this.mergeBookmarkTopics(this.topics, response.topics);
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

  private cleanExcerpt(raw: string | null): string {
    if (raw === null) {
      return '';
    }
    return raw
      .replace(/<[^>]*>/g, '')
      .replace(/&hellip;/g, '...')
      .replace(/&amp;/g, '&')
      .replace(/&lt;/g, '<')
      .replace(/&gt;/g, '>')
      .replace(/&quot;/g, '"')
      .replace(/&#39;/g, '\'')
      .replace(/&nbsp;/g, ' ')
      .replace(/\s+/g, ' ')
      .trim();
  }

  private getBookmarkReminderLabel(topic: Topic): string {
    if (topic.bookmarkReminderAt === null) {
      return '';
    }
    const now: number = Date.now();
    const target: number = (topic.bookmarkReminderAt as Date).getTime();
    if (target <= now) {
      return '提醒已过期';
    }
    return `提醒 ${TimeUtils.formatDetailTime(topic.bookmarkReminderAt)}`;
  }

  private isPostBookmark(topic: Topic): boolean {
    if (topic.bookmarkableType === null) {
      return false;
    }
    return (topic.bookmarkableType as string).trim() === 'Post';
  }

  private getBookmarkTypeLabel(topic: Topic): string {
    return this.isPostBookmark(topic) ? '楼层书签' : '话题书签';
  }

  private getBookmarkPostNumberLabel(topic: Topic): string {
    if (!this.isPostBookmark(topic)) {
      return '';
    }
    if (topic.bookmarkedPostNumber !== null && (topic.bookmarkedPostNumber as number) > 0) {
      return `#${(topic.bookmarkedPostNumber as number).toString()} 楼`;
    }
    return '已书签楼层';
  }

  private getBookmarkTargetLabel(topic: Topic): string {
    if (!this.isPostBookmark(topic)) {
      return '';
    }
    if (topic.bookmarkedPostNumber !== null && (topic.bookmarkedPostNumber as number) > 0) {
      return '打开后将直达该回复';
    }
    return '打开后将直达已书签回复';
  }

  private getBookmarkLabelColor(): string {
    return WindowManager.isDarkMode() ? '#F2C16E' : '#C97700';
  }

  private getBookmarkTypeAccentColor(topic: Topic): string {
    return this.isPostBookmark(topic) ? '#C97700' : '#2B5F94';
  }

  private getBookmarkTypeTextColor(topic: Topic): string {
    if (!WindowManager.isDarkMode()) {
      return this.getBookmarkTypeAccentColor(topic);
    }
    return this.isPostBookmark(topic) ? '#F2C16E' : '#9BD7FF';
  }

  private getBookmarkTypeBackground(topic: Topic): string {
    if (!WindowManager.isDarkMode()) {
      return this.isPostBookmark(topic) ? '#FFF3D6' : '#E8F0FE';
    }
    return ThemeManager.hexWithAlpha(this.getBookmarkTypeAccentColor(topic), 0.22);
  }

  private getBookmarkTypeBorderColor(topic: Topic): string {
    return ThemeManager.hexWithAlpha(this.getBookmarkTypeAccentColor(topic), WindowManager.isDarkMode() ? 0.34 : 0.12);
  }

  private getBookmarkLocationTitleColor(): string {
    return WindowManager.isDarkMode() ? '#F0C57B' : '#8A5A00';
  }

  private getBookmarkLocationBadgeTextColor(): string {
    return WindowManager.isDarkMode() ? '#F2C16E' : '#C97700';
  }

  private getBookmarkLocationBadgeBackground(): string {
    if (!WindowManager.isDarkMode()) {
      return '#FFF3D6';
    }
    return ThemeManager.hexWithAlpha('#C97700', 0.22);
  }

  private getBookmarkLocationBadgeBorderColor(): string {
    return ThemeManager.hexWithAlpha('#C97700', WindowManager.isDarkMode() ? 0.34 : 0.14);
  }

  private getBookmarkLocationPanelBackground(): string {
    if (!WindowManager.isDarkMode()) {
      return '#FFF8EC';
    }
    return ThemeManager.hexWithAlpha('#C97700', 0.12);
  }

  private getBookmarkLocationPanelBorderColor(): string {
    return ThemeManager.hexWithAlpha('#C97700', WindowManager.isDarkMode() ? 0.24 : 0.12);
  }

  private getPreviewEditActionColor(): string {
    return WindowManager.isDarkMode() ? '#9BD7FF' : '#2B5F94';
  }

  private getPreviewDeleteActionColor(): string {
    return WindowManager.isDarkMode() ? '#FF8A80' : '#C83A3A';
  }

  private getPreviewMenuShadowColor(): string {
    return WindowManager.isDarkMode() ? '#00000000' : '#1F000000';
  }

  private getPreviewMenuDisabledColor(): string {
    return WindowManager.isDarkMode() ? '#717A86' : '#99A3B4';
  }

  private mergeBookmarkTopics(preferred: Topic[], extra: Topic[]): Topic[] {
    const merged: Topic[] = [];
    const seen: Map<string, boolean> = new Map();
    for (let i = 0; i < preferred.length; i++) {
      const topic: Topic = preferred[i];
      const identityKey: string = topic.getBookmarkIdentityKey();
      if (seen.has(identityKey)) {
        continue;
      }
      seen.set(identityKey, true);
      merged.push(topic);
    }
    for (let i = 0; i < extra.length; i++) {
      const topic: Topic = extra[i];
      const identityKey: string = topic.getBookmarkIdentityKey();
      if (seen.has(identityKey)) {
        continue;
      }
      seen.set(identityKey, true);
      merged.push(topic);
    }
    return merged;
  }

  private openBookmarkTopic(topic: Topic): void {
    RouterManager.pushTopicDetail(topic.id, topic.getBookmarkTargetPostNumber());
  }

  private openTopicPreview(topic: Topic): void {
    const category: Category | null = this.getCategory(topic);
    this.previewTopic = topic;
    this.previewCategory = category;
    this.previewParentCategory = category !== null ? this.getParentCategory(category as Category) : null;
    this.isPreviewDeleting = false;
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
    this.openBookmarkTopic(topic);
  }

  private openBookmarkEditor(topic: Topic): void {
    if (topic.bookmarkId === null || (topic.bookmarkId as number) <= 0) {
      return;
    }
    this.editingTopic = topic;
    this.isBookmarkSheetVisible = true;
  }

  private openBookmarkEditorFromPreview(topic: Topic): void {
    this.closeTopicPreview();
    this.openBookmarkEditor(topic);
  }

  private async deleteBookmarkFromPreview(topic: Topic): Promise<void> {
    if (this.isPreviewDeleting || topic.bookmarkId === null || (topic.bookmarkId as number) <= 0) {
      return;
    }
    this.isPreviewDeleting = true;
    try {
      await ApiClient.getInstance().deleteBookmark(topic.bookmarkId as number);
      this.removeBookmarkById(topic.bookmarkId as number);
      ToastService.show('已删除书签');
      this.closeTopicPreview();
    } catch (err) {
      const message: string = ApiClient.formatError(err).replace('Error: ', '').trim();
      ToastService.show(message.length > 0 ? message : '删除书签失败');
    } finally {
      this.isPreviewDeleting = false;
    }
  }

  private closeBookmarkEditor(): void {
    this.isBookmarkSheetVisible = false;
  }

  private removeBookmarkById(bookmarkId: number): void {
    const next: Topic[] = [];
    for (let i = 0; i < this.topics.length; i++) {
      const topic: Topic = this.topics[i];
      if (topic.bookmarkId !== bookmarkId) {
        next.push(topic);
      }
    }
    this.topics = next;
  }

  private applyBookmarkUpdate(bookmarkId: number, name: string | null, reminderAt: Date | null, clearReminderAt: boolean): void {
    const next: Topic[] = [];
    for (let i = 0; i < this.topics.length; i++) {
      const topic: Topic = this.topics[i];
      if (topic.bookmarkId === bookmarkId) {
        topic.bookmarkName = name;
        topic.bookmarkReminderAt = clearReminderAt ? null : reminderAt;
      }
      next.push(topic);
    }
    this.topics = next;
  }

  private openSearch(): void {
    RouterManager.pushSearch('', SearchInType.BOOKMARKS.value);
  }

  build() {
    HdsNavDestination() {
      Stack({ alignContent: Alignment.Center }) {
        Column() {
          this.TopBar()

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
              List() {
                if (!this.isLoading && this.topics.length === 0) {
                  ListItem() {
                    Column() {
                      SymbolGlyph($r('sys.symbol.bookmark'))
                        .fontSize(30)
                        .fontColor([$r('app.color.on_surface_tertiary')])
                        .margin({ bottom: 12 })
                      Text('暂无书签')
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
                      this.BookmarkTopicItem(topic)
                    }
                  }, (topic: Topic) => topic.getBookmarkIdentityKey())
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
            this.loadTopics(true, false, true).catch(() => {
            });
          })
          .layoutWeight(1)
        }
        .width('100%')
        .height('100%')
        .backgroundColor($r('app.color.background'))
        .padding({ top: WindowManager.getSystemAvoidAreaTopVp() })

        this.TopicPreviewOverlay()

        Column() {
        }
        .width(0)
        .height(0)
        .bindSheet($$this.isBookmarkSheetVisible, this.BookmarkSheetBuilder, {
          height: SheetSize.MEDIUM,
          dragBar: false,
          showClose: false,
          backgroundColor: $r('app.color.surface'),
          onDisappear: () => {
            this.isBookmarkSheetVisible = false;
            this.editingTopic = null;
          }
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

      Text('我的书签')
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
  private BookmarkTopicItem(topic: Topic) {
    Column() {
      Row() {
        Row() {
          SymbolGlyph($r('sys.symbol.bookmark'))
            .fontSize(12)
            .fontColor([this.getBookmarkLabelColor()])

          Text(topic.bookmarkName !== null && (topic.bookmarkName as string).trim().length > 0
            ? topic.bookmarkName as string
            : '书签')
            .fontSize(12)
            .fontColor(this.getBookmarkLabelColor())
            .margin({ left: 6 })

          Text(this.getBookmarkTypeLabel(topic))
            .fontSize(11)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.getBookmarkTypeTextColor(topic))
            .padding({ left: 8, right: 8, top: 3, bottom: 3 })
            .backgroundColor(this.getBookmarkTypeBackground(topic))
            .border({
              width: WindowManager.isDarkMode() ? 1 : 0,
              color: this.getBookmarkTypeBorderColor(topic)
            })
            .borderRadius(9)
            .margin({ left: 10 })

          if (this.getBookmarkReminderLabel(topic).length > 0) {
            Text(this.getBookmarkReminderLabel(topic))
              .fontSize(12)
              .fontColor($r('app.color.on_surface_secondary'))
              .margin({ left: 10 })
          }
        }
        .layoutWeight(1)
        .alignItems(VerticalAlign.Center)
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 10, bottom: 6 })
      .alignItems(VerticalAlign.Center)

      if (this.getBookmarkTargetLabel(topic).length > 0) {
        Row() {
          Text('定位')
            .fontSize(11)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.getBookmarkLocationTitleColor())
            .margin({ right: 8 })

          Text(this.getBookmarkPostNumberLabel(topic))
            .fontSize(11)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.getBookmarkLocationBadgeTextColor())
            .padding({ left: 8, right: 8, top: 4, bottom: 4 })
            .backgroundColor(this.getBookmarkLocationBadgeBackground())
            .border({
              width: WindowManager.isDarkMode() ? 1 : 0,
              color: this.getBookmarkLocationBadgeBorderColor()
            })
            .borderRadius(10)
            .margin({ right: 8 })

          Text(this.getBookmarkTargetLabel(topic))
            .fontSize(11)
            .fontColor($r('app.color.on_surface_secondary'))
            .layoutWeight(1)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .width('100%')
        .padding({ left: 12, right: 12, top: 2, bottom: 8 })
        .backgroundColor(this.getBookmarkLocationPanelBackground())
        .border({
          width: WindowManager.isDarkMode() ? 1 : 0,
          color: this.getBookmarkLocationPanelBorderColor()
        })
        .borderRadius(12)
        .margin({ left: 12, right: 12, bottom: 6 })
        .alignItems(VerticalAlign.Center)
      }

      TopicCard({
        topic: topic,
        category: this.getCategory(topic),
        opAvatarUrl: this.getOpAvatarUrl(topic),
        onCardClick: (t: Topic) => {
          this.openBookmarkTopic(t);
        },
        onCardLongPress: (t: Topic) => {
          this.openTopicPreview(t);
        }
      })

      if (this.cleanExcerpt(topic.excerpt).length > 0) {
        Text(this.cleanExcerpt(topic.excerpt))
          .fontSize(12)
          .fontColor($r('app.color.on_surface_secondary'))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
          .padding({ left: 12, right: 12, bottom: 12 })
      }
    }
    .width('100%')
    .backgroundColor($r('app.color.card_background'))
    .borderRadius(16)
    .margin({ bottom: 10 })
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

        Column() {
          TopicPreviewDialog({
            topic: this.previewTopic as Topic,
            category: this.previewCategory,
            parentCategory: this.previewParentCategory,
            compactMode: true,
            showParticipants: false,
            secondaryActionLabel: '',
            onClose: () => {
              this.closeTopicPreview();
            },
            onOpen: (topic: Topic) => {
              this.openTopicFromPreview(topic);
            },
            onSecondaryAction: (_topic: Topic) => {
            }
          })

          if ((this.previewTopic as Topic).bookmarkId !== null && ((this.previewTopic as Topic).bookmarkId as number) > 0) {
            Column() {
              this.PreviewMenuItem('编辑书签', this.getPreviewEditActionColor(), false, () => {
                this.openBookmarkEditorFromPreview(this.previewTopic as Topic);
              })
              this.PreviewMenuDivider()
              this.PreviewMenuItem(this.isPreviewDeleting ? '删除中...' : '删除书签', this.getPreviewDeleteActionColor(),
                this.isPreviewDeleting, () => {
                this.deleteBookmarkFromPreview(this.previewTopic as Topic).catch(() => {
                });
              })
            }
            .width('88%')
            .constraintSize({ maxWidth: 520 })
            .margin({ top: 12 })
            .backgroundColor($r('app.color.surface'))
            .borderRadius(20)
            .shadow({ radius: 12, color: this.getPreviewMenuShadowColor(), offsetX: 0, offsetY: 6 })
          }
        }
        .width('100%')
        .alignItems(HorizontalAlign.Center)
      }
      .width('100%')
      .height('100%')
    }
  }

  @Builder
  private PreviewMenuItem(label: string, colorValue: string, disabled: boolean, action: () => void) {
    Row() {
      Text(label)
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor(disabled ? this.getPreviewMenuDisabledColor() : colorValue)
    }
    .width('100%')
    .padding({ left: 22, right: 22, top: 18, bottom: 18 })
    .opacity(disabled ? 0.7 : 1)
    .onClick(() => {
      if (!disabled) {
        action();
      }
    })
  }

  @Builder
  private PreviewMenuDivider() {
    Divider()
      .strokeWidth(1)
      .color($r('app.color.divider_light'))
  }

  @Builder
  private BookmarkSheetBuilder() {
    if (this.editingTopic !== null && (this.editingTopic as Topic).bookmarkId !== null) {
      BookmarkEditSheet({
        bookmarkId: (this.editingTopic as Topic).bookmarkId as number,
        initialName: (this.editingTopic as Topic).bookmarkName !== null ? (this.editingTopic as Topic).bookmarkName as string : '',
        initialReminderAt: (this.editingTopic as Topic).bookmarkReminderAt,
        onDismiss: () => {
          this.closeBookmarkEditor();
        },
        onUpdated: (name: string | null, reminderAt: Date | null, clearReminderAt: boolean) => {
          this.applyBookmarkUpdate(
            (this.editingTopic as Topic).bookmarkId as number,
            name,
            reminderAt,
            clearReminderAt
          );
        },
        onDeleted: () => {
          this.removeBookmarkById((this.editingTopic as Topic).bookmarkId as number);
        }
      })
    }
  }
}
