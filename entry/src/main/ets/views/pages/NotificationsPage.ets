import { HdsNavDestination, HdsNavDestinationTitleMode } from '@kit.UIDesignKit';
import { DiscourseNotification, NotificationType } from '../../models/Notification';
import { User } from '../../models/User';
import { ThemeManager } from '../../common/theme/ThemeManager';
import { TimeUtils } from '../../common/utils/TimeUtils';
import { RouterManager } from '../../common/utils/RouterManager';
import { WindowManager } from '../../common/utils/WindowManager';
import { ToastService } from '../../common/utils/ToastService';
import { ApiClient } from '../../services/network/ApiClient';
import { AuthService } from '../../services/auth/AuthService';
import { NotificationTrackingService } from '../../services/messagebus/NotificationTrackingService';
import { LoadingSpinner } from '../components/LoadingSpinner';
import { ErrorView } from '../components/ErrorView';
import { SmartAvatar } from '../components/SmartAvatar';
import { ImmersiveHdsTitleBarHelper } from '../components/ImmersiveHdsTitleBarHelper';

@ComponentV2
export struct NotificationsPage {
  @Local notifications: DiscourseNotification[] = [];
  @Local isLoading: boolean = true;
  @Local isRefreshing: boolean = false;
  @Local isLoadingMore: boolean = false;
  @Local isMarkingAllRead: boolean = false;
  @Local hasMore: boolean = false;
  @Local errorMessage: string = '';
  @Local loadMoreFailed: boolean = false;

  private totalRows: number = 0;
  private contentScroller: Scroller = new Scroller();

  aboutToAppear(): void {
    if (this.notifications.length === 0) {
      this.loadNotifications(true, true).catch((err: Object) => {
        this.errorMessage = this.normalizeErrorMessage(err);
        this.isLoading = false;
      });
    }
  }

  private normalizeErrorMessage(err: Object): string {
    if (err === undefined || err === null) {
      return '加载通知失败';
    }
    const text: string = err.toString().replace('Error: ', '').trim();
    return text.length > 0 ? text : '加载通知失败';
  }

  private updateHasMore(loadMorePath: string | null): void {
    if (loadMorePath !== null && loadMorePath.trim().length > 0) {
      this.hasMore = true;
      return;
    }
    this.hasMore = this.totalRows > 0 && this.notifications.length < this.totalRows;
  }

