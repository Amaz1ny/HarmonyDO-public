import { SearchPost, SearchTopic } from '../../../models/SearchResult';
import { Category } from '../../../models/Category';
import { SmartAvatar } from '../SmartAvatar';
import { TimeUtils } from '../../../common/utils/TimeUtils';
import { CategoryIcon } from '../CategoryIcon';
import { TagBadge } from '../TopicBadges';
import { ThemeManager } from '../../../common/theme/ThemeManager';

@ComponentV2
export struct SearchPostCard {
  @Param post: SearchPost = new SearchPost();
  @Param category: Category | null = null;
  @Param parentCategory: Category | null = null;
  @Param accentSurfaceColorHex: string = ThemeManager.getCurrentAccentSurfaceColorHex();
  @Param accentSurfaceVariantColorHex: string = ThemeManager.getCurrentAccentSurfaceVariantColorHex();
  @Param themeRevision: number = 0;
  @Event onTap: () => void = () => {};

  build() {
    Row() {
      SmartAvatar({
        avatarUrl: this.post.getAvatarUrl(88),
        avatarSize: 40,
        avatarRadius: 20,
        fallbackText: this.post.username,
        bgColor: '#E8EAF0'
      })
      .margin({ top: 2 })

      Column() {
        Row() {
          Row() {
            if (this.getTopic() !== null && (this.getTopic() as SearchTopic).closed) {
              SymbolGlyph($r('sys.symbol.lock'))
                .fontSize(14)
                .fontColor([$r('app.color.on_surface_tertiary')])
                .margin({ right: 4, top: 2 })
            }

            if (this.getTopic() !== null && (this.getTopic() as SearchTopic).archived) {
              SymbolGlyph($r('sys.symbol.archivebox'))
                .fontSize(14)
                .fontColor([$r('app.color.on_surface_tertiary')])
                .margin({ right: 4, top: 2 })
            }

            Text(this.getTopicTitle())
              .fontSize($r('app.float.text_size_large'))
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.on_surface'))
              .maxLines(2)
              .lineHeight(24)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
          }
          .layoutWeight(1)
          .alignItems(VerticalAlign.Top)

          if (this.post.postNumber > 1) {
            Row() {
              Text(`#${this.post.postNumber}`)
                .fontSize($r('app.float.font_micro'))
                .fontColor($r('app.color.on_surface_secondary'))
                .fontWeight(FontWeight.Medium)
            }
            .padding({ left: 6, right: 6, top: 3, bottom: 3 })
            .backgroundColor(this.accentSurfaceVariantColorHex)
            .borderRadius($r('app.float.border_radius_large'))
            .margin({ left: 8, top: 2 })
          }
        }
        .width('100%')
        .alignItems(VerticalAlign.Top)

        if (this.getBlurbText().length > 0) {
          Text(this.getBlurbText())
            .fontSize($r('app.float.text_size_normal'))
            .fontColor($r('app.color.on_surface_secondary'))
            .lineHeight(22)
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .margin({ top: 6 })
        }

        Row() {
          Flex({ wrap: FlexWrap.Wrap }) {
            if (this.category !== null) {
              this.CategoryBadge(this.category as Category)
            }

            if (this.getTopic() !== null) {
              ForEach(this.getDisplayTags(this.getTopic() as SearchTopic), (tag: string) => {
                TagBadge({
                  name: tag,
                  fontSize: $r('app.float.font_small'),
                  iconSize: 11,
                  paddingH: 7,
                  paddingV: 4,
                  radius: $r('app.float.border_radius_small'),
                  bgColor: this.accentSurfaceVariantColorHex
                })
                  .margin({ right: 6, bottom: 6 })
              }, (tag: string) => tag)
            }
          }
          .layoutWeight(1)

          Row() {
            if (this.post.likeCount > 0) {
              SymbolGlyph($r('sys.symbol.heart'))
                .fontSize(13)
                .fontColor([$r('app.color.on_surface_tertiary')])
              Text(` ${this.post.likeCount}`)
                .fontSize($r('app.float.font_small'))
                .fontColor($r('app.color.on_surface_tertiary'))
              Text(' · ')
                .fontSize($r('app.float.font_small'))
                .fontColor($r('app.color.on_surface_tertiary'))
            }

            Text(TimeUtils.formatRelativeTime(this.post.createdAt))
              .fontSize($r('app.float.font_small'))
              .fontColor($r('app.color.on_surface_tertiary'))
          }
          .alignItems(VerticalAlign.Center)
          .margin({ top: 2 })
        }
        .width('100%')
        .margin({ top: 10 })
        .alignItems(VerticalAlign.Top)
      }
      .layoutWeight(1)
      .margin({ left: 12 })
    }
    .width('100%')
    .padding({ left: 14, right: 14, top: 14, bottom: 14 })
    .alignItems(VerticalAlign.Top)
    .backgroundColor(this.accentSurfaceColorHex)
    .borderRadius(18)
    .shadow({ radius: 10, color: '#0A000000', offsetX: 0, offsetY: 4 })
    .onClick(() => {
      this.onTap();
    })
  }

