import { DiscourseNotification, NotificationType } from '../../models/Notification';
import { User } from '../../models/User';
import { TimeUtils } from '../../common/utils/TimeUtils';
import { RouterManager } from '../../common/utils/RouterManager';
import { ToastService } from '../../common/utils/ToastService';
import { WindowManager } from '../../common/utils/WindowManager';
import { ApiClient } from '../../services/network/ApiClient';
import { AuthService } from '../../services/auth/AuthService';
import { LoadingSpinner } from './LoadingSpinner';
import { SmartAvatar } from './SmartAvatar';

@ComponentV2
export struct NotificationQuickPanel {
  @Param onClose: () => void = () => {};
  @Param onViewAll: () => void = () => {};

  @Local notifications: DiscourseNotification[] = [];
  @Local isLoading: boolean = true;
  @Local isMarkingAllRead: boolean = false;
  @Local errorMessage: string = '';

  private loadRequestId: number = 0;

  aboutToAppear(): void {
    this.loadNotifications().catch((err: Object) => {
      this.errorMessage = this.normalizeErrorMessage(err);
      this.isLoading = false;
    });
  }

  private normalizeErrorMessage(err: Object): string {
    if (err === undefined || err === null) {
      return '加载通知失败';
    }
    const text: string = err.toString().replace('Error: ', '').trim();
    return text.length > 0 ? text : '加载通知失败';
  }

  private async loadNotifications(): Promise<void> {
    const requestId: number = ++this.loadRequestId;
    this.isLoading = true;
    this.errorMessage = '';
    try {
      const response = await ApiClient.getInstance().getNotifications(0, 20);
      if (requestId !== this.loadRequestId) {
        return;
      }
      this.notifications = response.notifications;
    } catch (err) {
      if (requestId === this.loadRequestId) {
        this.errorMessage = this.normalizeErrorMessage(err);
      }
    } finally {
      if (requestId === this.loadRequestId) {
        this.isLoading = false;
      }
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
  }

  private markLocalNotificationRead(notificationId: number): void {
    const next: DiscourseNotification[] = [];
    let changed: boolean = false;
    for (let i = 0; i < this.notifications.length; i++) {
      const item: DiscourseNotification = this.notifications[i];
      if (item.id === notificationId && !item.read) {
        item.read = true;
        changed = true;
      }
      next.push(item);
    }
    this.notifications = next;
    if (!changed) {
      return;
    }
    const currentUser: User | null = AuthService.getInstance().getCurrentUser();
    const currentUnread: number = currentUser !== null ? currentUser.allUnreadNotificationsCount : 0;
    this.updateUnreadCount(Math.max(0, currentUnread - 1));
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

  private closeThen(action: () => void): void {
    this.onClose();
    setTimeout(() => {
      action();
    }, 0);
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
      const topicId: number = notification.topicId as number;
      const postNumber: number = notification.postNumber !== null ? notification.postNumber as number : 0;
      this.closeThen(() => {
        RouterManager.pushTopicDetail(topicId, postNumber);
      });
      return;
    }

    if (notification.notificationTypeId === NotificationType.GRANTED_BADGE
      && notification.data.badgeId !== null
      && (notification.data.badgeId as number) > 0) {
      this.closeThen(() => {
        RouterManager.pushBadgeDetail(
          notification.data.badgeId as number,
          notification.data.badgeSlug !== null ? notification.data.badgeSlug as string : '',
          AuthService.getInstance().getCurrentUsername()
        );
      });
      return;
    }

    const username: string = notification.username.trim();
    if (username.length > 0) {
      this.closeThen(() => {
        RouterManager.pushUserProfile(username);
      });
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

  build() {
    Column() {
      Column() {
        Blank()
          .width(32)
          .height(4)
          .borderRadius(2)
          .backgroundColor('#D4D8DF')
      }
      .width('100%')
      .padding({ top: 10, bottom: 6 })
      .alignItems(HorizontalAlign.Center)

      Row() {
        Text('通知')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.on_surface'))

        Blank().layoutWeight(1)

        Row() {
          if (this.isMarkingAllRead) {
            LoadingProgress().width(16).height(16)
          } else {
            SymbolGlyph($r('sys.symbol.checkmark_circle'))
              .fontSize(18)
              .fontColor([$r('app.color.on_surface_secondary')])
          }
        }
        .width(34)
        .height(34)
        .borderRadius(17)
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Center)
        .onClick(() => {
          this.markAllAsRead().catch(() => {
          });
        })

        Row() {
          Text('查看全部')
            .fontSize(14)
            .fontColor($r('app.color.on_surface_secondary'))
          SymbolGlyph($r('sys.symbol.chevron_right'))
            .fontSize(16)
            .fontColor([$r('app.color.on_surface_secondary')])
            .margin({ left: 2 })
        }
        .height(34)
        .padding({ left: 10, right: 6 })
        .borderRadius(17)
        .margin({ left: 6 })
        .onClick(() => {
          this.onViewAll();
        })
      }
      .width('100%')
      .padding({ left: 20, right: 12, top: 2, bottom: 8 })
      .alignItems(VerticalAlign.Center)

      if (this.isLoading && this.notifications.length === 0 && this.errorMessage.length === 0) {
        Column() {
          LoadingSpinner({ message: '' })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      } else if (this.errorMessage.length > 0 && this.notifications.length === 0) {
        Column() {
          SymbolGlyph($r('sys.symbol.exclamationmark_triangle'))
            .fontSize(30)
            .fontColor([$r('app.color.on_surface_tertiary')])
            .margin({ bottom: 10 })
          Text(this.errorMessage)
            .fontSize(14)
            .fontColor($r('app.color.on_surface_secondary'))
          Text('点击重试')
            .fontSize(13)
            .fontColor($r('app.color.primary'))
            .margin({ top: 12 })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .onClick(() => {
          this.loadNotifications().catch(() => {
          });
        })
      } else {
        List() {
          if (!this.isLoading && this.notifications.length === 0) {
            ListItem() {
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
            }
          } else {
            ForEach(this.notifications, (notification: DiscourseNotification) => {
              ListItem() {
                this.NotificationRow(notification)
              }
            }, (notification: DiscourseNotification) => notification.id.toString())
          }
        }
        .width('100%')
        .layoutWeight(1)
        .padding({ left: 16, right: 16, bottom: 12 + WindowManager.getSystemAvoidAreaBottomVp() })
        .scrollBar(BarState.Off)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.surface'))
  }

  @Builder
  private NotificationRow(notification: DiscourseNotification) {
    Column() {
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
              .backgroundColor(`${this.getNotificationAccentColor(notification)}1A`)
              .borderRadius(9)

            Text(TimeUtils.formatRelativeTime(notification.createdAt))
              .fontSize(11)
              .fontColor($r('app.color.on_surface_tertiary'))
              .margin({ left: 8 })
          }
          .margin({ top: 8 })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        .margin({ left: 14 })
      }
      .width('100%')
      .padding({ left: 4, right: 4, top: 14, bottom: 14 })
      .alignItems(VerticalAlign.Top)
      .onClick(() => {
        this.openNotification(notification).catch(() => {
        });
      })

      Blank()
        .width('100%')
        .height(1)
        .backgroundColor('#EEF1F5')
        .margin({ left: 62 })
    }
    .width('100%')
  }
}
