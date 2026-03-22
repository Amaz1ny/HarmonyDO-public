import { hilog } from '@kit.PerformanceAnalysisKit';
import { Category } from '../../models/Category';
import { Post } from '../../models/Post';
import { Topic, Tag } from '../../models/Topic';
import { ExternalLinkService } from '../../common/utils/ExternalLinkService';
import { RouterManager } from '../../common/utils/RouterManager';
import { ShareUtils } from '../../common/utils/ShareUtils';
import { SystemShareService } from '../../common/utils/SystemShareService';
import { ClipboardService } from '../../common/utils/ClipboardService';
import { ToastService } from '../../common/utils/ToastService';
import { TimeUtils } from '../../common/utils/TimeUtils';
import { UrlUtils } from '../../common/utils/UrlUtils';
import { ApiClient } from '../../services/network/ApiClient';
import { SmartAvatar } from './SmartAvatar';
import { TagBadge } from './TopicBadges';
import { CategoryIcon } from './CategoryIcon';
import { PostRichContent } from './PostRichContent';

const TAG: string = 'TopicPreviewDialog';

function decodeHtmlEntities(text: string): string {
  let result: string = text;
  result = result.replace(/&nbsp;/g, ' ');
  result = result.replace(/&lt;/g, '<');
  result = result.replace(/&gt;/g, '>');
  result = result.replace(/&amp;/g, '&');
  result = result.replace(/&quot;/g, '"');
  result = result.replace(/&#39;/g, '\'');
  result = result.replace(/&hellip;/g, '...');
  return result;
}

function stripHtmlKeepLines(html: string): string {
  if (html.length === 0) return '';
  let result: string = html;
  result = result.replace(/<(br|hr)\s*\/?>/gi, '\n');
  result = result.replace(/<\/(p|div|li|blockquote|h[1-6]|tr|pre)>/gi, '\n');
  result = result.replace(/<[^>]*>/g, '');
  result = decodeHtmlEntities(result);
  result = result.replace(/\r/g, '');
  result = result.replace(/[ \t\u00A0]+/g, ' ');
  result = result.replace(/\n{3,}/g, '\n\n');
  return result.trim();
}

function normalizePreviewText(text: string): string {
  const raw: string = text !== undefined && text !== null ? text.trim() : '';
  if (raw.length === 0) return '';
  const lines: string[] = raw.split('\n');
  const out: string[] = [];
  let previousBlank: boolean = true;
  for (let i = 0; i < lines.length; i++) {
    const line: string = lines[i].replace(/[ \t\u00A0]+/g, ' ').trim();
    if (line.length === 0) {
      if (!previousBlank && out.length > 0) {
        out.push('');
      }
      previousBlank = true;
      continue;
    }
    out.push(line);
    previousBlank = false;
  }
  return out.join('\n').trim();
}

@ComponentV2
export struct TopicPreviewDialog {
  @Param topic: Topic = new Topic();
  @Param category: Category | null = null;
  @Param parentCategory: Category | null = null;
  @Param secondaryActionLabel: string = '';
  @Event onClose: () => void = () => {};
  @Event onOpen: (topic: Topic) => void = () => {};
  @Event onSecondaryAction: (topic: Topic) => void = (_: Topic) => {};

  @Local private previewCookedHtml: string = '';
  @Local private previewFallbackText: string = '';
  @Local private previewPost: Post | null = null;
  @Local private isLoading: boolean = true;

  aboutToAppear(): void {
    this.previewCookedHtml = '';
    this.previewFallbackText = '';
    this.previewPost = null;
    this.isLoading = true;
    this.loadPreviewContent().catch((err: Object) => {
      hilog.warn(0x0000, TAG, 'loadPreviewContent failed: %{public}s', JSON.stringify(err));
      this.previewFallbackText = this.getFallbackExcerpt();
      this.isLoading = false;
    });
  }

  build() {
    Column() {
      Row() {
      }
      .width('100%')
      .height(4)
      .linearGradient({
        angle: 0,
        colors: [['#E9D5FF', 0], ['#DBEAFE', 0.6], ['#D1FAE5', 1]]
      })

      Scroll() {
        Column() {
          this.TitleSection()
          this.AuthorSection()

          if (this.category !== null || this.topic.tags.length > 0) {
            this.CategoryAndTagsSection()
          }

          this.ContentSection()

          if (this.hasParticipants()) {
            this.ParticipantsSection()
          }

          this.StatsSection()
        }
      }
      .width('100%')
      .layoutWeight(1)
      .padding({ left: 20, right: 20, top: 18, bottom: 18 })

      this.ActionBar()
    }
    .width('92%')
    .height('72%')
    .constraintSize({ maxWidth: 560 })
    .backgroundColor($r('app.color.surface'))
    .borderRadius(24)
    .clip(true)
    .shadow({ radius: 18, color: '#26000000', offsetX: 0, offsetY: 10 })
  }

  @Builder
  private TitleSection() {
    Row() {
      if (this.topic.closed) {
        SymbolGlyph($r('sys.symbol.lock'))
          .fontSize(18)
          .fontColor([$r('app.color.on_surface_tertiary')])
          .margin({ right: 6, top: 4 })
      }
      if (this.topic.pinned) {
        SymbolGlyph($r('sys.symbol.pin'))
          .fontSize(18)
          .fontColor([$r('app.color.primary')])
          .margin({ right: 6, top: 4 })
      }
      if (this.topic.hasAcceptedAnswer) {
        SymbolGlyph($r('sys.symbol.checkmark_square_fill'))
          .fontSize(18)
          .fontColor([$r('app.color.success')])
          .margin({ right: 6, top: 4 })
      }
      Text(this.topic.title)
        .layoutWeight(1)
        .fontSize(22)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.on_surface'))
        .lineHeight(30)
        .maxLines(4)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
  }

  @Builder
  private AuthorSection() {
    Row() {
      SmartAvatar({
        avatarUrl: this.getAuthorAvatarUrl(),
        avatarSize: 30,
        avatarRadius: 15,
        fallbackText: this.getAuthorName(),
        bgColor: '#E8EAF0'
      })

      Text(this.getAuthorName().length > 0 ? this.getAuthorName() : '未知用户')
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.on_surface'))
        .margin({ left: 10 })

      if (this.topic.createdAt !== null) {
        Text(` · 创建于 ${TimeUtils.formatRelativeTime(this.topic.createdAt)}`)
          .fontSize(13)
          .fontColor($r('app.color.on_surface_tertiary'))
          .margin({ left: 4, top: 1 })
      }
    }
    .width('100%')
    .margin({ top: 14 })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private CategoryAndTagsSection() {
    Flex({ wrap: FlexWrap.Wrap }) {
      if (this.category !== null) {
        Row() {
          CategoryIcon({
            category: this.category,
            parent: this.parentCategory,
            iconSize: 12,
            color: this.getCategoryColorValue(),
            preferImage: false
          })
          .margin({ right: 6 })

          Text((this.category as Category).name)
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.getCategoryColorValue())
        }
        .padding({ left: 10, right: 10, top: 6, bottom: 6 })
        .backgroundColor(this.hexWithAlpha(this.getCategoryColorValue(), 0.12))
        .border({ width: 1, color: this.hexWithAlpha(this.getCategoryColorValue(), 0.24) })
        .borderRadius(10)
        .margin({ right: 8, bottom: 8 })
      }

      ForEach(this.topic.tags, (tag: Tag) => {
        if (tag.name.trim().length > 0) {
          TagBadge({ name: tag.name })
            .margin({ right: 8, bottom: 8 })
        }
      }, (tag: Tag) => tag.name)
    }
    .width('100%')
    .margin({ top: 14 })
  }

  @Builder
  private ContentSection() {
    if (this.isLoading) {
      Row() {
        LoadingProgress()
          .width(22)
          .height(22)
        Text('正在加载预览...')
          .fontSize(13)
          .fontColor($r('app.color.on_surface_tertiary'))
          .margin({ left: 10 })
      }
      .width('100%')
      .padding({ top: 18, bottom: 18 })
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
    } else if (this.previewCookedHtml.length > 0 && this.previewPost !== null) {
      Column() {
        PostRichContent({
          cookedHtml: this.previewCookedHtml,
          post: this.previewPost as Post,
          dense: true,
          onOpenLink: (url: string) => {
            this.handlePreviewLinkClick(url);
          },
          onOpenImagePreview: (urls: string[], initialIndex: number) => {
            this.openPreviewImage(urls, initialIndex);
          }
        })
      }
      .width('100%')
      .margin({ top: 16 })
    } else if (this.previewFallbackText.length > 0) {
      Text(this.previewFallbackText)
        .width('100%')
        .fontSize(14)
        .fontColor($r('app.color.on_surface'))
        .lineHeight(22)
        .margin({ top: 16 })
    }
  }

  @Builder
  private ParticipantsSection() {
    Row() {
      Text('参与者')
        .fontSize(13)
        .fontColor($r('app.color.on_surface_tertiary'))
        .margin({ right: 12 })

      Row() {
        ForEach(this.getParticipantIndexes(), (index: number) => {
          SmartAvatar({
            avatarUrl: this.getParticipantAvatarUrl(index),
            avatarSize: 28,
            avatarRadius: 14,
            fallbackText: this.getParticipantFallback(index),
            bgColor: '#E8EAF0'
          })
          .margin({ left: index === 0 ? 0 : -6 })
        }, (index: number) => `${index}`)
      }
      .layoutWeight(1)
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .margin({ top: 18 })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private StatsSection() {
    Column() {
      Row() {
        this.StatItem($r('sys.symbol.message'), `${this.formatCount(this.getEffectiveReplyCount())} 条回复`)
        this.StatItem($r('sys.symbol.heart'), `${this.formatCount(this.topic.likeCount)} 点赞`)
      }
      .width('100%')

      Row() {
        this.StatItem($r('sys.symbol.eye'), `${this.formatCount(this.topic.views)} 浏览`)
        this.StatItem(
          $r('sys.symbol.clock'),
          this.topic.lastPostedAt !== null ? `最后回复 ${TimeUtils.formatRelativeTime(this.topic.lastPostedAt)}` : '最后回复未知'
        )
      }
      .width('100%')
      .margin({ top: 10 })
    }
    .width('100%')
    .margin({ top: 18 })
  }

  @Builder
  private StatItem(symbol: Resource, text: string) {
    Row() {
      SymbolGlyph(symbol)
        .fontSize(16)
        .fontColor([$r('app.color.on_surface_tertiary')])
      Text(text)
        .fontSize(13)
        .fontColor($r('app.color.on_surface_tertiary'))
        .margin({ left: 6 })
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .layoutWeight(1)
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private ActionBar() {
    Row() {
      Button('关闭')
        .type(ButtonType.Capsule)
        .fontSize(14)
        .height(42)
        .layoutWeight(1)
        .backgroundColor($r('app.color.surface'))
        .fontColor($r('app.color.on_surface_secondary'))
        .onClick(() => {
          this.onClose();
        })

      Blank().width(10)

      Button() {
        SymbolGlyph($r('sys.symbol.share'))
          .fontSize(18)
          .fontColor([$r('app.color.on_surface_secondary')])
      }
      .type(ButtonType.Capsule)
      .width(46)
      .height(42)
      .backgroundColor($r('app.color.surface_variant'))
        .onClick(() => {
          this.shareTopic().catch((_: Object) => {
          });
        })

      if (this.secondaryActionLabel.trim().length > 0) {
        Blank().width(10)

        Button(this.secondaryActionLabel)
          .type(ButtonType.Capsule)
          .fontSize(14)
          .height(42)
          .backgroundColor($r('app.color.surface_variant'))
          .fontColor($r('app.color.primary'))
          .padding({ left: 16, right: 16 })
          .onClick(() => {
            this.onSecondaryAction(this.topic);
          })
      }

      Blank().width(10)

      Button('查看详情')
        .type(ButtonType.Capsule)
        .fontSize(14)
        .height(42)
        .backgroundColor($r('app.color.primary'))
        .fontColor(Color.White)
        .padding({ left: 18, right: 18 })
        .onClick(() => {
          this.onOpen(this.topic);
        })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 14, bottom: 14 })
    .backgroundColor($r('app.color.surface'))
    .border({
      width: { top: 1 },
      color: { top: $r('app.color.divider_light') }
    })
    .alignItems(VerticalAlign.Center)
  }

  private async loadPreviewContent(): Promise<void> {
    if (this.topic.id <= 0) {
      this.previewFallbackText = this.getFallbackExcerpt();
      this.isLoading = false;
      return;
    }

    try {
      const raw: string = await ApiClient.getInstance().getTopicDetail(this.topic.id);
      const firstPost: Post | null = this.extractFirstPost(raw);
      if (firstPost !== null && firstPost.cooked.trim().length > 0) {
        this.previewPost = firstPost;
        this.previewCookedHtml = firstPost.cooked;
      }
    } catch (err) {
      hilog.warn(0x0000, TAG, 'getTopicDetail failed: %{public}s', JSON.stringify(err));
    } finally {
      if (this.previewCookedHtml.length === 0) {
        this.previewFallbackText = this.getFallbackExcerpt();
      }
      this.isLoading = false;
    }
  }

  private extractFirstPost(raw: string): Post | null {
    if (raw.trim().length === 0) return null;
    const json: Record<string, Object> = JSON.parse(raw) as Record<string, Object>;
    const postStreamVal = json['post_stream'];
    if (postStreamVal === undefined || postStreamVal === null || typeof postStreamVal !== 'object') {
      return null;
    }
    const postStreamObj: Record<string, Object> = postStreamVal as Record<string, Object>;
    const postsVal = postStreamObj['posts'];
    if (postsVal === undefined || postsVal === null || !Array.isArray(postsVal)) {
      return null;
    }
    const arr: Object[] = postsVal as Object[];
    for (let i = 0; i < arr.length; i++) {
      const item: Object = arr[i];
      if (item === null || item === undefined || typeof item !== 'object') continue;
      const postObj: Record<string, Object> = item as Record<string, Object>;
      const postNumberVal = postObj['post_number'];
      const isFirst: boolean = postNumberVal !== undefined && postNumberVal !== null ? Number(postNumberVal.toString()) === 1 : i === 0;
      if (!isFirst) continue;
      return Post.fromJson(postObj);
    }
    return null;
  }

  private getFallbackExcerpt(): string {
    const raw: string = this.topic.excerpt !== null ? (this.topic.excerpt as string) : '';
    return normalizePreviewText(stripHtmlKeepLines(raw));
  }

  private getAuthorName(): string {
    if (this.topic.posters.length > 0 && this.topic.posters[0].user !== null) {
      return this.topic.posters[0].user!.username;
    }
    if (this.topic.lastPosterUsername !== null) {
      return (this.topic.lastPosterUsername as string).trim();
    }
    return '';
  }

  private getAuthorAvatarUrl(): string {
    if (this.topic.posters.length > 0 && this.topic.posters[0].user !== null) {
      return UrlUtils.getAvatarUrl(this.topic.posters[0].user!.avatarTemplate, 56);
    }
    return '';
  }

  private hasParticipants(): boolean {
    for (let i = 0; i < this.topic.posters.length && i < 5; i++) {
      if (this.topic.posters[i].user !== null) {
        return true;
      }
    }
    return false;
  }

  private getParticipantIndexes(): number[] {
    const out: number[] = [];
    for (let i = 0; i < this.topic.posters.length && i < 5; i++) {
      if (this.topic.posters[i].user !== null) {
        out.push(i);
      }
    }
    return out;
  }

  private getParticipantAvatarUrl(index: number): string {
    if (index < 0 || index >= this.topic.posters.length) return '';
    if (this.topic.posters[index].user === null) return '';
    return UrlUtils.getAvatarUrl(this.topic.posters[index].user!.avatarTemplate, 56);
  }

  private getParticipantFallback(index: number): string {
    if (index < 0 || index >= this.topic.posters.length) return '';
    if (this.topic.posters[index].user === null) return '';
    return this.topic.posters[index].user!.username;
  }

  private getEffectiveReplyCount(): number {
    const effectivePostsCount: number = Math.max(this.topic.postsCount, this.topic.highestPostNumber, this.topic.replyCount + 1);
    return Math.max(this.topic.replyCount, Math.max(0, effectivePostsCount - 1));
  }

  private formatCount(count: number): string {
    if (count >= 10000) return `${(count / 10000).toFixed(1)}w`;
    if (count >= 1000) return `${(count / 1000).toFixed(1)}k`;
    return `${count}`;
  }

  private normalizeHex(hex: string): string {
    const raw: string = hex !== undefined && hex !== null ? hex.trim() : '';
    if (raw.length === 0) return '#999999';
    if (raw.startsWith('#')) return raw;
    return `#${raw}`;
  }

  private getCategoryColorValue(): string {
    if (this.category === null) return '#999999';
    return this.normalizeHex((this.category as Category).color);
  }

  private hexWithAlpha(hex: string, alpha: number): string {
    let raw: string = this.normalizeHex(hex);
    if (raw.startsWith('#')) {
      raw = raw.substring(1);
    }
    const alphaHex: string = Math.max(0, Math.min(255, Math.round(alpha * 255))).toString(16).padStart(2, '0');
    return `#${alphaHex}${raw}`;
  }

  private getTopicShareUrl(): string {
    const slug: string = this.topic.slug.trim().length > 0 ? this.topic.slug.trim() : 'topic';
    return ShareUtils.buildShareUrl(`/t/${slug}/${this.topic.id}`);
  }

  private handlePreviewLinkClick(url: string): void {
    const raw: string = url !== undefined && url !== null ? url.trim() : '';
    if (raw.length === 0 || raw.startsWith('#')) return;

    if (raw.startsWith('mailto:') || raw.startsWith('tel:')) {
      this.onClose();
      ExternalLinkService.openInBrowser(raw);
      return;
    }

    const full: string = UrlUtils.resolveUrl(raw);
    let path: string = full;
    const schemeIdx: number = full.indexOf('://');
    if (schemeIdx >= 0) {
      const after: number = schemeIdx + 3;
      const slashIdx: number = full.indexOf('/', after);
      path = slashIdx >= 0 ? full.substring(slashIdx) : '/';
    }

    if (path.startsWith('/t/')) {
      const segs: string[] = path.split('/');
      let topicId: number = 0;
      let postNumber: number = 0;
      for (let i = 2; i < segs.length; i++) {
        const seg: string = segs[i].trim();
        if (seg.length === 0) continue;
        const parsed: number = parseInt(seg, 10);
        if (isNaN(parsed)) continue;
        if (topicId <= 0) {
          topicId = parsed;
        } else if (postNumber <= 0) {
          postNumber = parsed;
          break;
        }
      }
      if (topicId > 0) {
        this.onClose();
        RouterManager.pushTopicDetail(topicId, postNumber > 0 ? postNumber : 0);
        return;
      }
    }

    if (path.startsWith('/u/')) {
      const segs: string[] = path.split('/');
      if (segs.length >= 3) {
        const username: string = segs[2].trim();
        if (username.length > 0) {
          this.onClose();
          RouterManager.pushUserProfile(username);
          return;
        }
      }
    }

    this.onClose();
    ExternalLinkService.openInBrowser(full);
  }

  private openPreviewImage(urls: string[], initialIndex: number): void {
    if (urls.length === 0) return;
    let idx: number = initialIndex;
    if (idx < 0) idx = 0;
    if (idx >= urls.length) idx = urls.length - 1;
    this.onClose();
    RouterManager.pushImagePreview(urls, idx);
  }

  private async shareTopic(): Promise<void> {
    const url: string = this.getTopicShareUrl();
    const ok: boolean = await SystemShareService.shareText(url, this.topic.title, false);
    if (ok) return;
    const copied: boolean = await ClipboardService.copyText(url, true);
    if (!copied) {
      ToastService.showShareFailed();
    }
  }
}