  private getTopic(): SearchTopic | null {
    if (this.post.topic !== null) {
      return this.post.topic as SearchTopic;
    }
    return null;
  }

  @Builder
  private CategoryBadge(category: Category) {
    Row() {
      CategoryIcon({
        category: category,
        parent: this.parentCategory,
        iconSize: 12,
        color: this.getCategoryColorValue(category)
      })
      .margin({ right: 4 })

      Text(category.name)
        .fontSize($r('app.float.font_small'))
        .fontWeight(FontWeight.Medium)
        .fontColor(this.getCategoryColorValue(category))
    }
    .padding({ left: 7, right: 8, top: 4, bottom: 4 })
    .backgroundColor(this.getCategoryBackgroundColor(category))
    .borderRadius($r('app.float.border_radius_small'))
    .margin({ right: 6, bottom: 6 })
    .alignItems(VerticalAlign.Center)
  }

  private getTopicTitle(): string {
    if (this.post.topicTitleHeadline !== null && (this.post.topicTitleHeadline as string).length > 0) {
      return this.stripHtml(this.post.topicTitleHeadline as string);
    }
    if (this.getTopic() !== null) {
      return ((this.getTopic() as SearchTopic).title);
    }
    return '';
  }

  private getBlurbText(): string {
    return this.stripHtml(this.post.blurb);
  }

  private stripHtml(input: string): string {
    if (input.length === 0) {
      return input;
    }
    try {
      return input.replace(/<[^>]+>/g, '').replace(/\s+/g, ' ').trim();
    } catch (_) {
      return input;
    }
  }

  private getDisplayTags(topic: SearchTopic): string[] {
    const out: string[] = [];
    for (let i: number = 0; i < topic.tags.length; i++) {
      const tag: string = topic.tags[i];
      if (tag.trim().length === 0) {
        continue;
      }
      out.push(tag);
      if (out.length >= 3) {
        break;
      }
    }
    return out;
  }

  private getCategoryColorValue(category: Category): string {
    const color: string = category.colorValue;
    if (color.length > 1) {
      return color;
    }
    return '#999999';
  }

  private getCategoryBackgroundColor(category: Category): string {
    const color: string = this.getCategoryColorValue(category);
    return this.hexWithAlpha(color, 0.12);
  }

  private hexWithAlpha(hex: string, alpha: number): string {
    const raw: string = hex.startsWith('#') ? hex.substring(1) : hex;
    if (raw.length !== 6) {
      return '#0F000000';
    }
    const safeAlpha: number = Math.max(0, Math.min(255, Math.round(alpha * 255)));
    return `#${safeAlpha.toString(16).padStart(2, '0')}${raw}`.toUpperCase();
  }
}
