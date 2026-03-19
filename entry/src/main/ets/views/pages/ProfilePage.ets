import { webview } from '@kit.ArkWeb';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppConstants } from '../../common/constants/AppConstants';
import { ThemeManager } from '../../common/theme/ThemeManager';
import { WindowManager } from '../../common/utils/WindowManager';
import { RouterManager } from '../../common/utils/RouterManager';
import { ToastService } from '../../common/utils/ToastService';
import { UserSummarySnapshotService } from '../../services/storage/UserSummarySnapshotService';
import { AppSettingsService } from '../../services/storage/AppSettingsService';
import { AuthService } from '../../services/auth/AuthService';
import { ApiClient } from '../../services/network/ApiClient';
import { CookieStore } from '../../services/network/CookieStore';
import { User, UserSummary, UserStatus } from '../../models/User';
import { AvatarWithFlair } from '../components/AvatarWithFlair';
import { UserStatusEmoji } from '../components/UserStatusEmoji';
import { LoadingSpinner } from '../components/LoadingSpinner';
import { ErrorView } from '../components/ErrorView';
import { NotificationQuickPanel } from '../components/NotificationQuickPanel';
import {
  FLOATING_TAB_BAR_HEIGHT_VP,
  FLOATING_TAB_BAR_MARGIN_BOTTOM_VP,
  FLOATING_TAB_BAR_CONTENT_EXTRA_PADDING_VP
} from '../../common/constants/LayoutConstants';

const TAG: string = 'ProfilePage';
const HEADER_AVATAR_SIZE: number = 72;

interface ProfileOptionItem {
  iconSymbol: Resource;
  iconBgColor: string;
  iconColor: string;
  title: string;
  showDivider: boolean;
  onClick: () => void;
}

@ComponentV2
export struct ProfilePage {
  @Local isLoading: boolean = true;
  @Local isRefreshing: boolean = false;
  @Local isSummaryLoading: boolean = false;
  @Local isNotificationQuickPanelVisible: boolean = false;
  @Local errorMessage: string = '';
  @Local isLoggedIn: boolean = false;
  @Local showTitle: boolean = false;
  @Local scrollOffset: number = 0;
  @Local currentUser: User | null = null;
  @Local summary: UserSummary | null = null;
  @Local isLoggingOut: boolean = false;

  private scroller: Scroller = new Scroller();
  private hasBootstrapped: boolean = false;
  private loadRequestId: number = 0;
  private authStateListener: (() => void) | null = null;

  aboutToAppear(): void {
    this.attachAuthStateListener();
    const showLoading: boolean = !this.hasBootstrapped;
    this.hasBootstrapped = true;
    this.refreshPage(showLoading).catch((err: Object) => {
      hilog.error(0x0000, TAG, 'Refresh page failed: %{public}s', JSON.stringify(err));
    });
  }

  aboutToDisappear(): void {
    this.detachAuthStateListener();
  }

  private getFloatingTabBarReservedBottomVp(): number {
    return WindowManager.getSystemAvoidAreaBottomVp()
      + FLOATING_TAB_BAR_HEIGHT_VP
      + FLOATING_TAB_BAR_MARGIN_BOTTOM_VP
      + FLOATING_TAB_BAR_CONTENT_EXTRA_PADDING_VP;
  }

