import { hilog } from '@kit.PerformanceAnalysisKit';
import { PreferencesUtil } from '../storage/PreferencesUtil';
import { ApiClient } from '../network/ApiClient';
import { CookieStore } from '../network/CookieStore';
import { User, UserStatus } from '../../models/User';
import { AuthSessionService } from './AuthSessionService';
import { LoginCredentialStore } from './LoginCredentialStore';

const TAG: string = 'AuthService';

/**
 * 认证服务
 *
 * 管理用户登录状态、Token 存储
 */
export class AuthService {
  private static instance: AuthService | null = null;
  private static readonly LEGACY_KEY_COOKIES: string = 'auth_cookies';
  private static readonly KEY_CSRF_TOKEN: string = 'csrf_token';
  private static readonly KEY_USERNAME: string = 'username';
  private static readonly KEY_IS_LOGGED_IN: string = 'is_logged_in';
  private static readonly KEY_CURRENT_USER: string = 'current_user_json';

  private currentUser: User | null = null;
  private currentUsername: string = '';
  private isLoggedIn: boolean = false;
  private csrfToken: string = '';
  private listeners: (() => void)[] = [];
  private notifyScheduled: boolean = false;
  private initialized: boolean = false;

  private constructor() {
  }

  static getInstance(): AuthService {
    if (AuthService.instance === null) {
      AuthService.instance = new AuthService();
    }
    return AuthService.instance;
  }

  /**
   * 初始化认证状态（从存储中恢复）
   */
  async init(): Promise<void> {
    if (this.initialized) {
      return;
    }
    try {
      await PreferencesUtil.ensureInit();
      this.isLoggedIn = await PreferencesUtil.getBoolean(AuthService.KEY_IS_LOGGED_IN, false);
      this.currentUsername = await PreferencesUtil.getString(AuthService.KEY_USERNAME, '');
      const legacyCookies: string = await PreferencesUtil.getString(AuthService.LEGACY_KEY_COOKIES, '');
      this.csrfToken = await PreferencesUtil.getString(AuthService.KEY_CSRF_TOKEN, '');
      const currentUserRaw: string = await PreferencesUtil.getString(AuthService.KEY_CURRENT_USER, '');
      this.currentUser = this.parseStoredCurrentUser(currentUserRaw);
      if (this.currentUser !== null && this.currentUser.username.trim().length > 0) {
        this.currentUsername = this.currentUser.username;
      }
      await this.migrateLegacyCookies(legacyCookies);
      this.initialized = true;

      hilog.info(0x0000, TAG, 'Auth state restored, isLoggedIn: %{public}s', this.isLoggedIn.toString());
    } catch (err) {
      hilog.error(0x0000, TAG, 'Failed to restore auth state: %{public}s', JSON.stringify(err));
    }
  }

  private async migrateLegacyCookies(legacyCookies: string): Promise<void> {
    const normalized: string = legacyCookies.trim();
    if (normalized.length === 0) {
      return;
    }

    try {
      const store: CookieStore = CookieStore.getInstance();
      await store.init();
      if (store.getCookieHeader().trim().length === 0) {
        store.ingestCookieHeader(normalized);
        hilog.info(0x0000, TAG, 'Migrated legacy auth cookies into CookieStore');
      }
    } catch (err) {
      hilog.error(0x0000, TAG, 'Migrate legacy auth cookies failed: %{public}s', JSON.stringify(err));
      return;
    }

    try {
      await PreferencesUtil.delete(AuthService.LEGACY_KEY_COOKIES);
    } catch (_) {
    }
  }

  private parseStoredCurrentUser(raw: string): User | null {
    if (raw.trim().length === 0) {
      return null;
    }
    try {
      const parsed: Object = JSON.parse(raw) as Object;
      if (parsed instanceof Array) {
        return null;
      }
      return User.fromJson(parsed as Record<string, Object>);
    } catch (err) {
      hilog.warn(0x0000, TAG, 'Parse stored current user failed: %{public}s', JSON.stringify(err));
      PreferencesUtil.delete(AuthService.KEY_CURRENT_USER).catch(() => {
      });
      return null;
    }
  }

