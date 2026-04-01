import { TopicListPage } from '../views/pages/TopicListPage';
import { TopicDetailPage } from '../views/pages/TopicDetailPage';
import { CategoryTopicPage } from '../views/pages/CategoryTopicPage';
import { ProfilePage } from '../views/pages/ProfilePage';
import { SearchPage } from '../views/pages/SearchPage';
import { UserProfilePage } from '../views/pages/UserProfilePage';
import { FollowListPage } from '../views/pages/FollowListPage';
import { BadgeDetailPage } from '../views/pages/BadgeDetailPage';
import { ImagePreviewPage } from '../views/pages/ImagePreviewPage';
import { WebViewPage } from '../views/pages/WebViewPage';
import { LoginPage } from '../views/pages/LoginPage';
import { CfChallengePage } from '../views/pages/CfChallengePage';
import { NotificationsPage } from '../views/pages/NotificationsPage';
import { BookmarksPage } from '../views/pages/BookmarksPage';
import { DraftsPage } from '../views/pages/DraftsPage';
import { MyTopicsPage } from '../views/pages/MyTopicsPage';
import { MyBadgesPage } from '../views/pages/MyBadgesPage';
import { BrowsingHistoryPage } from '../views/pages/BrowsingHistoryPage';
import { TrustLevelPage } from '../views/pages/TrustLevelPage';
import { InviteLinksPage } from '../views/pages/InviteLinksPage';
import { AboutAppPage } from '../views/pages/AboutAppPage';
import { OpenSourceInfoPage } from '../views/pages/OpenSourceInfoPage';
import { AppLogsPage } from '../views/pages/AppLogsPage';
import { FeatureSettingsPage } from '../views/pages/FeatureSettingsPage';
import { CfRefreshHost } from '../views/components/CfRefreshHost';
import { ReadLaterBubble } from '../views/components/ReadLaterBubble';
import { Topic } from '../models/Topic';
import { Category } from '../models/Category';
import { User } from '../models/User';
import { TopicTrackingService } from '../services/messagebus/TopicTrackingService';
import { PreloadedDataService } from '../services/messagebus/PreloadedDataService';
import { NotificationTrackingService } from '../services/messagebus/NotificationTrackingService';
import { AuthService } from '../services/auth/AuthService';
import {
  RouterManager,
  RouteConstants,
  TopicDetailRouteParam,
  SearchRouteParam,
  BadgeDetailRouteParam,
  ImagePreviewRouteParam,
  FollowListRouteParam,
  WebViewRouteParam
} from '../common/utils/RouterManager';
import { HdsNavigation, HdsTabs } from '@kit.UIDesignKit';
import { WindowManager } from '../common/utils/WindowManager';
import {
  FLOATING_TAB_BAR_HEIGHT_VP,
  FLOATING_TAB_BAR_RADIUS_VP,
  FLOATING_TAB_BAR_MARGIN_H_VP,
  FLOATING_TAB_BAR_MARGIN_BOTTOM_VP
} from '../common/constants/LayoutConstants';
import { SmartAvatar } from '../views/components/SmartAvatar';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppLogService } from '../common/utils/AppLogService';

const TAG: string = 'Index';
const FLOATING_TAB_BAR_ANIM_DURATION: number = 180;
const FLOATING_TAB_SWITCH_ANIM_DURATION: number = 260;
const FLOATING_TAB_ITEM_ANIM_DURATION: number = 220;
const FLOATING_TAB_INDICATOR_WIDTH_VP: number = 66;
const FLOATING_TAB_INDICATOR_HEIGHT_VP: number = 46;
const FLOATING_TAB_ICON_BOX_HEIGHT_VP: number = 28;

/**
 * 应用主页面 -
 *
 * 底部导航只有 2 个 Tab：
 * - 首页（🏠）
 * - 我的（👤）
 *
 * 使用 Navigation + NavPathStack 管理路由
 */
@Entry
@ComponentV2
struct Index {
  @Local currentIndex: number = 0;
  @Local tabBarVisibility: number = 1;
  @Local pathStack: NavPathStack = new NavPathStack();
  @Local currentTabUser: User | null = null;
  @Local currentTabUsername: string = '';
  @Local floatingTabBarContentWidth: number = 0;

  private authStateListener: (() => void) | null = null;
  private backgroundSessionSyncId: number = 0;
  private backgroundSessionBootstrapped: boolean = false;
  private lastBackgroundLoggedIn: boolean | null = null;