  private attachAuthStateListener(): void {
    if (this.authStateListener !== null) {
      return;
    }
    this.authStateListener = () => {
      this.handleAuthStateChanged().catch((err: Object) => {
        hilog.error(0x0000, TAG, 'Handle auth state change failed: %{public}s', JSON.stringify(err));
      });
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

  private buildFallbackCurrentUser(username: string): User {
    const user: User = new User();
    user.username = username;
    user.name = username;
    return user;
  }

  private needsProfileDetails(user: User): boolean {
    return user.avatarTemplate === null
      || (user.avatarTemplate as string).trim().length === 0
      || (user.name === null || (user.name as string).trim().length === 0)
      || user.status === null
      || user.flairUrl === null;
  }

  private mergeSessionAndProfileUser(sessionUser: User, profileUser: User): User {
    profileUser.unreadNotifications = sessionUser.unreadNotifications;
    profileUser.unreadHighPriorityNotifications = sessionUser.unreadHighPriorityNotifications;
    profileUser.allUnreadNotificationsCount = sessionUser.allUnreadNotificationsCount;
    profileUser.seenNotificationId = sessionUser.seenNotificationId;
    profileUser.notificationChannelPosition = sessionUser.notificationChannelPosition;

    if ((profileUser.name === null || (profileUser.name as string).trim().length === 0)
      && sessionUser.name !== null && (sessionUser.name as string).trim().length > 0) {
      profileUser.name = sessionUser.name;
    }
    if ((profileUser.avatarTemplate === null || (profileUser.avatarTemplate as string).trim().length === 0)
      && sessionUser.avatarTemplate !== null && (sessionUser.avatarTemplate as string).trim().length > 0) {
      profileUser.avatarTemplate = sessionUser.avatarTemplate;
    }
    if ((profileUser.animatedAvatar === null || (profileUser.animatedAvatar as string).trim().length === 0)
      && sessionUser.animatedAvatar !== null && (sessionUser.animatedAvatar as string).trim().length > 0) {
      profileUser.animatedAvatar = sessionUser.animatedAvatar;
    }
    if (profileUser.status === null && sessionUser.status !== null) {
      profileUser.status = sessionUser.status;
    }
    if (profileUser.flairUrl === null && sessionUser.flairUrl !== null) {
      profileUser.flairUrl = sessionUser.flairUrl;
      profileUser.flairName = sessionUser.flairName;
      profileUser.flairBgColor = sessionUser.flairBgColor;
      profileUser.flairColor = sessionUser.flairColor;
      profileUser.flairGroupId = sessionUser.flairGroupId;
    }
    return profileUser;
  }

  private shouldNotifyHydratedUser(previousUser: User | null, nextUser: User): boolean {
    if (previousUser === null) {
      return true;
    }
    const previousName: string = previousUser.name !== null ? (previousUser.name as string).trim() : '';
    const nextName: string = nextUser.name !== null ? (nextUser.name as string).trim() : '';
    const previousAvatar: string = previousUser.avatarTemplate !== null ? (previousUser.avatarTemplate as string).trim() : '';
    const nextAvatar: string = nextUser.avatarTemplate !== null ? (nextUser.avatarTemplate as string).trim() : '';
    if (previousAvatar.length === 0 && nextAvatar.length > 0) {
      return true;
    }
    if (previousName.length === 0 && nextName.length > 0) {
      return true;
    }
    if (previousUser.trustLevel !== nextUser.trustLevel) {
      return true;
    }
    if (previousUser.status === null && nextUser.status !== null) {
      return true;
    }
    if (previousUser.flairUrl === null && nextUser.flairUrl !== null) {
      return true;
    }
    return false;
  }

  private async hydrateVisibleUserByUsername(
    api: ApiClient,
    auth: AuthService,
    username: string,
    requestId: number
  ): Promise<void> {
    const normalizedUsername: string = username.trim();
    if (normalizedUsername.length === 0) {
      return;
    }

    let resolvedUser: User | null = this.currentUser;
    const currentVisibleUser: User | null = this.currentUser;
    const shouldFetchProfile: boolean = resolvedUser === null
      || this.needsProfileDetails(resolvedUser as User)
      || (resolvedUser as User).trustLevel <= 0;

    if (shouldFetchProfile) {
      try {
        const profileUser: User = await api.getUserProfile(normalizedUsername);
        if (requestId !== this.loadRequestId) {
          return;
        }
        resolvedUser = resolvedUser !== null
          ? this.mergeSessionAndProfileUser(resolvedUser as User, profileUser)
          : profileUser;
        this.currentUser = resolvedUser;
        auth.setCurrentUser(resolvedUser, this.shouldNotifyHydratedUser(currentVisibleUser, resolvedUser));
        api.setCachedCurrentUser(resolvedUser);
      } catch (profileErr) {
        hilog.warn(0x0000, TAG, 'Hydrate visible user by username failed: %{public}s', ApiClient.formatError(profileErr));
      }
    }

    const summaryUsername: string = resolvedUser !== null ? resolvedUser.username.trim() : normalizedUsername;
    const shouldFetchSummary: boolean = summaryUsername.length > 0 && (this.summary === null || this.isRefreshing);
    if (!shouldFetchSummary) {
      return;
    }

    this.isSummaryLoading = true;
    try {
      const summary: UserSummary = await api.getUserSummary(summaryUsername);
      if (requestId !== this.loadRequestId) {
        return;
      }
      this.summary = summary;
      this.isSummaryLoading = false;
      this.persistSummarySnapshot(summaryUsername, summary).catch((persistErr: Object) => {
        hilog.warn(0x0000, TAG, 'Persist hydrated profile summary snapshot failed: %{public}s', JSON.stringify(persistErr));
      });
    } catch (summaryErr) {
      hilog.warn(0x0000, TAG, 'Hydrate profile summary by username failed: %{public}s', ApiClient.formatError(summaryErr));
      if (requestId === this.loadRequestId) {
        this.isSummaryLoading = false;
      }
    }
  }

  private isRateLimitError(err: Object): boolean {
    if (err === undefined || err === null) {
      return false;
    }
    return err.toString().indexOf('HTTP 429') >= 0;
  }

  private async loadSummarySnapshot(username: string): Promise<UserSummary | null> {
    return await UserSummarySnapshotService.load(username);
  }

  private async persistSummarySnapshot(username: string, summary: UserSummary): Promise<void> {
    await UserSummarySnapshotService.save(username, summary);
  }

  private async handleAuthStateChanged(): Promise<void> {
    this.loadRequestId += 1;
    const auth: AuthService = AuthService.getInstance();
    if (!auth.getIsLoggedIn()) {
      this.applyLoggedOutState();
      return;
    }

    const cachedUser: User | null = auth.getCurrentUser();
    if (cachedUser !== null) {
      this.currentUser = cachedUser;
    } else {
      const username: string = auth.getCurrentUsername().trim();
      if (username.length > 0) {
        this.currentUser = this.buildFallbackCurrentUser(username);
      }
    }
    this.isLoggedIn = true;
    this.errorMessage = '';
    await this.refreshPage(false, false);
  }

  private async pullToRefresh(): Promise<void> {
    this.errorMessage = '';
    if (this.isLoggedIn) {
      this.isSummaryLoading = true;
    }
    ApiClient.getInstance().invalidateCurrentUserCache();
    await this.refreshPage(false, false);
  }

  private async refreshPage(showLoading: boolean = true, clearAuthWhenServerUserMissing: boolean = true): Promise<void> {
    const requestId: number = ++this.loadRequestId;
    if (showLoading) {
      this.isLoading = true;
      this.errorMessage = '';
    } else if (this.isLoggedIn) {
      this.isRefreshing = true;
    }

    try {
      const auth: AuthService = AuthService.getInstance();
      await auth.init();
      if (requestId !== this.loadRequestId) {
        return;
      }

      if (!auth.getIsLoggedIn()) {
        this.applyLoggedOutState();
        return;
      }

      const cachedUser: User | null = auth.getCurrentUser();
      if (cachedUser !== null) {
        this.currentUser = cachedUser;
        this.isLoggedIn = true;
      } else {
        const fallbackUsername: string = auth.getCurrentUsername().trim();
        if (fallbackUsername.length > 0) {
          this.currentUser = this.buildFallbackCurrentUser(fallbackUsername);
          this.isLoggedIn = true;
        }
      }

      const snapshotUsername: string = this.currentUser !== null ? (this.currentUser as User).username.trim() : '';
      if (snapshotUsername.length > 0 && this.summary === null) {
        const startupSummary: UserSummary | null = await this.loadSummarySnapshot(snapshotUsername);
        if (requestId !== this.loadRequestId) {
          return;
        }
        if (startupSummary !== null) {
          this.summary = startupSummary;
          this.isSummaryLoading = false;
        }
      }

      const api: ApiClient = ApiClient.getInstance();
      const currentUser: User | null = await api.getCurrentUser();
      if (requestId !== this.loadRequestId) {
        return;
      }

      if (currentUser === null) {
        if (!clearAuthWhenServerUserMissing) {
          hilog.warn(0x0000, TAG, 'Server current_user unavailable during auth sync, keep cached login state');
          this.isLoggedIn = true;
          this.errorMessage = '';
          if (snapshotUsername.length > 0) {
            await this.hydrateVisibleUserByUsername(api, auth, snapshotUsername, requestId);
          }
          return;
        }
        await this.clearLocalAuth(false);
        ToastService.show('登录状态已失效，请重新登录');
        return;
      }

      let resolvedUser: User = currentUser;
      if (this.needsProfileDetails(currentUser)) {
        try {
          const profileUser: User = await api.getUserProfile(currentUser.username);
          if (requestId !== this.loadRequestId) {
            return;
          }
          resolvedUser = this.mergeSessionAndProfileUser(currentUser, profileUser);
        } catch (profileErr) {
          hilog.warn(0x0000, TAG, 'Load profile details failed, keep session user: %{public}s', ApiClient.formatError(profileErr));
        }
      }

      auth.setCurrentUser(resolvedUser);
      api.setCachedCurrentUser(resolvedUser);
      this.currentUser = resolvedUser;
      this.isLoggedIn = true;
      this.errorMessage = '';
      const cachedSummary: UserSummary | null = await this.loadSummarySnapshot(resolvedUser.username);
      if (requestId !== this.loadRequestId) {
        return;
      }
      this.summary = cachedSummary;
      this.isSummaryLoading = cachedSummary === null;

      try {
        const summary: UserSummary = await api.getUserSummary(resolvedUser.username);
        if (requestId === this.loadRequestId) {
          this.summary = summary;
          this.isSummaryLoading = false;
          this.persistSummarySnapshot(resolvedUser.username, summary).catch((persistErr: Object) => {
            hilog.warn(0x0000, TAG, 'Persist profile summary snapshot failed: %{public}s', JSON.stringify(persistErr));
          });
        }
      } catch (summaryErr) {
        hilog.error(0x0000, TAG, 'Load user summary failed: %{public}s', ApiClient.formatError(summaryErr));
        if (requestId === this.loadRequestId) {
          this.isSummaryLoading = false;
        }
      }
    } catch (err) {
      hilog.error(0x0000, TAG, 'Load profile data failed: %{public}s', ApiClient.formatError(err));
      if (requestId === this.loadRequestId && this.currentUser !== null && this.isRateLimitError(err)) {
        this.isLoggedIn = true;
        this.errorMessage = '';
        const visibleUsername: string = (this.currentUser as User).username.trim();
        if (visibleUsername.length > 0) {
          await this.hydrateVisibleUserByUsername(ApiClient.getInstance(), AuthService.getInstance(), visibleUsername, requestId);
        } else {
          this.isSummaryLoading = false;
        }
        return;
      }
      if (requestId === this.loadRequestId && this.currentUser === null) {
        this.errorMessage = this.normalizeErrorMessage(err, '加载个人信息失败');
        this.isSummaryLoading = false;
      }
    } finally {
      if (requestId === this.loadRequestId) {
        this.isLoading = false;
        this.isRefreshing = false;
      }
    }
  }

  private normalizeErrorMessage(err: Object, fallback: string): string {
    if (err === undefined || err === null) {
      return fallback;
    }
    const text: string = err.toString().replace('Error: ', '').trim();
    return text.length > 0 ? text : fallback;
  }

  private applyLoggedOutState(): void {
    this.loadRequestId += 1;
    this.isLoggedIn = false;
    this.currentUser = null;
    this.summary = null;
    this.isSummaryLoading = false;
    this.isNotificationQuickPanelVisible = false;
    this.errorMessage = '';
    this.showTitle = false;
    this.isLoading = false;
    this.isRefreshing = false;
  }

  private async clearLocalAuth(showToast: boolean): Promise<void> {
    try {
      await CookieStore.getInstance().init();
    } catch (_) {
    }

    const allCookies: Record<string, string> = CookieStore.getInstance().getAllCookies();
    const cookieNames: string[] = Object.keys(allCookies);
    CookieStore.getInstance().clearAll();

    for (let i = 0; i < cookieNames.length; i++) {
      const name: string = cookieNames[i];
      if (name.trim().length === 0) continue;
      try {
        webview.WebCookieManager.configCookieSync(
          AppConstants.BASE_URL,
          `${name}=; Max-Age=0; Path=/;`,
          false,
          true
        );
      } catch (err) {
        try {
          webview.WebCookieManager.configCookieSync(
            AppConstants.BASE_URL,
            `${name}=; Max-Age=0; Path=/;`,
            false
          );
        } catch (_) {
        }
        hilog.error(0x0000, TAG, 'Clear web cookie failed: %{public}s', JSON.stringify(err));
      }
    }

    try {
      webview.WebCookieManager.saveCookieAsync();
    } catch (_) {
    }

    try {
      await AuthService.getInstance().logout();
    } catch (err) {
      hilog.error(0x0000, TAG, 'Auth logout failed: %{public}s', JSON.stringify(err));
    }

    this.applyLoggedOutState();
    this.scrollToTop();
    if (showToast) {
      ToastService.show('已退出登录');
    }
  }

  private scrollToTop(): void {
    try {
      this.scroller.scrollTo({ xOffset: 0, yOffset: 0, animation: { duration: 220, curve: Curve.EaseOut } });
    } catch (_) {
      this.scroller.scrollBy(0, -99999);
    }
  }

  private getDisplayName(): string {
    if (this.currentUser === null) {
      return '未登录';
    }
    const name: string | null = (this.currentUser as User).name;
    if (name !== null && name.trim().length > 0) {
      return name.trim();
    }
    return (this.currentUser as User).username;
  }

  private getUsername(): string {
    if (this.currentUser === null) {
      return '';
    }
    return (this.currentUser as User).username.trim();
  }

  private getAvatarUrl(size: number): string {
    if (this.currentUser === null) {
      return '';
    }
    return (this.currentUser as User).getAvatarUrl(size);
  }

  private getTrustLevelText(): string {
    if (this.currentUser === null) {
      return '';
    }
    return (this.currentUser as User).trustLevelString;
  }

  private getTrustLevelColor(): string {
    if (this.currentUser === null) {
      return '#999999';
    }
    return ThemeManager.getTrustLevelColor((this.currentUser as User).trustLevel);
  }

  private getStatus(): UserStatus | null {
    if (this.currentUser === null) {
      return null;
    }
    return (this.currentUser as User).status;
  }

  private getStatusEmojiText(): string {
    const status: UserStatus | null = this.getStatus();
    if (status === null || status.emoji === null) {
      return '';
    }
    return (status.emoji as string).trim();
  }

  private getStatusDescription(): string {
    const status: UserStatus | null = this.getStatus();
    if (status === null || status.description === null) {
      return '';
    }
    return (status.description as string).trim();
  }

  private getUnreadCount(): number {
    if (this.currentUser === null) {
      return 0;
    }
    return (this.currentUser as User).allUnreadNotificationsCount;
  }

  private canShowInviteLinks(): boolean {
    return this.currentUser !== null && (this.currentUser as User).trustLevel >= 3;
  }

  private openMyProfile(): void {
    const username: string = this.getUsername();
    if (username.length > 0) {
      RouterManager.pushUserProfile(username);
    }
  }

  private openProfileEdit(): void {
    const username: string = this.getUsername();
    if (username.length > 0) {
      RouterManager.pushWebView(`${AppConstants.BASE_URL}/u/${username}/preferences/account`, '编辑资料');
    }
  }

  private openNotifications(): void {
    this.isNotificationQuickPanelVisible = true;
  }

  private openNotificationsPage(): void {
    this.isNotificationQuickPanelVisible = false;
    setTimeout(() => {
      RouterManager.pushNotifications();
    }, 0);
  }

  private openBookmarks(): void {
    RouterManager.pushBookmarks();
  }

  private openDrafts(): void {
    RouterManager.pushDrafts();
  }

  private openMyTopics(): void {
    RouterManager.pushMyTopics();
  }

  private openBadges(): void {
    RouterManager.pushMyBadges();
  }

  private openInviteLinks(): void {
    const username: string = this.getUsername();
    if (username.length > 0) {
      RouterManager.pushWebView(`${AppConstants.BASE_URL}/u/${username}/invited/pending`, '邀请链接');
    }
  }

  private openTrustRequirements(): void {
    RouterManager.pushTrustRequirements();
  }

  private openBrowsingHistory(): void {
    RouterManager.pushBrowsingHistory();
  }

  private openMetaverse(): void {
    RouterManager.pushMetaverse();
  }

  private openAppearance(): void {
    RouterManager.pushAppearance();
  }

  private openPreferences(): void {
    RouterManager.pushPreferences();
  }

  private openAbout(): void {
    RouterManager.pushAbout();
  }

  private showPendingToast(title: string): void {
    ToastService.show(`${title}待接入`);
  }

  private async logout(): Promise<void> {
    if (this.isLoggingOut) {
      return;
    }
    this.isLoggingOut = true;
    try {
      await this.clearLocalAuth(true);
    } finally {
      this.isLoggingOut = false;
    }
  }

  build() {
    Column() {
      this.TopBar()

      if (this.isLoading && this.currentUser === null && this.errorMessage.length === 0) {
        Column() {
          LoadingSpinner({ message: '' })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      } else if (this.errorMessage.length > 0 && this.currentUser === null) {
        Column() {
          ErrorView({
            title: '加载失败',
            message: this.errorMessage,
            onRetry: () => {
              this.refreshPage(true).catch((err: Object) => {
                hilog.error(0x0000, TAG, 'Retry refresh failed: %{public}s', JSON.stringify(err));
              });
            }
          })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        Refresh({ refreshing: this.isRefreshing }) {
          Scroll(this.scroller) {
            Column() {
              this.HeaderSection()
              Blank().height(24)

              if (this.isLoggedIn && this.summary !== null) {
                this.StatsCard()
                Blank().height(24)
              } else if (this.isLoggedIn && this.currentUser !== null && (this.isSummaryLoading || this.isRefreshing)) {
                this.SummaryLoadingCard()
                Blank().height(24)
              } else if (this.isLoggedIn && this.currentUser !== null) {
                this.SummaryPlaceholderCard()
                Blank().height(24)
              }

              if (this.isLoggedIn && this.currentUser !== null) {
                this.LoggedInOptionsCard()
                Blank().height(20)
              }

              this.AboutCard()
              Blank().height(32)
              this.AuthButton()
              Blank().height(48)
            }
            .width('100%')
            .padding({
              left: 16,
              right: 16,
              top: 12,
              bottom: this.getFloatingTabBarReservedBottomVp()
            })
          }
          .width('100%')
          .layoutWeight(1)
          .scrollBar(BarState.Off)
          .onScrollFrameBegin((offset: number, _state: ScrollState) => {
            const next: number = Math.max(0, this.scrollOffset + offset);
            this.scrollOffset = next;
            const shouldShow: boolean = this.isLoggedIn && next > 80;
            if (shouldShow !== this.showTitle) {
              this.showTitle = shouldShow;
            }
            return { offsetRemain: offset };
          })
        }
        .onRefreshing(() => {
          this.pullToRefresh().catch((err: Object) => {
            hilog.error(0x0000, TAG, 'Pull to refresh profile failed: %{public}s', JSON.stringify(err));
          });
        })
        .layoutWeight(1)
        .width('100%')
      }
    }
    .width('100%')
    .height('100%')
    .padding({ top: WindowManager.getSystemAvoidAreaTopVp() })
    .backgroundColor($r('app.color.background'))
    .bindSheet($$this.isNotificationQuickPanelVisible, this.NotificationQuickPanelBuilder, {
      height: SheetSize.LARGE,
      dragBar: false,
      showClose: false,
      backgroundColor: $r('app.color.surface')
    })
  }

  @Builder
  private TopBar() {
    Row() {
      if (this.showTitle && this.currentUser !== null) {
        Row() {
          AvatarWithFlair({
            avatarUrl: this.getAvatarUrl(56),
            avatarSize: 28,
            fallbackText: this.getDisplayName(),
            flairUrl: (this.currentUser as User).flairUrl,
            flairName: (this.currentUser as User).flairName,
            flairBgColor: (this.currentUser as User).flairBgColor,
            flairColor: (this.currentUser as User).flairColor,
            flairSize: 12
          })

          Text(this.getDisplayName())
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.on_surface'))
            .margin({ left: 8 })
            .layoutWeight(1)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .layoutWeight(1)
        .onClick(() => {
          this.scrollToTop();
        })
      } else {
        Blank().layoutWeight(1)
      }

      if (this.isLoggedIn) {
        Row() {
          Row() {
            if (this.isRefreshing) {
              LoadingProgress().width(18).height(18)
            } else if (this.errorMessage.length > 0) {
              SymbolGlyph($r('sys.symbol.exclamationmark_triangle'))
                .fontSize(16)
                .fontColor([$r('app.color.on_surface_tertiary')])
            } else {
              Blank().width(18).height(18)
            }
          }
          .width(24)
          .height(24)
          .justifyContent(FlexAlign.Center)
          .alignItems(VerticalAlign.Center)

          this.TopIconButton($r('sys.symbol.gearshape'), () => {
            this.openProfileEdit();
          })

          Stack({ alignContent: Alignment.TopEnd }) {
            Row() {
              SymbolGlyph($r('sys.symbol.bell'))
                .fontSize(19)
                .fontColor([$r('app.color.on_surface')])
            }
            .width(36)
            .height(36)
            .justifyContent(FlexAlign.Center)
            .alignItems(VerticalAlign.Center)
            .onClick(() => {
              this.openNotifications();
            })

            if (this.getUnreadCount() > 0) {
              Row() {
                Text(this.getUnreadCount() > 99 ? '99+' : this.getUnreadCount().toString())
                  .fontSize(9)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(Color.White)
              }
              .padding({ left: 5, right: 5, top: 1, bottom: 1 })
              .backgroundColor($r('app.color.error'))
              .borderRadius(8)
              .margin({ top: 2, right: 0 })
            }
          }
          .width(36)
          .height(36)
        }
        .alignItems(VerticalAlign.Center)
      }
    }
    .width('100%')
    .height(56)
    .padding({ left: 12, right: 12, top: 6, bottom: 6 })
    .backgroundColor($r('app.color.background'))
    .alignItems(VerticalAlign.Center)
    .shadow({ radius: this.scrollOffset > 0 ? 8 : 0, color: $r('app.color.shadow_light'), offsetX: 0, offsetY: 2 })
  }

  @Builder
  private TopIconButton(symbol: Resource, onClick: () => void = () => {}) {
    Row() {
      SymbolGlyph(symbol)
        .fontSize(19)
        .fontColor([$r('app.color.on_surface')])
    }
    .width(36)
    .height(36)
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
    .margin({ left: 8 })
    .onClick(() => {
      onClick();
    })
  }

  @Builder
  private HeaderSection() {
    Row() {
      AvatarWithFlair({
        avatarUrl: this.getAvatarUrl(144),
        avatarSize: HEADER_AVATAR_SIZE,
        avatarRadius: HEADER_AVATAR_SIZE / 2,
        fallbackText: this.isLoggedIn ? this.getDisplayName() : '',
        bgColor: '#E8EAF0',
        flairUrl: this.currentUser !== null ? (this.currentUser as User).flairUrl : null,
        flairName: this.currentUser !== null ? (this.currentUser as User).flairName : null,
        flairBgColor: this.currentUser !== null ? (this.currentUser as User).flairBgColor : null,
        flairColor: this.currentUser !== null ? (this.currentUser as User).flairColor : null,
        flairSize: 24
      })

      Column() {
        Text(this.getDisplayName())
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.on_surface'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        if (this.isLoggedIn && this.getUsername().length > 0) {
          Text(`@${this.getUsername()}`)
            .fontSize(14)
            .fontColor($r('app.color.on_surface_secondary'))
            .margin({ top: 4 })
        } else {
          Text('登录后体验更多功能')
            .fontSize(14)
            .fontColor($r('app.color.on_surface_secondary'))
            .margin({ top: 4 })
        }

        if (this.isLoggedIn && this.currentUser !== null) {
          Flex({ wrap: FlexWrap.Wrap }) {
            Text(this.getTrustLevelText())
              .fontSize(11)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.getTrustLevelColor())
              .padding({ left: 8, right: 8, top: 3, bottom: 3 })
              .backgroundColor(ThemeManager.hexWithAlpha(this.getTrustLevelColor(), 0.14))
              .borderRadius(10)
              .margin({ right: 8, bottom: 4 })

            if (this.getStatusEmojiText().length > 0 || this.getStatusDescription().length > 0) {
              Row() {
                if (this.getStatusEmojiText().length > 0) {
                  UserStatusEmoji({
                    rawEmoji: this.getStatusEmojiText(),
                    iconSize: 14,
                    marginLeft: 0
                  })
                }
                if (this.getStatusDescription().length > 0) {
                  Text(this.getStatusDescription())
                    .fontSize(11)
                    .fontWeight(FontWeight.Medium)
                    .fontColor($r('app.color.on_surface_secondary'))
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .margin({ left: this.getStatusEmojiText().length > 0 ? 4 : 0 })
                }
              }
              .padding({ left: 8, right: 8, top: 3, bottom: 3 })
              .backgroundColor($r('app.color.card_background'))
              .borderRadius(10)
              .margin({ bottom: 4 })
            }
          }
          .margin({ top: 8 })
        }
      }
      .layoutWeight(1)
      .margin({ left: 20 })
      .alignItems(HorizontalAlign.Start)

      if (this.isLoggedIn && this.currentUser !== null) {
        Row() {
          SymbolGlyph($r('sys.symbol.chevron_right'))
            .fontSize(16)
            .fontColor([$r('app.color.on_surface_tertiary')])
        }
        .width(32)
        .height(32)
        .borderRadius(16)
        .backgroundColor($r('app.color.card_background'))
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Center)
        .margin({ left: 12 })
      }
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      if (this.isLoggedIn && this.currentUser !== null) {
        this.openMyProfile();
      }
    })
  }

  @Builder
  private StatsCard() {
    Column() {
      Row() {
        this.StatItem(this.formatCount((this.summary as UserSummary).daysVisited), '访问天数')
        this.VerticalDivider()
        this.StatItem(this.formatCount((this.summary as UserSummary).postsReadCount), '阅读帖子')
        this.VerticalDivider()
        this.StatItem(this.formatCount((this.summary as UserSummary).likesReceived), '获得点赞')
        this.VerticalDivider()
        this.StatItem(this.formatCount((this.summary as UserSummary).postCount), '发表回复')
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 20, bottom: 20 })
    .backgroundColor($r('app.color.card_background'))
    .borderRadius(16)
  }

  @Builder
  private SummaryLoadingCard() {
    Row() {
      LoadingProgress().width(20).height(20)
      Text('正在刷新社区表现...')
        .fontSize(13)
        .fontColor($r('app.color.on_surface_secondary'))
        .margin({ left: 8 })
    }
    .width('100%')
    .padding({ top: 18, bottom: 18 })
    .justifyContent(FlexAlign.Center)
    .backgroundColor($r('app.color.card_background'))
    .borderRadius(16)
  }

  @Builder
  private SummaryPlaceholderCard() {
    Row() {
      this.StatItem('--', '访问天数')
      this.VerticalDivider()
      this.StatItem('--', '阅读帖子')
      this.VerticalDivider()
      this.StatItem('--', '获得点赞')
      this.VerticalDivider()
      this.StatItem('--', '发表回复')
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 20, bottom: 20 })
    .backgroundColor($r('app.color.card_background'))
    .borderRadius(16)
    .opacity(0.68)
  }

