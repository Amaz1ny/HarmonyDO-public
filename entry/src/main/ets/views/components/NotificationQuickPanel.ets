import { LengthMetrics } from '@kit.ArkUI';
import {
  HdsNavigation,
  HdsNavigationBackgroundStyle,
  HdsNavigationBadgeIconOptions,
  HdsNavigationIconItemStyle,
  HdsNavigationIconOptions,
  HdsNavigationMenuContentOptions,
  HdsNavigationMenuItemOptions,
  HdsNavigationTitle,
  HdsNavigationTitleBarOptions,
  HdsNavigationTitleBarStyle,
  HdsNavigationTitleMode,
  HdsNavigationTitleStyle,
  HdsTitleBarContentStyle,
  IconStyleMode,
  ScrollEffectOptions,
  ScrollEffectType,
  SystemMaterialParams,
  TitleBarContentOptions,
  TitleBarStyleOptions,
  hdsMaterial
} from '@kit.UIDesignKit';
import { DiscourseNotification, NotificationType } from '../../models/Notification';
import { User } from '../../models/User';
import { TimeUtils } from '../../common/utils/TimeUtils';
import { RouterManager } from '../../common/utils/RouterManager';
import { ToastService } from '../../common/utils/ToastService';
import { WindowManager } from '../../common/utils/WindowManager';
import { ApiClient } from '../../services/network/ApiClient';
import { AuthService } from '../../services/auth/AuthService';
import { NotificationTrackingService } from '../../services/messagebus/NotificationTrackingService';
import { LoadingSpinner } from './LoadingSpinner';
import { SmartAvatar } from './SmartAvatar';

const MODAL_TITLE_BAR_SCROLL_EFFECT_START_OFFSET_VP: number = 0;
const MODAL_TITLE_BAR_SCROLL_EFFECT_END_OFFSET_VP: number = 56;
const MODAL_TITLE_BAR_MASK_EXTRA_HEIGHT_VP: number = 20;
const MODAL_TITLE_BAR_BLUR_RADIUS: number = 22;

@ComponentV2
export struct NotificationQuickPanel {
  @Param onClose: () => void = () => {};
  @Param onViewAll: () => void = () => {};

  @Local notifications: DiscourseNotification[] = [];
  @Local isLoading: boolean = true;
  @Local isMarkingAllRead: boolean = false;
  @Local errorMessage: string = '';

  private loadRequestId: number = 0;
  private modalScroller: Scroller = new Scroller();

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
      NotificationTrackingService.getInstance().syncStateFromNotificationPreview(
        response.notifications,
        response.seenNotificationId
      );
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
    NotificationTrackingService.getInstance().syncStateFromCurrentUser(currentUser, true);
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

  private buildModalTitle(): HdsNavigationTitle {
    const title: HdsNavigationTitle = {
      mainTitle: '通知'
    };
    return title;
  }

  private buildModalTitleStyle(): HdsNavigationTitleStyle {
    const titleStyle: HdsNavigationTitleStyle = {
      mainTitleColor: $r('app.color.on_surface')
    };
    return titleStyle;
  }

  private buildModalIconItemStyle(): HdsNavigationIconItemStyle {
    const iconItemStyle: HdsNavigationIconItemStyle = {
      backgroundColor: Color.Transparent,
      iconColor: $r('app.color.on_surface'),
      textColor: $r('app.color.on_surface')
    };
    return iconItemStyle;
  }

  private buildModalContentStyle(): HdsTitleBarContentStyle {
    const contentStyle: HdsTitleBarContentStyle = {
      titleStyle: this.buildModalTitleStyle(),
      menuStyle: this.buildModalIconItemStyle()
    };
    return contentStyle;
  }

  private buildModalTitleBarStyle(includeMaskStyle: boolean): HdsNavigationTitleBarStyle {
    let backgroundStyle: HdsNavigationBackgroundStyle;
    if (includeMaskStyle) {
      backgroundStyle = {
        backgroundColor: Color.Transparent,
        maskExtraHeight: MODAL_TITLE_BAR_MASK_EXTRA_HEIGHT_VP,
        blurRadius: MODAL_TITLE_BAR_BLUR_RADIUS
      };
    } else {
      backgroundStyle = {
        backgroundColor: Color.Transparent
      };
    }
    const titleBarStyle: HdsNavigationTitleBarStyle = {
      backgroundStyle: backgroundStyle,
      contentStyle: this.buildModalContentStyle()
    };
    return titleBarStyle;
  }