  aboutToAppear(): void {
    RouterManager.init(this.pathStack);
    this.attachAuthStateListener();
    this.syncProfileTabUser().catch(() => {
    });
    this.syncBackgroundSessionSafely();
  }

  aboutToDisappear(): void {
    this.detachAuthStateListener();
  }

  private getEffectiveTabBarVisibility(): number {
    return this.currentIndex === 0 ? this.tabBarVisibility : 1;
  }

  private getBottomSafeHeight(): number {
    return WindowManager.getSystemAvoidAreaBottomVp();
  }

  private getFloatingTabBarHideTranslate(): number {
    return FLOATING_TAB_BAR_HEIGHT_VP + this.getBottomSafeHeight() + FLOATING_TAB_BAR_MARGIN_BOTTOM_VP + 24;
  }

  private updateFloatingTabBarContentWidth(widthValue: number | string | Resource): void {
    const rawWidth: number = (widthValue !== undefined && widthValue !== null && typeof widthValue === 'number')
      ? (widthValue as number)
      : 0;
    if (rawWidth <= 0) {
      return;
    }

    let resolvedWidthVp: number = rawWidth;
    const uiContext = this.getUIContext();
    if (uiContext !== undefined && uiContext !== null) {
      try {
        const convertedVp: number = uiContext.px2vp(rawWidth);
        if (convertedVp > 0) {
          resolvedWidthVp = convertedVp;

          // onAreaChange 在这里更像是直接给了 vp；若再 px2vp 一次会让位移明显偏小。
          if (convertedVp < 140 && rawWidth > 220) {
            resolvedWidthVp = rawWidth;
          }
        }
      } catch (_) {
      }
    }

    if (Math.abs(resolvedWidthVp - this.floatingTabBarContentWidth) <= 0.5) {
      return;
    }
    this.floatingTabBarContentWidth = resolvedWidthVp;
  }

  private getFloatingTabIndicatorOffsetX(): number {
    if (this.floatingTabBarContentWidth <= 0) {
      return 0;
    }
    return this.floatingTabBarContentWidth / 4;
  }

  private getFloatingTabIndicatorTranslateX(): number {
    const offsetX: number = this.getFloatingTabIndicatorOffsetX();
    return this.currentIndex === 0 ? -offsetX : offsetX;
  }

  private isFloatingTabSelected(index: number): boolean {
    return this.currentIndex === index;
  }

  private switchMainTab(index: number): void {
    if (this.currentIndex === index) {
      return;
    }
    const uiContext = this.getUIContext();
    if (uiContext !== undefined && uiContext !== null) {
      uiContext.animateTo({ duration: FLOATING_TAB_SWITCH_ANIM_DURATION, curve: Curve.EaseInOut }, () => {
        this.currentIndex = index;
      });
    } else {
      this.currentIndex = index;
    }
  }

  private updateTabBarVisibility(next: number): void {
    const v: number = Math.max(0, Math.min(1, next));
    if (Math.abs(v - this.tabBarVisibility) <= 0.001) {
      return;
    }
    const uiContext = this.getUIContext();
    if (uiContext !== undefined && uiContext !== null) {
      uiContext.animateTo({ duration: FLOATING_TAB_BAR_ANIM_DURATION, curve: Curve.EaseOut }, () => {
        this.tabBarVisibility = v;
      });
    } else {
      this.tabBarVisibility = v;
    }
  }

  private attachAuthStateListener(): void {
    if (this.authStateListener !== null) {
      return;
    }
    this.authStateListener = () => {
      this.syncProfileTabUser().catch(() => {
      });
      this.syncBackgroundSessionSafely();
    };
    AuthService.getInstance().addListener(this.authStateListener);
  }

  private detachAuthStateListener(): void {
    if (this.authStateListener === null) {
      return;
    }
    AuthService.getInstance().removeListener(this.authStateListener);
    this.authStateListener = null;
  }

  private async syncProfileTabUser(): Promise<void> {
    const auth: AuthService = AuthService.getInstance();
    await auth.init();
    this.currentTabUser = auth.getCurrentUser();
    this.currentTabUsername = auth.getCurrentUsername().trim();
  }

  private syncBackgroundSessionSafely(): void {
    this.syncBackgroundSession().catch((err: Object) => {
      this.backgroundSessionBootstrapped = false;
      this.lastBackgroundLoggedIn = null;
      hilog.warn(0x0000, TAG, 'Sync background session failed: %{public}s', JSON.stringify(err));
      AppLogService.getInstance().error('general', 'sync background session failed', TAG, JSON.stringify(err));
    });
  }