  @Builder
  private VerticalDivider() {
    Blank()
      .width(1)
      .height(20)
      .backgroundColor(ThemeManager.hexWithAlpha('#A0A6B1', 0.35))
  }

  @Builder
  private StatItem(value: string, label: string) {
    Column() {
      Text(value)
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppSettingsService.getInstance().getPrimaryColor())
      Text(label)
        .fontSize(11)
        .fontColor($r('app.color.on_surface_secondary'))
        .margin({ top: 4 })
    }
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  private LoggedInOptionsCard() {
    Column() {
      this.OptionItem({
        iconSymbol: $r('sys.symbol.bookmark'),
        iconBgColor: '#FFF3E0',
        iconColor: '#FB8C00',
        title: '我的书签',
        showDivider: true,
        onClick: () => { this.openBookmarks(); }
      })
      this.OptionItem({
        iconSymbol: $r('sys.symbol.notepad'),
        iconBgColor: '#E0F2F1',
        iconColor: '#00897B',
        title: '我的草稿',
        showDivider: true,
        onClick: () => { this.openDrafts(); }
      })
      this.OptionItem({
        iconSymbol: $r('sys.symbol.message'),
        iconBgColor: '#E0F7FA',
        iconColor: '#00ACC1',
        title: '我的话题',
        showDivider: true,
        onClick: () => { this.openMyTopics(); }
      })
      this.OptionItem({
        iconSymbol: $r('sys.symbol.medal'),
        iconBgColor: '#FFF8E1',
        iconColor: '#FFB300',
        title: '我的徽章',
        showDivider: true,
        onClick: () => { this.openBadges(); }
      })
      this.OptionItem({
        iconSymbol: $r('sys.symbol.security_shield'),
        iconBgColor: '#E8F5E9',
        iconColor: '#43A047',
        title: '信任要求',
        showDivider: true,
        onClick: () => { this.openTrustRequirements(); }
      })
      if (this.canShowInviteLinks()) {
        this.OptionItem({
          iconSymbol: $r('sys.symbol.link'),
          iconBgColor: '#E0F7FA',
          iconColor: '#00ACC1',
          title: '邀请链接',
          showDivider: true,
          onClick: () => { this.openInviteLinks(); }
        })
      }
      this.OptionItem({
        iconSymbol: $r('sys.symbol.clock'),
        iconBgColor: '#F3E5F5',
        iconColor: '#8E24AA',
        title: '浏览历史',
        showDivider: true,
        onClick: () => { this.openBrowsingHistory(); }
      })
      this.OptionItem({
        iconSymbol: $r('sys.symbol.archivebox'),
        iconBgColor: '#FBE9E7',
        iconColor: '#F4511E',
        title: '元宇宙',
        showDivider: false,
        onClick: () => { this.openMetaverse(); }
      })
    }
    .width('100%')
    .backgroundColor($r('app.color.card_background'))
    .borderRadius(16)
  }