  private async loadNotifications(reset: boolean, showLoading: boolean = false): Promise<void> {
    if (this.isLoadingMore || this.isMarkingAllRead) {
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
      const api: ApiClient = ApiClient.getInstance();
      const offset: number = reset ? 0 : this.notifications.length;
      const response = await api.getNotifications(offset, 60);

      if (reset) {
        this.notifications = response.notifications;
        this.totalRows = response.totalRowsNotifications;
      } else {
        const appended: DiscourseNotification[] = [];
        for (let i = 0; i < this.notifications.length; i++) {
          appended.push(this.notifications[i]);
        }
        for (let i = 0; i < response.notifications.length; i++) {
          const item: DiscourseNotification = response.notifications[i];
          let exists: boolean = false;
          for (let j = 0; j < appended.length; j++) {
            if (appended[j].id === item.id) {
              exists = true;
              break;
            }
          }
          if (!exists) {
            appended.push(item);
          }
        }
        this.notifications = appended;
        if (response.totalRowsNotifications > 0) {
          this.totalRows = response.totalRowsNotifications;
        }
      }
      this.updateHasMore(response.loadMoreNotifications);
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

  private updateUnreadCount(nextCount: number): void {
    const auth: AuthService = AuthService.getInstance();
    const currentUser: User | null = auth.getCurrentUser();
    if (currentUser === null) {
      return;
    }
    currentUser.unreadNotifications = 0;
    currentUser.unreadHighPriorityNotifications = 0;
    currentUser.allUnreadNotificationsCount = Math.max(0, nextCount);
    auth.setCurrentUser(currentUser, true);
    ApiClient.getInstance().setCachedCurrentUser(currentUser);
    NotificationTrackingService.getInstance().syncStateFromCurrentUser(currentUser, true);
  }

  private markLocalNotificationRead(notificationId: number): void {
    const next: DiscourseNotification[] = [];
    let unreadCount: number = 0;
    for (let i = 0; i < this.notifications.length; i++) {
      const item: DiscourseNotification = this.notifications[i];
      if (item.id === notificationId) {
        item.read = true;
      }
      if (!item.read) {
        unreadCount++;
      }
      next.push(item);
    }
    this.notifications = next;
    this.updateUnreadCount(unreadCount);
  }

  private async markAllAsRead(): Promise<void> {
    if (this.isMarkingAllRead || this.notifications.length === 0) {
      return;
    }
    this.isMarkingAllRead = true;
    try {
      await ApiClient.getInstance().markAllNotificationsRead();
      const next: DiscourseNotification[] = [];
      for (let i = 0; i < this.notifications.length; i++) {
        const item: DiscourseNotification = this.notifications[i];
        item.read = true;
        next.push(item);
      }
      this.notifications = next;
      this.updateUnreadCount(0);
      ToastService.show('已全部标为已读');
    } catch (err) {
      ToastService.show(this.normalizeErrorMessage(err));
    } finally {
      this.isMarkingAllRead = false;
    }
  }

  private async openNotification(notification: DiscourseNotification): Promise<void> {
    if (!notification.read) {
      try {
        await ApiClient.getInstance().markNotificationRead(notification.id);
      } catch (_) {
      }
      this.markLocalNotificationRead(notification.id);
    }

    if (notification.topicId !== null && (notification.topicId as number) > 0) {
      const postNumber: number = notification.postNumber !== null ? notification.postNumber as number : 0;
      RouterManager.pushTopicDetail(notification.topicId as number, postNumber);
      return;
    }

    if (notification.notificationTypeId === NotificationType.GRANTED_BADGE
      && notification.data.badgeId !== null
      && (notification.data.badgeId as number) > 0) {
      RouterManager.pushBadgeDetail(
        notification.data.badgeId as number,
        notification.data.badgeSlug !== null ? notification.data.badgeSlug as string : '',
        AuthService.getInstance().getCurrentUsername()
      );
      return;
    }

    const username: string = notification.username.trim();
    if (username.length > 0) {
      RouterManager.pushUserProfile(username);
      return;
    }

    ToastService.show('该通知暂未支持跳转');
  }

  private getNotificationIcon(notification: DiscourseNotification): Resource {
    if (notification.notificationTypeId === NotificationType.LIKED
      || notification.notificationTypeId === NotificationType.LIKED_CONSOLIDATED) {
      return $r('sys.symbol.heart_fill');
    }
    if (notification.notificationTypeId === NotificationType.MENTIONED) {
      return $r('sys.symbol.person');
    }
    if (notification.notificationTypeId === NotificationType.REPLIED
      || notification.notificationTypeId === NotificationType.QUOTED
      || notification.notificationTypeId === NotificationType.POSTED) {
      return $r('sys.symbol.message');
    }
    if (notification.notificationTypeId === NotificationType.GRANTED_BADGE) {
      return $r('sys.symbol.medal');
    }
    if (notification.notificationTypeId === NotificationType.PRIVATE_MESSAGE) {
      return $r('sys.symbol.message');
    }
    if (notification.notificationTypeId === NotificationType.BOOKMARK_REMINDER) {
      return $r('sys.symbol.bookmark');
    }
    if (notification.notificationTypeId === NotificationType.FOLLOWING) {
      return $r('sys.symbol.person_fill');
    }
    return $r('sys.symbol.bell');
  }

  private getNotificationAccentColor(notification: DiscourseNotification): string {
    if (notification.notificationTypeId === NotificationType.LIKED
      || notification.notificationTypeId === NotificationType.LIKED_CONSOLIDATED) {
      return '#E53935';
    }
    if (notification.notificationTypeId === NotificationType.MENTIONED) {
      return '#1E88E5';
    }
    if (notification.notificationTypeId === NotificationType.REPLIED
      || notification.notificationTypeId === NotificationType.QUOTED
      || notification.notificationTypeId === NotificationType.POSTED) {
      return '#00ACC1';
    }
    if (notification.notificationTypeId === NotificationType.GRANTED_BADGE) {
      return '#FFB300';
    }
    if (notification.notificationTypeId === NotificationType.PRIVATE_MESSAGE) {
      return '#8E24AA';
    }
    if (notification.notificationTypeId === NotificationType.BOOKMARK_REMINDER) {
      return '#FB8C00';
    }
    if (notification.notificationTypeId === NotificationType.FOLLOWING) {
      return '#43A047';
    }
    return '#546E7A';
  }

  private getNotificationAccentBackground(notification: DiscourseNotification): string {
    return ThemeManager.hexWithAlpha(this.getNotificationAccentColor(notification), WindowManager.isDarkMode() ? 0.22 : 0.10);
  }

  private getUnreadNotificationBackground(notification: DiscourseNotification): string {
    if (!WindowManager.isDarkMode()) {
      return '#F3F7FF';
    }
    return ThemeManager.hexWithAlpha(this.getNotificationAccentColor(notification), 0.18);
  }

  build() {
    HdsNavDestination() {
      Column() {
        Refresh({ refreshing: this.isRefreshing }) {
          if (this.isLoading && this.notifications.length === 0 && this.errorMessage.length === 0) {
            Column() {
              LoadingSpinner({ message: '' })
            }
            .width('100%')
            .height('100%')
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center)
          } else if (this.errorMessage.length > 0 && this.notifications.length === 0) {
            Column() {
              ErrorView({
                title: '加载失败',
                message: this.errorMessage,
                onRetry: () => {
                  this.loadNotifications(true, true).catch(() => {});
                }
              })
            }
            .width('100%')
            .height('100%')
            .justifyContent(FlexAlign.Center)
          } else {
            Scroll(this.contentScroller) {
              Column() {
                Blank()
                  .height(ImmersiveHdsTitleBarHelper.getContentTopSpacerHeightVp())
                  .width('100%')

              if (!this.isLoading && this.notifications.length === 0) {
                Column() {
                  SymbolGlyph($r('sys.symbol.bell'))
                    .fontSize(32)
                    .fontColor([$r('app.color.on_surface_tertiary')])
                    .margin({ bottom: 12 })
                  Text('暂无通知')
                    .fontSize(14)
                    .fontColor($r('app.color.on_surface_secondary'))
                }
                .width('100%')
                .padding({ top: 96, bottom: 96 })
                .alignItems(HorizontalAlign.Center)
              } else {
                ForEach(this.notifications, (notification: DiscourseNotification) => {
                  this.NotificationRow(notification)
                }, (notification: DiscourseNotification) => notification.id.toString())
              }

              if (this.loadMoreFailed) {
                Row() {
                  SymbolGlyph($r('sys.symbol.arrow_clockwise'))
                    .fontSize(14)
                    .fontColor([$r('app.color.primary')])
                  Text('加载更多失败，点击重试')
                    .fontSize(13)
                    .fontColor($r('app.color.primary'))
                    .margin({ left: 6 })
                }
                .width('100%')
                .height(44)
                .justifyContent(FlexAlign.Center)
                .onClick(() => {
                  this.loadNotifications(false, false).catch(() => {});
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
              } else if (!this.hasMore && this.notifications.length > 0) {
                Text('没有更多了')
                  .fontSize(12)
                  .fontColor($r('app.color.on_surface_tertiary'))
                  .width('100%')
                  .textAlign(TextAlign.Center)
                  .padding({ top: 16, bottom: 12 })
              }
              }
              .width('100%')
              .padding({ left: 16, right: 16, top: 12, bottom: 12 + WindowManager.getSystemAvoidAreaBottomVp() })
            }
            .width('100%')
            .height('100%')
            .backgroundColor($r('app.color.background'))
            .scrollBar(BarState.Off)
            .edgeEffect(EdgeEffect.Spring)
            .onReachEnd(() => {
              this.loadNotifications(false, false).catch(() => {});
            })
          }
        }
        .onRefreshing(() => {
          this.loadNotifications(true, false).catch(() => {});
        })
        .layoutWeight(1)
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.background'))
    }
    .backgroundColor($r('app.color.background'))
    .titleMode(HdsNavDestinationTitleMode.MINI)
    .titleBar(ImmersiveHdsTitleBarHelper.buildImmersiveTitleBarWithMenu(
      $r('app.string.tab_notifications'),
      this.isMarkingAllRead ? $r('sys.symbol.arrow_clockwise') : $r('sys.symbol.checkmark_circle'),
      this.isMarkingAllRead ? '正在标为已读' : '全部标为已读',
      () => {
        this.markAllAsRead().catch(() => {});
      },
      this.notifications.length > 0 && !this.isMarkingAllRead
    ))
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
  private NotificationRow(notification: DiscourseNotification) {
    Row() {
      Stack({ alignContent: Alignment.BottomEnd }) {
        SmartAvatar({
          avatarUrl: notification.getAvatarUrl(96),
          avatarSize: 44,
          avatarRadius: 22,
          fallbackText: notification.username,
          bgColor: '#E8EAF0'
        })

        Row() {
          SymbolGlyph(this.getNotificationIcon(notification))
            .fontSize(11)
            .fontColor([Color.White])
        }
        .width(18)
        .height(18)
        .borderRadius(9)
        .backgroundColor(this.getNotificationAccentColor(notification))
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Center)
      }

      Column() {
        Row() {
          Text(notification.title)
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.on_surface'))
            .layoutWeight(1)
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })

          if (!notification.read) {
            Circle()
              .width(8)
              .height(8)
              .fill($r('app.color.primary'))
              .margin({ left: 8, top: 4 })
          }
        }
        .width('100%')
        .alignItems(VerticalAlign.Top)

        Text(notification.description)
          .fontSize(13)
          .fontColor($r('app.color.on_surface_secondary'))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ top: 6 })

        Row() {
          Text(NotificationType.getLabel(notification.notificationTypeId))
            .fontSize(11)
            .fontColor(this.getNotificationAccentColor(notification))
            .padding({ left: 8, right: 8, top: 3, bottom: 3 })
            .backgroundColor(this.getNotificationAccentBackground(notification))
            .borderRadius(10)

          Text(TimeUtils.formatRelativeTime(notification.createdAt))
            .fontSize(11)
            .fontColor($r('app.color.on_surface_tertiary'))
            .margin({ left: 8 })
        }
        .margin({ top: 10 })
        .alignItems(VerticalAlign.Center)
      }
      .layoutWeight(1)
      .margin({ left: 14 })
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .padding({ left: 14, right: 14, top: 14, bottom: 14 })
    .backgroundColor(notification.read ? $r('app.color.surface') : this.getUnreadNotificationBackground(notification))
    .borderRadius(16)
    .margin({ bottom: 12 })
    .alignItems(VerticalAlign.Top)
    .onClick(() => {
      this.openNotification(notification).catch(() => {});
    })
  }
}