  private serializeCurrentUser(user: User): string {
    const json: Record<string, Object> = {};
    json['id'] = user.id;
    json['username'] = user.username;
    if (user.name !== null) {
      json['name'] = user.name as string;
    }
    if (user.avatarTemplate !== null) {
      json['avatar_template'] = user.avatarTemplate as string;
    }
    if (user.animatedAvatar !== null) {
      json['animated_avatar'] = user.animatedAvatar as string;
    }
    json['trust_level'] = user.trustLevel;
    json['unread_notifications'] = user.unreadNotifications;
    json['unread_high_priority_notifications'] = user.unreadHighPriorityNotifications;
    json['all_unread_notifications_count'] = user.allUnreadNotificationsCount;
    json['seen_notification_id'] = user.seenNotificationId;
    json['notification_channel_position'] = user.notificationChannelPosition;

    if (user.status !== null) {
      const currentStatus: UserStatus = user.status as UserStatus;
      const status: Record<string, Object> = {};
      if (currentStatus.description !== null) {
        status['description'] = currentStatus.description as string;
      }
      if (currentStatus.emoji !== null) {
        status['emoji'] = currentStatus.emoji as string;
      }
      json['status'] = status as Object;
    }

    if (user.cardBackgroundUploadUrl !== null) {
      json['card_background_upload_url'] = user.cardBackgroundUploadUrl as string;
    }
    if (user.profileBackgroundUploadUrl !== null) {
      json['profile_background_upload_url'] = user.profileBackgroundUploadUrl as string;
    }
    if (user.lastPostedAt !== null) {
      json['last_posted_at'] = user.lastPostedAt.toISOString();
    }
    if (user.lastSeenAt !== null) {
      json['last_seen_at'] = user.lastSeenAt.toISOString();
    }
    if (user.createdAt !== null) {
      json['created_at'] = user.createdAt.toISOString();
    }
    if (user.location !== null) {
      json['location'] = user.location as string;
    }
    if (user.website !== null) {
      json['website'] = user.website as string;
    }
    if (user.websiteName !== null) {
      json['website_name'] = user.websiteName as string;
    }
    if (user.flairUrl !== null) {
      json['flair_url'] = user.flairUrl as string;
    }
    if (user.flairName !== null) {
      json['flair_name'] = user.flairName as string;
    }
    if (user.flairBgColor !== null) {
      json['flair_bg_color'] = user.flairBgColor as string;
    }
    if (user.flairColor !== null) {
      json['flair_color'] = user.flairColor as string;
    }
    if (user.flairGroupId !== null) {
      json['flair_group_id'] = user.flairGroupId as number;
    }
    return JSON.stringify(json);
  }

  private persistCurrentUser(): void {
    if (this.currentUser === null) {
      PreferencesUtil.delete(AuthService.KEY_CURRENT_USER).catch(() => {
      });
      return;
    }
    PreferencesUtil.putString(AuthService.KEY_CURRENT_USER, this.serializeCurrentUser(this.currentUser as User)).catch(() => {
    });
  }

  addListener(listener: () => void): void {
    for (let i = 0; i < this.listeners.length; i++) {
      if (this.listeners[i] === listener) {
        return;
      }
    }
    this.listeners.push(listener);
  }

  removeListener(listener: () => void): void {
    const next: (() => void)[] = [];
    for (let i = 0; i < this.listeners.length; i++) {
      if (this.listeners[i] !== listener) {
        next.push(this.listeners[i]);
      }
    }
    this.listeners = next;
  }

  private notifyListeners(): void {
    if (this.notifyScheduled) {
      return;
    }
    this.notifyScheduled = true;
    setTimeout(() => {
      this.notifyScheduled = false;
      for (let i = 0; i < this.listeners.length; i++) {
        try {
          this.listeners[i]();
        } catch (_) {
        }
      }
    }, 0);
  }

  /**
   * 获取登录状态
   */
  getIsLoggedIn(): boolean {
    return this.isLoggedIn;
  }