  @Builder
  private AboutCard() {
    Column() {
      this.OptionItem({
        iconSymbol: $r('sys.symbol.robot'),
        iconBgColor: '#E0F7FA',
        iconColor: '#00ACC1',
        title: 'AI 模型服务',
        showDivider: true,
        onClick: () => { this.showPendingToast('AI 模型服务'); }
      })
      this.OptionItem({
        iconSymbol: $r('sys.symbol.paintbrush'),
        iconBgColor: '#E0F2F1',
        iconColor: '#00897B',
        title: '外观设置',
        showDivider: true,
        onClick: () => { this.openAppearance(); }
      })
      this.OptionItem({
        iconSymbol: $r('sys.symbol.wifi'),
        iconBgColor: '#E8F5E9',
        iconColor: '#43A047',
        title: '网络设置',
        showDivider: true,
        onClick: () => { this.showPendingToast('网络设置'); }
      })
      this.OptionItem({
        iconSymbol: $r('sys.symbol.gearshape'),
        iconBgColor: '#EDE7F6',
        iconColor: '#5E35B1',
        title: '功能设置',
        showDivider: true,
        onClick: () => { this.openPreferences(); }
      })
      this.OptionItem({
        iconSymbol: $r('sys.symbol.archivebox'),
        iconBgColor: '#EFEBE9',
        iconColor: '#6D4C41',
        title: '数据管理',
        showDivider: true,
        onClick: () => { this.showPendingToast('数据管理'); }
      })
      this.OptionItem({
        iconSymbol: $r('sys.symbol.info_circle'),
        iconBgColor: '#E8EAF6',
        iconColor: '#3949AB',
        title: '关于 HarmonyDo',
        showDivider: false,
        onClick: () => { this.openAbout(); }
      })
    }
    .width('100%')
    .backgroundColor($r('app.color.card_background'))
    .borderRadius(16)
  }