  private async syncBackgroundSession(): Promise<void> {
    const requestId: number = this.backgroundSessionSyncId + 1;
    this.backgroundSessionSyncId = requestId;

    const auth: AuthService = AuthService.getInstance();
    await auth.init();
    if (requestId !== this.backgroundSessionSyncId) {
      return;
    }

    const loggedIn: boolean = auth.getIsLoggedIn();
    if (this.backgroundSessionBootstrapped && this.lastBackgroundLoggedIn === loggedIn) {
      return;
    }

    const tracking: TopicTrackingService = TopicTrackingService.getInstance();
    const notificationTracking: NotificationTrackingService = NotificationTrackingService.getInstance();
    const preloaded: PreloadedDataService = PreloadedDataService.getInstance();

    tracking.stop();
    notificationTracking.stop();
    await preloaded.clearSessionScopedState();
    if (requestId !== this.backgroundSessionSyncId) {
      return;
    }

    hilog.info(
      0x0000,
      TAG,
      'Apply background session mode loggedIn=%{public}s',
      loggedIn ? 'Y' : 'N'
    );
    await tracking.start(loggedIn);
    if (requestId !== this.backgroundSessionSyncId) {
      return;
    }
    if (loggedIn) {
      await notificationTracking.start();
      if (requestId !== this.backgroundSessionSyncId) {
        notificationTracking.stop();
        return;
      }
    } else {
      notificationTracking.stop();
      notificationTracking.resetState();
    }
    this.backgroundSessionBootstrapped = true;
    this.lastBackgroundLoggedIn = loggedIn;
  }

  private shouldShowProfileTabAvatar(): boolean {
    return this.currentTabUser !== null || this.currentTabUsername.length > 0;
  }

  private getProfileTabAvatarUrl(): string {
    if (this.currentTabUser === null) {
      return '';
    }
    return (this.currentTabUser as User).getAvatarUrl(64);
  }

  private getProfileTabFallbackText(): string {
    if (this.currentTabUsername.length > 0) {
      return this.currentTabUsername;
    }
    return '我';
  }

  private getStringParam(param: Object): string {
    return typeof param === 'string' ? param as string : '';
  }

  private parseTopicDetailParam(param: Object): TopicDetailRouteParam {
    if (typeof param === 'number') {
      return new TopicDetailRouteParam(param as number, 0);
    }
    const obj: TopicDetailRouteParam = param as TopicDetailRouteParam;
    const topicId: number = obj.topicId !== undefined && obj.topicId !== null ? obj.topicId as number : 0;
    const initialPostNumber: number = obj.initialPostNumber !== undefined && obj.initialPostNumber !== null
      ? obj.initialPostNumber as number : 0;
    return new TopicDetailRouteParam(topicId, initialPostNumber);
  }

  private parseSearchParam(param: Object): SearchRouteParam {
    if (param === null || param === undefined) {
      return new SearchRouteParam('', '');
    }
    if (typeof param === 'string') {
      return new SearchRouteParam(param as string, '');
    }
    const obj: SearchRouteParam = param as SearchRouteParam;
    const initialQuery: string = obj.initialQuery !== undefined && obj.initialQuery !== null
      ? obj.initialQuery as string
      : '';
    const initialInTypeValue: string = obj.initialInTypeValue !== undefined && obj.initialInTypeValue !== null
      ? obj.initialInTypeValue as string
      : '';
    return new SearchRouteParam(initialQuery, initialInTypeValue);
  }

  private parseBadgeDetailParam(param: Object): BadgeDetailRouteParam {
    if (param === null || param === undefined) {
      return new BadgeDetailRouteParam(0, '', '');
    }
    const obj: BadgeDetailRouteParam = param as BadgeDetailRouteParam;
    const badgeId: number = obj.badgeId !== undefined && obj.badgeId !== null ? obj.badgeId as number : 0;
    const badgeSlug: string = obj.badgeSlug !== undefined && obj.badgeSlug !== null ? obj.badgeSlug as string : '';
    const username: string = obj.username !== undefined && obj.username !== null ? obj.username as string : '';
    return new BadgeDetailRouteParam(badgeId, badgeSlug, username);
  }