  private buildModalScrollEffectOptions(): ScrollEffectOptions {
    const scrollEffectOptions: ScrollEffectOptions = {
      enableScrollEffect: true,
      scrollEffectType: ScrollEffectType.GRADIENT_BLUR,
      enableRefreshOffsetChange: true,
      blurEffectiveStartOffset: LengthMetrics.vp(MODAL_TITLE_BAR_SCROLL_EFFECT_START_OFFSET_VP),
      blurEffectiveEndOffset: LengthMetrics.vp(MODAL_TITLE_BAR_SCROLL_EFFECT_END_OFFSET_VP)
    };
    return scrollEffectOptions;
  }

  private buildModalSystemMaterialParams(): SystemMaterialParams {
    const systemMaterialParams: SystemMaterialParams = {
      materialType: hdsMaterial.MaterialType.ADAPTIVE,
      materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
    };
    return systemMaterialParams;
  }

  private buildModalTitleBar(): HdsNavigationTitleBarOptions {
    const closeIcon: HdsNavigationIconOptions = {
      icon: $r('sys.symbol.xmark'),
      label: '关闭通知',
      type: IconStyleMode.SMALL,
      action: () => {
        this.onClose();
      }
    };
    const closeMenuItem: HdsNavigationBadgeIconOptions = {
      content: closeIcon
    };
    const menuItems: Array<HdsNavigationMenuItemOptions> = [
      closeMenuItem
    ];
    const menu: HdsNavigationMenuContentOptions = {
      value: menuItems,
      maxCount: 1
    };
    const content: TitleBarContentOptions = {
      title: this.buildModalTitle(),
      menu: menu
    };
    const style: TitleBarStyleOptions = {
      scrollEffectOpts: this.buildModalScrollEffectOptions(),
      originalStyle: this.buildModalTitleBarStyle(false),
      scrollEffectStyle: this.buildModalTitleBarStyle(true),
      systemMaterialEffect: this.buildModalSystemMaterialParams(),
      thermoCtrl: true
    };
    const titleBarOptions: HdsNavigationTitleBarOptions = {
      enableComponentSafeArea: true,
      content: content,
      style: style
    };
    return titleBarOptions;
  }

  build() {
    HdsNavigation() {
      Scroll(this.modalScroller) {
        Column() {
          Row() {
            Row() {
              if (this.isMarkingAllRead) {
                LoadingProgress().width(16).height(16)
              } else {
                SymbolGlyph($r('sys.symbol.checkmark_circle'))
                  .fontSize(18)
                  .fontColor([$r('app.color.on_surface_secondary')])
              }
              Text(this.isMarkingAllRead ? '标记中' : '全部已读')
                .fontSize(14)
                .fontColor($r('app.color.on_surface_secondary'))
                .margin({ left: 6 })
            }
            .height(34)
            .padding({ left: 12, right: 12 })
            .borderRadius(17)
            .backgroundColor($r('app.color.search_background'))
            .enabled(this.notifications.length > 0 && !this.isMarkingAllRead)
            .opacity(this.notifications.length > 0 ? 1 : 0.36)
            .justifyContent(FlexAlign.Center)
            .alignItems(VerticalAlign.Center)
            .onClick(() => {
              this.markAllAsRead().catch(() => {
              });
            })

            Blank().layoutWeight(1)

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
            .padding({ left: 12, right: 8 })
            .borderRadius(17)
            .backgroundColor($r('app.color.search_background'))
            .onClick(() => {
              this.onViewAll();
            })
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 10, bottom: 8 })
          .alignItems(VerticalAlign.Center)

          if (this.isLoading && this.notifications.length === 0 && this.errorMessage.length === 0) {
            Column() {
              LoadingSpinner({ message: '' })
            }
            .width('100%')
            .height(320)
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
            .height(320)
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center)
            .onClick(() => {
              this.loadNotifications().catch(() => {
              });
            })
          } else {
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
          }
        }
        .width('100%')
        .padding({ left: 16, right: 16, bottom: 12 + WindowManager.getSystemAvoidAreaBottomVp() })
      }
      .clip(false)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.surface'))
    .titleBar(this.buildModalTitleBar())
    .titleMode(HdsNavigationTitleMode.MODAL)
    .bindToScrollable([this.modalScroller])
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
        .backgroundColor($r('app.color.divider_light'))
        .margin({ left: 62 })
    }
    .width('100%')
  }
}