  @Builder
  private AuthButton() {
    if (this.isLoggedIn) {
      Button() {
        Row() {
          if (this.isLoggingOut) {
            LoadingProgress().width(18).height(18)
            Text('正在退出...')
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.error'))
              .margin({ left: 8 })
          } else {
            Text('退出当前账号')
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.error'))
          }
        }
        .justifyContent(FlexAlign.Center)
      }
      .width('100%')
      .height(48)
      .backgroundColor(ThemeManager.hexWithAlpha('#D32F2F', 0.08))
      .borderRadius(24)
      .onClick(() => {
        this.logout().catch((err: Object) => {
          hilog.error(0x0000, TAG, 'Logout failed: %{public}s', JSON.stringify(err));
          ToastService.show('退出失败');
        });
      })
    } else {
      Button() {
        Row() {
          SymbolGlyph($r('sys.symbol.arrow_right'))
            .fontSize(20)
            .fontColor([Color.White])
            .margin({ right: 8 })
          Text('登录 Linux.do')
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor(Color.White)
        }
        .justifyContent(FlexAlign.Center)
      }
      .width('100%')
      .height(52)
      .backgroundColor(AppSettingsService.getInstance().getPrimaryColor())
      .borderRadius(16)
      .onClick(() => {
        RouterManager.pushLogin();
      })
    }
  }