  private parseImagePreviewParam(param: Object): ImagePreviewRouteParam {
    const obj: ImagePreviewRouteParam = param as ImagePreviewRouteParam;
    const urls: string[] = obj.urls !== undefined && obj.urls !== null ? obj.urls as string[] : [];
    const initialIndex: number = obj.initialIndex !== undefined && obj.initialIndex !== null ? obj.initialIndex as number : 0;
    return new ImagePreviewRouteParam(urls, initialIndex);
  }

  private parseFollowListParam(param: Object): FollowListRouteParam {
    const obj: FollowListRouteParam = param as FollowListRouteParam;
    const username: string = obj.username !== undefined && obj.username !== null ? obj.username as string : '';
    const isFollowing: boolean = obj.isFollowing !== undefined && obj.isFollowing !== null
      ? obj.isFollowing as boolean : true;
    return new FollowListRouteParam(username, isFollowing);
  }

  private parseWebViewParam(param: Object): WebViewRouteParam {
    const obj: WebViewRouteParam = param as WebViewRouteParam;
    const url: string = obj.url !== undefined && obj.url !== null ? obj.url as string : '';
    const title: string = obj.title !== undefined && obj.title !== null ? obj.title as string : '';
    return new WebViewRouteParam(url, title);
  }

  @Builder
  routeMap(name: string, param: Object) {
    if (name === RouteConstants.PAGE_TOPIC_DETAIL) {
      TopicDetailPage({
        topicId: this.parseTopicDetailParam(param).topicId,
        initialPostNumber: this.parseTopicDetailParam(param).initialPostNumber
      })
    } else if (name === RouteConstants.PAGE_CATEGORY_TOPIC_LIST) {
      CategoryTopicPage({ category: param as Category })
    } else if (name === RouteConstants.PAGE_SEARCH) {
      SearchPage({
        initialQuery: this.parseSearchParam(param).initialQuery,
        initialInTypeValue: this.parseSearchParam(param).initialInTypeValue
      })
    } else if (name === RouteConstants.PAGE_NOTIFICATIONS) {
      NotificationsPage()
    } else if (name === RouteConstants.PAGE_BOOKMARKS) {
      BookmarksPage()
    } else if (name === RouteConstants.PAGE_DRAFTS) {
      DraftsPage()
    } else if (name === RouteConstants.PAGE_MY_TOPICS) {
      MyTopicsPage()
    } else if (name === RouteConstants.PAGE_MY_BADGES) {
      MyBadgesPage()
    } else if (name === RouteConstants.PAGE_BROWSING_HISTORY) {
      BrowsingHistoryPage()
    } else if (name === RouteConstants.PAGE_BADGE_DETAIL) {
      BadgeDetailPage({
        badgeId: this.parseBadgeDetailParam(param).badgeId,
        badgeSlug: this.parseBadgeDetailParam(param).badgeSlug,
        username: this.parseBadgeDetailParam(param).username
      })
    } else if (name === RouteConstants.PAGE_USER_PROFILE) {
      UserProfilePage({ username: this.getStringParam(param) })
    } else if (name === RouteConstants.PAGE_FOLLOW_LIST) {
      FollowListPage({
        username: this.parseFollowListParam(param).username,
        isFollowing: this.parseFollowListParam(param).isFollowing
      })
    } else if (name === RouteConstants.PAGE_IMAGE_PREVIEW) {
      ImagePreviewPage({
        urls: this.parseImagePreviewParam(param).urls,
        initialIndex: this.parseImagePreviewParam(param).initialIndex
      })
    } else if (name === RouteConstants.PAGE_WEB_VIEW) {
      WebViewPage({
        url: this.parseWebViewParam(param).url,
        title: this.parseWebViewParam(param).title
      })
    } else if (name === RouteConstants.PAGE_LOGIN) {
      LoginPage()
    } else if (name === RouteConstants.PAGE_CF_CHALLENGE) {
      CfChallengePage()
    } else if (name === RouteConstants.PAGE_TRUST_LEVEL) {
      TrustLevelPage()
    } else if (name === RouteConstants.PAGE_INVITE_LINKS) {
      InviteLinksPage()
    } else if (name === RouteConstants.PAGE_ABOUT_APP) {
      AboutAppPage()
    } else if (name === RouteConstants.PAGE_OPEN_SOURCE_INFO) {
      OpenSourceInfoPage()
    } else if (name === RouteConstants.PAGE_APP_LOGS) {
      AppLogsPage()
    } else if (name === RouteConstants.PAGE_FEATURE_SETTINGS) {
      FeatureSettingsPage()
    }
  }