  /**
   * 获取当前用户
   */
  getCurrentUser(): User | null {
    return this.currentUser;
  }

  /**
   * 获取当前用户名
   */
  getCurrentUsername(): string {
    if (this.currentUser !== null && this.currentUser.username.trim().length > 0) {
      return this.currentUser.username;
    }
    return this.currentUsername;
  }

  /**
   * 获取 Cookies
   */
  getCookies(): string {
    return CookieStore.getInstance().getCookieHeader();
  }

  /**
   * 获取 CSRF Token
   */
  getCsrfToken(): string {
    return this.csrfToken;
  }

  /**
   * 更新 CSRF Token（登录态写接口会复用）
   */
  async updateCsrfToken(csrfToken: string): Promise<void> {
    this.csrfToken = csrfToken;
    await PreferencesUtil.putString(AuthService.KEY_CSRF_TOKEN, csrfToken);
  }

  /**
   * 保存登录信息
   */
  async saveLoginInfo(cookies: string, csrfToken: string, username: string, password: string = ''): Promise<void> {
    await this.init();
    const normalizedUsername: string = username.trim().toLowerCase();
    if (this.currentUser !== null) {
      const currentUsername: string = this.currentUser.username.trim().toLowerCase();
      if (normalizedUsername.length > 0 && currentUsername.length > 0 && currentUsername !== normalizedUsername) {
        this.currentUser = null;
        await PreferencesUtil.delete(AuthService.KEY_CURRENT_USER);
      }
    }

    const normalizedCookieHeader: string = cookies.trim();
    if (normalizedCookieHeader.length > 0) {
      try {
        const store: CookieStore = CookieStore.getInstance();
        await store.init();
        if (store.getCookieHeader().trim().length === 0) {
          store.ingestCookieHeader(normalizedCookieHeader);
        }
      } catch (err) {
        hilog.error(0x0000, TAG, 'Backfill CookieStore from login info failed: %{public}s', JSON.stringify(err));
      }
    }
    this.csrfToken = csrfToken;
    this.isLoggedIn = true;
    this.currentUsername = username;
    this.initialized = true;

    await PreferencesUtil.delete(AuthService.LEGACY_KEY_COOKIES);
    await PreferencesUtil.putString(AuthService.KEY_CSRF_TOKEN, csrfToken);
    await PreferencesUtil.putString(AuthService.KEY_USERNAME, username);
    await PreferencesUtil.putBoolean(AuthService.KEY_IS_LOGGED_IN, true);
    if (password.length > 0) {
      await LoginCredentialStore.getInstance().saveCredential(username, password);
    } else {
      await LoginCredentialStore.getInstance().clearCredentialIfUsernameMismatch(username);
    }

    hilog.info(0x0000, TAG, 'Login info saved for user: %{public}s', username);
    this.notifyListeners();
  }

  /**
   * 设置当前用户
   */
  setCurrentUser(user: User, notify: boolean = false): void {
    this.currentUser = user;
    if (user.username.trim().length > 0) {
      this.currentUsername = user.username;
    }
    this.persistCurrentUser();
    if (notify) {
      this.notifyListeners();
    }
  }

  /**
   * 退出登录
   */
  async logout(): Promise<void> {
    this.currentUser = null;
    this.currentUsername = '';
    this.isLoggedIn = false;
    this.csrfToken = '';
    this.initialized = true;
    AuthSessionService.getInstance().advance('logout');
    ApiClient.getInstance().resetCurrentUserSessionState();

    await PreferencesUtil.delete(AuthService.LEGACY_KEY_COOKIES);
    await PreferencesUtil.delete(AuthService.KEY_CSRF_TOKEN);
    await PreferencesUtil.delete(AuthService.KEY_USERNAME);
    await PreferencesUtil.delete(AuthService.KEY_CURRENT_USER);
    await PreferencesUtil.putBoolean(AuthService.KEY_IS_LOGGED_IN, false);
    await LoginCredentialStore.getInstance().clearCredential();

    hilog.info(0x0000, TAG, 'User logged out');
    this.notifyListeners();
  }
}