  @Builder
  private NotificationQuickPanelBuilder() {
    NotificationQuickPanel({
      onClose: () => {
        this.isNotificationQuickPanelVisible = false;
      },
      onViewAll: () => {
        this.openNotificationsPage();
      }
    })
  }

  private formatCount(count: number): string {
    if (count >= 10000) {
      return `${(count / 10000).toFixed(1)}w`;
    }
    if (count >= 1000) {
      return `${(count / 1000).toFixed(1)}k`;
    }
    return count.toString();
  }

  @Builder
  private OptionItem(params: ProfileOptionItem) {
    Column() {
      Row() {
        Column() {
          SymbolGlyph(params.iconSymbol)
            .fontSize(20)
            .fontColor([params.iconColor])
        }
        .width(36)
        .height(36)
        .borderRadius(10)
        .backgroundColor(params.iconBgColor)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)

        Text(params.title)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.on_surface'))
          .margin({ left: 16 })
          .layoutWeight(1)

        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(20)
          .fontColor([$r('app.color.on_surface_tertiary')])
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 16, bottom: 16 })
      .alignItems(VerticalAlign.Center)
      .onClick(() => {
        params.onClick();
      })

      if (params.showDivider) {
        Divider()
          .color($r('app.color.divider_light'))
          .strokeWidth(0.5)
          .margin({ left: 60 })
      }
    }
    .width('100%')
  }
}