  build() {
    HdsNavigation(this.pathStack) {
      Stack({ alignContent: Alignment.Bottom }) {
        // Cloudflare: cf_clearance 自动续期宿主（隐藏 Web）
        CfRefreshHost()

        HdsTabs({ barPosition: BarPosition.End, index: this.currentIndex }) {
          // Tab 1: 首页
          TabContent() {
            TopicListPage({
              onTopicClick: (topic: Topic) => {
                this.pathStack.pushPath({ name: RouteConstants.PAGE_TOPIC_DETAIL, param: topic.id });
              },
              onBarVisibilityChange: (v: number) => {
                this.updateTabBarVisibility(v);
              }
            })
          }
          .tabBar(this.TabBarItem(0, '首页', $r('sys.symbol.house'), $r('sys.symbol.house_fill')))

          // Tab 2: 我的
          TabContent() {
            ProfilePage()
          }
          .tabBar(this.TabBarItem(1, '我的', $r('sys.symbol.person'), $r('sys.symbol.person_fill')))
        }
        // 使用自定义“悬浮胶囊”TabBar：隐藏 HdsTabs 默认 TabBar（只保留内容切换能力）
        .barHeight(0)
        .onChange((index: number) => {
          this.currentIndex = index;
        })
        .scrollable(false)

        this.FloatingTabBar()
        ReadLaterBubble()
      }
      .width('100%')
      .height('100%')
    }
    .navDestination(this.routeMap)
    .hideTitleBar(true)
    .hideToolBar(true)
    .width('100%')
    .height('100%')
  }

  @Builder
  TabBarItem(index: number, label: string, icon: Resource, selectedIcon: Resource) {
    Column() {
      // 选中时显示背景胶囊
      if (this.currentIndex === index) {
        Column() {
          if (index === 1 && this.shouldShowProfileTabAvatar()) {
            SmartAvatar({
              avatarUrl: this.getProfileTabAvatarUrl(),
              avatarSize: 24,
              avatarRadius: 12,
              fallbackText: this.getProfileTabFallbackText(),
              bgColor: '#E8EAF0'
            })
          } else {
            SymbolGlyph(selectedIcon)
              .fontSize(22)
              .fontColor([$r('app.color.primary')])
          }
        }
        .width(56)
        .height(30)
        .borderRadius(15)
        .backgroundColor($r('app.color.tab_selected_pill'))
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      } else {
        if (index === 1 && this.shouldShowProfileTabAvatar()) {
          SmartAvatar({
            avatarUrl: this.getProfileTabAvatarUrl(),
            avatarSize: 24,
            avatarRadius: 12,
            fallbackText: this.getProfileTabFallbackText(),
            bgColor: '#E8EAF0'
          })
        } else {
          SymbolGlyph(icon)
            .fontSize(22)
            .fontColor([$r('app.color.on_surface_secondary')])
        }
      }
      Text(label)
        .fontSize(11)
        .fontColor(this.currentIndex === index ? $r('app.color.primary') : $r('app.color.on_surface_secondary'))
        .margin({ top: 2 })
    }
    .width('100%')
    .height(56 + this.getBottomSafeHeight())
    .padding({ bottom: this.getBottomSafeHeight() })
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .opacity(this.getEffectiveTabBarVisibility())
  }

