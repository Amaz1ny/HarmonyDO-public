import { Topic, Tag } from '../../models/Topic';
import { Category } from '../../models/Category';
import { TimeUtils } from '../../common/utils/TimeUtils';
import { UrlUtils } from '../../common/utils/UrlUtils';
import { AppSettingsService } from '../../services/storage/AppSettingsService';
import { SmartAvatar } from './SmartAvatar';
import { TagBadge } from './TopicBadges';

/**
 * 话题卡片 - 标准样式
 *
 * 精确复刻安卓版布局：
 * - 左侧：楼主头像（圆形 34px）
 * - 右侧上行：标题文字（最多2行） + 回复数（右上角）
 * - 右侧下行：分类标签+tag标签（左） + 点赞数·时间（右）
 */
@ComponentV2
export struct TopicCard {
  @Param topic: Topic = new Topic();
  @Param category: Category | null = null;
  @Param opAvatarUrl: string = '';
  @Param isHighlighted: boolean = false;
  @Param enableLongPress: boolean = true;
  @Event onCardClick: (topic: Topic) => void = () => {};
  @Event onCardLongPress: (topic: Topic) => void = () => {};

  build() {
    Row() {
      // 左侧：楼主头像
      SmartAvatar({
        avatarUrl: this.opAvatarUrl,
        avatarSize: 34,
        avatarRadius: 17,
        fallbackText: this.topic.lastPosterUsername !== null ? this.topic.lastPosterUsername : ''
      })
      .margin({ top: 2 })

      // 右侧内容
      Column() {
        // 第1行：标题 + 回复数
        Row() {
          // 标题（含状态图标）
          Row() {
            if (this.topic.closed) {
              SymbolGlyph($r('sys.symbol.lock'))
                .fontSize(13)
                .fontColor([$r('app.color.on_surface_tertiary')])
                .margin({ right: 3 })
            }
            if (this.topic.hasAcceptedAnswer) {
              SymbolGlyph($r('sys.symbol.checkmark_square_fill'))
                .fontSize(13)
                .fontColor([$r('app.color.success')])
                .margin({ right: 3 })
            } else if (this.topic.canHaveAnswer) {
              SymbolGlyph($r('sys.symbol.square'))
                .fontSize(13)
                .fontColor([$r('app.color.on_surface_tertiary')])
                .margin({ right: 3 })
            }
            Text(this.topic.title)
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.isUnread() ? $r('app.color.on_surface') : $r('app.color.on_surface_secondary'))
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
              .lineHeight(20)

            // 未读蓝点（仅 unseen）
            if (this.topic.unseen) {
              Circle()
                .width(8)
                .height(8)
                .fill(AppSettingsService.getInstance().getPrimaryColor())
                .margin({ left: 6, top: 5 })
            }
          }
          .layoutWeight(1)
          .alignItems(VerticalAlign.Top)

          // 回复数（右上角）
          if (this.topic.unread > 0) {
            // 未读数徽标
            Row() {
              Text(`${this.topic.unread}`)
                .fontSize(10)
                .fontWeight(FontWeight.Bold)
                .fontColor(AppSettingsService.getInstance().getPrimaryColor())
            }
            .padding({ left: 8, right: 8, top: 3, bottom: 3 })
            .backgroundColor($r('app.color.badge_background_light'))
            .borderRadius(10)
            .margin({ left: 8, top: 2 })
          } else if (this.getEffectiveReplyCount() > 0) {
            Row() {
              SymbolGlyph($r('sys.symbol.message'))
                .fontSize(12)
                .fontColor([this.getReplyHeatColor()])
              Text(` ${this.formatCount(this.getEffectiveReplyCount())}`)
                .fontSize($r('app.float.text_size_small'))
                .fontColor(this.getReplyHeatColor())
                .fontWeight(this.isHotReply() ? FontWeight.Bold : FontWeight.Normal)
            }
            .margin({ left: 8, top: 2 })
          }
        }
        .width('100%')
        .alignItems(VerticalAlign.Top)

        // 第2行：分类+标签（左） + 点赞·时间（右）
        Row() {
          // 左侧：分类+标签
          Flex({ wrap: FlexWrap.Wrap }) {
            // 分类标签
            if (this.category !== null) {
              Row() {
                // 分类图标：logo → lock → dot（不再做 sys.symbol 近似映射，避免与安卓不一致）
                if (this.categoryHasLogo()) {
                  Image(UrlUtils.resolveUrl((this.category as Category).uploadedLogo))
                    .width(12)
                    .height(12)
                    .objectFit(ImageFit.Contain)
                    .margin({ right: 4 })
                } else if ((this.category as Category).readRestricted) {
                  SymbolGlyph($r('sys.symbol.lock'))
                    .fontSize(11)
                    .fontColor([this.getCategoryColorValue()])
                    .margin({ right: 4 })
                } else {
                  Circle()
                    .width(8)
                    .height(8)
                    .fill(this.getCategoryColorValue())
                    .margin({ right: 4 })
                }

                Text((this.category as Category).name)
                  .fontSize($r('app.float.font_small'))
                  .fontColor(this.getCategoryColorValue())
                  .fontWeight(FontWeight.Medium)
              }
              .padding({ left: 6, right: 8, top: 3, bottom: 3 })
              .backgroundColor(this.hexWithAlpha(this.getCategoryColorValue(), 0.1))
              .borderRadius($r('app.float.tag_radius'))
              .alignItems(VerticalAlign.Center)
              .margin({ right: 6, bottom: 4 })
            }

            // Tag 标签
            ForEach(this.topic.tags, (tag: Tag) => {
              if (tag.name.trim().length > 0) {
                TagBadge({ name: tag.name })
                  .margin({ right: 6, bottom: 4 })
              }
            })
          }
          .layoutWeight(1)

          // 右侧：点赞 + 时间
          Row() {
            if (this.topic.likeCount > 0) {
              SymbolGlyph($r('sys.symbol.heart'))
                .fontSize(12)
                .fontColor([$r('app.color.on_surface_tertiary')])
              Text(` ${this.formatCount(this.topic.likeCount)}`)
                .fontSize($r('app.float.font_small'))
                .fontColor($r('app.color.on_surface_tertiary'))
              Text(' · ')
                .fontSize($r('app.float.font_small'))
                .fontColor($r('app.color.divider_light'))
            }
            Text(TimeUtils.formatRelativeTime(this.topic.lastPostedAt))
              .fontSize($r('app.float.font_small'))
              .fontColor($r('app.color.on_surface_tertiary'))
          }
          .alignItems(VerticalAlign.Center)
        }
        .width('100%')
        .margin({ top: 6 })
        .alignItems(VerticalAlign.Top)
      }
      .layoutWeight(1)
      .margin({ left: 10 })
    }
    .width('100%')
    .padding({ left: 12, right: 14, top: 10, bottom: 10 })
    .alignItems(VerticalAlign.Top)
    .backgroundColor(this.isHighlighted ? $r('app.color.badge_background_light') : $r('app.color.card_background'))
    .borderRadius($r('app.float.card_radius'))
    .margin({ bottom: 8 })
    .opacity(this.isFullyRead() ? 0.5 : 1)
    .animation({ duration: 220, curve: Curve.EaseOut })
    .gesture(
      GestureGroup(GestureMode.Exclusive,
        TapGesture()
          .onAction(() => {
            this.onCardClick(this.topic);
          }),
        LongPressGesture({ repeat: false, duration: 400 })
          .onAction(() => {
            if (this.enableLongPress) {
              this.onCardLongPress(this.topic);
            }
          })
      )
    )
  }

  private isUnread(): boolean {
    return this.topic.unseen || this.topic.unread > 0;
  }

  private isFullyRead(): boolean {
    return !this.topic.unseen && this.topic.unread === 0 && this.topic.lastReadPostNumber > 0;
  }

  private getEffectiveReplyCount(): number {
    const effectivePostsCount: number = Math.max(this.topic.postsCount, this.topic.highestPostNumber, this.topic.replyCount + 1);
    return Math.max(this.topic.replyCount, Math.max(0, effectivePostsCount - 1));
  }

  /**
   * 格式化数量
   */
  private formatCount(count: number): string {
    if (count >= 10000) {
      return `${(count / 10000).toFixed(1)}w`;
    }
    if (count >= 1000) {
      return `${(count / 1000).toFixed(1)}k`;
    }
    return count.toString();
  }

  /**
   * 是否是热门回复
   */
  private isHotReply(): boolean {
    const posts = Math.max(this.topic.postsCount, this.topic.highestPostNumber, this.topic.replyCount + 1);
    const likes = this.topic.likeCount;
    if (posts < 10) return false;
    const ratio: number = likes / posts;
    return ratio > 0.5;
  }

  /**
   * 回复数热度颜色
   */
  private getReplyHeatColor(): Resource {
    const posts = Math.max(this.topic.postsCount, this.topic.highestPostNumber, this.topic.replyCount + 1);
    const likes = this.topic.likeCount;
    if (posts < 10) return $r('app.color.on_surface_tertiary');
    const ratio: number = likes / posts;
    if (ratio > 2.0) return $r('app.color.heat_high');
    if (ratio > 1.0) return $r('app.color.heat_med');
    if (ratio > 0.5) return $r('app.color.heat_low');
    return $r('app.color.on_surface_tertiary');
  }

  /**
   * 颜色添加透明度
   */
  private hexWithAlpha(hex: string, alpha: number): string {
    let colorHex: string = hex;
    if (colorHex.startsWith('#')) {
      colorHex = colorHex.substring(1);
    }
    const alphaHex: string = Math.round(alpha * 255).toString(16).padStart(2, '0');
    return `#${alphaHex}${colorHex}`;
  }

  private normalizeHex(hex: string): string {
    if (hex.length === 0) return '#999999';
    if (hex.startsWith('#')) return hex;
    return `#${hex}`;
  }

  private getCategoryColorValue(): string {
    if (this.category === null) return '#999999';
    return this.normalizeHex((this.category as Category).color);
  }

  private categoryHasLogo(): boolean {
    if (this.category === null) return false;
    const logo: string | null = (this.category as Category).uploadedLogo;
    return logo !== null && (logo as string).length > 0;
  }
}

/**
 * 紧凑型话题卡片 - 用于置顶话题
 *
 * 单行布局：📌 + 分类圆点 + 标题 + 回复数
 */
@ComponentV2
export struct CompactTopicCard {
  @Param topic: Topic = new Topic();
  @Param category: Category | null = null;
  @Param isHighlighted: boolean = false;
  @Param enableLongPress: boolean = true;
  @Event onCardClick: (topic: Topic) => void = () => {};
  @Event onCardLongPress: (topic: Topic) => void = () => {};

  build() {
    Row() {
      // 置顶图标
      SymbolGlyph($r('sys.symbol.pin'))
        .fontSize(14)
        .fontColor([AppSettingsService.getInstance().getPrimaryColor()])
        .margin({ right: 8 })

      // 分类图标：logo → lock → dot（不再做 sys.symbol 近似映射，避免与安卓不一致）
      if (this.category !== null) {
        if (
          (this.category as Category).uploadedLogo !== null
          && ((this.category as Category).uploadedLogo as string).length > 0
        ) {
          Image(UrlUtils.resolveUrl((this.category as Category).uploadedLogo))
            .width(12)
            .height(12)
            .objectFit(ImageFit.Contain)
            .margin({ right: 8 })
        } else if ((this.category as Category).readRestricted) {
          SymbolGlyph($r('sys.symbol.lock'))
            .fontSize(12)
            .fontColor([this.normalizeHex((this.category as Category).color)])
            .margin({ right: 8 })
        } else {
          Circle()
            .width(6)
            .height(6)
            .fill(this.normalizeHex((this.category as Category).color))
            .margin({ right: 8 })
        }
      }

      // 关闭图标
      if (this.topic.closed) {
        SymbolGlyph($r('sys.symbol.lock'))
          .fontSize(11)
          .fontColor([$r('app.color.on_surface_tertiary')])
          .margin({ right: 3 })
      }

      if (this.topic.hasAcceptedAnswer) {
        SymbolGlyph($r('sys.symbol.checkmark_square_fill'))
          .fontSize(11)
          .fontColor([$r('app.color.success')])
          .margin({ right: 3 })
      } else if (this.topic.canHaveAnswer) {
        SymbolGlyph($r('sys.symbol.square'))
          .fontSize(11)
          .fontColor([$r('app.color.on_surface_tertiary')])
          .margin({ right: 3 })
      }

      // 标题
      Text(this.topic.title)
        .fontSize(13)
        .fontColor($r('app.color.on_surface'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)

      // 未读数优先，否则显示回复数
      if (this.topic.unread > 0) {
        Row() {
          Text(`${this.topic.unread}`)
            .fontSize(9)
            .fontWeight(FontWeight.Bold)
            .fontColor(AppSettingsService.getInstance().getPrimaryColor())
        }
        .padding({ left: 6, right: 6, top: 2, bottom: 2 })
        .backgroundColor($r('app.color.badge_background_light'))
        .borderRadius(10)
        .margin({ left: 8 })
      } else if (this.getEffectiveReplyCount() > 0) {
        Row() {
          SymbolGlyph($r('sys.symbol.message'))
            .fontSize(11)
            .fontColor([$r('app.color.on_surface_tertiary')])
          Text(` ${this.getEffectiveReplyCount()}`)
            .fontSize($r('app.float.font_small'))
            .fontColor($r('app.color.on_surface_tertiary'))
        }
        .margin({ left: 8 })
      }
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 10, bottom: 10 })
    .alignItems(VerticalAlign.Center)
    .backgroundColor(this.isHighlighted ? $r('app.color.badge_background_light') : $r('app.color.search_bar_background'))
    .borderRadius($r('app.float.card_radius'))
    .margin({ bottom: 6 })
    .opacity(!this.topic.unseen && this.topic.unread === 0 && this.topic.lastReadPostNumber > 0 ? 0.5 : 1)
    .animation({ duration: 220, curve: Curve.EaseOut })
    .gesture(
      GestureGroup(GestureMode.Exclusive,
        TapGesture()
          .onAction(() => {
            this.onCardClick(this.topic);
          }),
        LongPressGesture({ repeat: false, duration: 400 })
          .onAction(() => {
            if (this.enableLongPress) {
              this.onCardLongPress(this.topic);
            }
          })
      )
    )
  }

  private normalizeHex(hex: string): string {
    if (hex.length === 0) return '#999999';
    if (hex.startsWith('#')) return hex;
    return `#${hex}`;
  }

  private getEffectiveReplyCount(): number {
    const effectivePostsCount: number = Math.max(this.topic.postsCount, this.topic.highestPostNumber, this.topic.replyCount + 1);
    return Math.max(this.topic.replyCount, Math.max(0, effectivePostsCount - 1));
  }
}