  @Builder
  FloatingTabBar() {
    Row() {
      Stack({ alignContent: Alignment.Center }) {
        Stack()
          .width('100%')
          .height('100%')
          .backgroundEffect(
            {
              radius: 64,
              saturation: 2.2,
              brightness: 1.08,
              color: $r('app.color.tab_glass_tint'),
              adaptiveColor: AdaptiveColor.DEFAULT,
              policy: BlurStyleActivePolicy.ALWAYS_ACTIVE,
              inactiveColor: $r('app.color.tab_glass_tint')
            },
            { disableSystemAdaptation: true }
          )

        Stack()
          .width(FLOATING_TAB_INDICATOR_WIDTH_VP)
          .height(FLOATING_TAB_INDICATOR_HEIGHT_VP)
          .borderRadius(FLOATING_TAB_INDICATOR_HEIGHT_VP / 2)
          .backgroundColor($r('app.color.tab_selected_pill'))
          .border({ width: 0.5, color: $r('app.color.tab_glass_stroke') })
          .shadow({ radius: 10, color: '#14000000', offsetX: 0, offsetY: 4 })
          .opacity(this.floatingTabBarContentWidth > 0 ? 1 : 0)
          .translate({ x: this.getFloatingTabIndicatorTranslateX(), y: 0 })
          .animation({ duration: FLOATING_TAB_SWITCH_ANIM_DURATION, curve: Curve.EaseInOut })

        Row() {
          this.FloatingTabItem(0, '首页', $r('sys.symbol.house'), $r('sys.symbol.house_fill'))
          this.FloatingTabItem(1, '我的', $r('sys.symbol.person'), $r('sys.symbol.person_fill'))
        }
        .width('100%')
        .height('100%')
      }
      .width('100%')
      .height(FLOATING_TAB_BAR_HEIGHT_VP)
      .onAreaChange((_: Area, newArea: Area) => {
        this.updateFloatingTabBarContentWidth(newArea.width);
      })
      .border({ width: 0.5, color: $r('app.color.tab_glass_stroke') })
      .borderRadius(FLOATING_TAB_BAR_RADIUS_VP)
      .clip(true)
      .shadow({ radius: 18, color: $r('app.color.tab_glass_shadow'), offsetX: 0, offsetY: 10 })
    }
    .width('100%')
    .padding({ left: FLOATING_TAB_BAR_MARGIN_H_VP, right: FLOATING_TAB_BAR_MARGIN_H_VP })
    .margin({ bottom: this.getBottomSafeHeight() + FLOATING_TAB_BAR_MARGIN_BOTTOM_VP })
    .opacity(this.getEffectiveTabBarVisibility())
    .translate({ x: 0, y: (1 - this.getEffectiveTabBarVisibility()) * this.getFloatingTabBarHideTranslate() })
    .enabled(this.getEffectiveTabBarVisibility() > 0.05)
    .animation({ duration: FLOATING_TAB_BAR_ANIM_DURATION, curve: Curve.EaseOut })
  }

  @Builder
  FloatingTabItem(index: number, label: string, icon: Resource, selectedIcon: Resource) {
    Column() {
      Column() {
        if (index === 1 && this.shouldShowProfileTabAvatar()) {
          SmartAvatar({
            avatarUrl: this.getProfileTabAvatarUrl(),
            avatarSize: 24,
            avatarRadius: 12,
            fallbackText: this.getProfileTabFallbackText(),
            bgColor: '#E8EAF0'
          })
            .scale({ x: this.isFloatingTabSelected(index) ? 1 : 0.92, y: this.isFloatingTabSelected(index) ? 1 : 0.92 })
            .opacity(this.isFloatingTabSelected(index) ? 1 : 0.86)
            .animation({ duration: FLOATING_TAB_ITEM_ANIM_DURATION, curve: Curve.EaseOut })
        } else {
          SymbolGlyph(this.isFloatingTabSelected(index) ? selectedIcon : icon)
            .fontSize(22)
            .fontColor([this.isFloatingTabSelected(index) ? $r('app.color.primary') : $r('app.color.on_surface_secondary')])
            .scale({ x: this.isFloatingTabSelected(index) ? 1 : 0.88, y: this.isFloatingTabSelected(index) ? 1 : 0.88 })
            .opacity(this.isFloatingTabSelected(index) ? 1 : 0.74)
            .animation({ duration: FLOATING_TAB_ITEM_ANIM_DURATION, curve: Curve.EaseOut })
        }
      }
      .width(FLOATING_TAB_INDICATOR_WIDTH_VP)
      .height(FLOATING_TAB_ICON_BOX_HEIGHT_VP)
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .translate({ x: 0, y: this.isFloatingTabSelected(index) ? 0 : 1 })
      .animation({ duration: FLOATING_TAB_ITEM_ANIM_DURATION, curve: Curve.EaseOut })

      Text(label)
        .fontSize(11)
        .lineHeight(12)
        .fontWeight(this.isFloatingTabSelected(index) ? FontWeight.Medium : FontWeight.Regular)
        .fontColor(this.isFloatingTabSelected(index) ? $r('app.color.primary') : $r('app.color.on_surface_secondary'))
        .opacity(this.isFloatingTabSelected(index) ? 1 : 0.8)
        .translate({ x: 0, y: this.isFloatingTabSelected(index) ? 0 : 1 })
        .margin({ top: 1 })
        .animation({ duration: FLOATING_TAB_ITEM_ANIM_DURATION, curve: Curve.EaseOut })
    }
    .layoutWeight(1)
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .onClick(() => {
      this.switchMainTab(index);
    })
  }
}
