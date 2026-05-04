import { ApiClient } from '../../services/network/ApiClient';
import { Emoji } from '../../models/Emoji';
import { UrlUtils } from '../../common/utils/UrlUtils';
import { CustomEmojiEntry, EmojiResolver } from '../../common/utils/EmojiResolver';
import { ComposerEmojiPreferences } from '../../services/storage/ComposerEmojiPreferences';
import { ThemeManager } from '../../common/theme/ThemeManager';

class EmojiPanelGroup {
  key: string = '';
  title: string = '';
  emojis: Emoji[] = [];
}

class EmojiPanelTab {
  key: string = '';
  title: string = '';
}

class FallbackEmojiRow {
  name: string = '';
  aliases: string[] = [];
}

@ComponentV2
export struct ComposerEmojiPanel {
  @Param panelHeight: number = 320;
  @Param showHandle: boolean = true;
  @Event onSelectEmoji: (emoji: Emoji) => void = (_: Emoji) => {
  };

  @Local private isLoading: boolean = false;
  @Local private errorMessage: string = '';
  @Local private searchQuery: string = '';
  @Local private groups: EmojiPanelGroup[] = [];
  @Local private recentEmojiNames: string[] = [];
  @Local private selectedGroupKey: string = '';

  aboutToAppear(): void {
    this.loadRecentEmojiNames();
    this.loadEmojiGroups();
  }

  private async loadRecentEmojiNames(): Promise<void> {
    this.recentEmojiNames = await ComposerEmojiPreferences.loadRecentNames();
    this.ensureSelectedGroup();
  }

  private async loadEmojiGroups(): Promise<void> {
    if (this.groups.length > 0) {
      return;
    }
    this.isLoading = true;
    this.errorMessage = '';
    try {
      try {
        await ApiClient.getInstance().getSiteInfo();
      } catch (_) {
      }
      const groups: Map<string, Emoji[]> = await ApiClient.getInstance().getEmojis();
      const built: EmojiPanelGroup[] = this.buildGroups(groups);
      if (built.length === 0) {
        this.groups = this.buildFallbackGroups();
        if (this.groups.length === 0) {
          this.errorMessage = '暂无可用表情';
        }
      } else {
        this.groups = built;
      }
      this.ensureSelectedGroup();
    } catch (err) {
      this.groups = this.buildFallbackGroups();
      if (this.groups.length === 0) {
        this.errorMessage = err !== undefined && err !== null
          ? err.toString().replace('Error: ', '')
          : '表情库加载失败';
      }
      this.ensureSelectedGroup();
    } finally {
      this.isLoading = false;
    }
  }

  private buildGroups(groups: Map<string, Emoji[]>): EmojiPanelGroup[] {
    const out: EmojiPanelGroup[] = [];
    const keys: string[] = Array.from(groups.keys());
    keys.sort((a: string, b: string): number => this.getGroupOrder(a) - this.getGroupOrder(b));
    for (let i = 0; i < keys.length; i++) {
      const key: string = keys[i];
      const list: Emoji[] = groups.get(key) as Emoji[];
      if (list === null || list === undefined || list.length === 0) {
        continue;
      }
      const group: EmojiPanelGroup = new EmojiPanelGroup();
      group.key = key;
      group.title = this.formatGroupTitle(key);
      group.emojis = list;
      this.registerEmojiUrls(list);
      out.push(group);
    }
    return out;
  }

  private registerEmojiUrls(emojis: Emoji[]): void {
    for (let i = 0; i < emojis.length; i++) {
      const emoji: Emoji = emojis[i];
      const rawUrl: string = emoji.url !== undefined && emoji.url !== null ? emoji.url.trim() : '';
      if (rawUrl.length > 0) {
        EmojiResolver.registerEmojiUrl(emoji.name, rawUrl);
      }
    }
  }

  private buildFallbackGroups(): EmojiPanelGroup[] {
    const groups: EmojiPanelGroup[] = [];

    const customEntries: CustomEmojiEntry[] = EmojiResolver.getCustomEmojiEntries();
    if (customEntries.length > 0) {
      const customGroup: EmojiPanelGroup = new EmojiPanelGroup();
      customGroup.key = 'custom';
      customGroup.title = '站点';
      const emojis: Emoji[] = [];
      for (let i = 0; i < customEntries.length; i++) {
        const entry: CustomEmojiEntry = customEntries[i];
        const emoji: Emoji = new Emoji();
        emoji.name = entry.name;
        emoji.url = entry.url;
        emoji.group = 'custom';
        emojis.push(emoji);
      }
      customGroup.emojis = emojis;
      groups.push(customGroup);
    }

    groups.push(this.createFallbackGroup('smileys_&_emotion', '表情', [
      this.createFallbackRow('smile', ['happy', '开心']),
      this.createFallbackRow('grinning', ['laugh', '笑']),
      this.createFallbackRow('joy', ['tears', '喜极而泣']),
      this.createFallbackRow('heart_eyes', ['love', '喜欢']),
      this.createFallbackRow('thinking', ['hmm', '思考']),
      this.createFallbackRow('sob', ['cry', '哭']),
      this.createFallbackRow('rage', ['mad', '生气']),
      this.createFallbackRow('sparkles', ['stars', '闪亮']),
      this.createFallbackRow('sunglasses', ['cool', '酷']),
      this.createFallbackRow('sleeping', ['sleep', '睡觉'])
    ]));
    groups.push(this.createFallbackGroup('people_&_body', '动作', [
      this.createFallbackRow('wave', ['hello', '招手']),
      this.createFallbackRow('thumbsup', ['good', '赞']),
      this.createFallbackRow('clap', ['applause', '鼓掌']),
      this.createFallbackRow('pray', ['thanks', '感谢']),
      this.createFallbackRow('muscle', ['strong', '加油']),
      this.createFallbackRow('ok_hand', ['ok', '没问题']),
      this.createFallbackRow('handshake', ['shake', '握手']),
      this.createFallbackRow('writing_hand', ['write', '书写'])
    ]));
    groups.push(this.createFallbackGroup('symbols', '符号', [
      this.createFallbackRow('heart', ['love', '爱心']),
      this.createFallbackRow('broken_heart', ['sad', '心碎']),
      this.createFallbackRow('fire', ['hot', '火']),
      this.createFallbackRow('100', ['full', '满分']),
      this.createFallbackRow('warning', ['alert', '注意']),
      this.createFallbackRow('rocket', ['launch', '起飞']),
      this.createFallbackRow('star', ['favorite', '星星']),
      this.createFallbackRow('check', ['done', '完成'])
    ]));
    return groups;
  }

  private createFallbackRow(name: string, aliases: string[] = []): FallbackEmojiRow {
    const row: FallbackEmojiRow = new FallbackEmojiRow();
    row.name = name;
    row.aliases = aliases;
    return row;
  }

  private createFallbackGroup(
    key: string,
    title: string,
    rows: FallbackEmojiRow[]
  ): EmojiPanelGroup {
    const group: EmojiPanelGroup = new EmojiPanelGroup();
    group.key = key;
    group.title = title;
    const emojis: Emoji[] = [];
    for (let i = 0; i < rows.length; i++) {
      const row: FallbackEmojiRow = rows[i];
      const emoji: Emoji = new Emoji();
      emoji.name = row.name;
      emoji.group = key;
      emoji.searchAliases = row.aliases;
      emojis.push(emoji);
    }
    group.emojis = emojis;
    return group;
  }

  private getGroupOrder(key: string): number {
    const normalized: string = key.toLowerCase();
    if (normalized.indexOf('custom') >= 0) return 0;
    if (normalized === 'smileys_&_emotion') return 10;
    if (normalized === 'people_&_body') return 20;
    if (normalized === 'animals_&_nature') return 30;
    if (normalized === 'food_&_drink') return 40;
    if (normalized === 'activities') return 50;
    if (normalized === 'travel_&_places') return 60;
    if (normalized === 'objects') return 70;
    if (normalized === 'symbols') return 80;
    if (normalized === 'flags') return 90;
    return 100 + normalized.charCodeAt(0);
  }

  private formatGroupTitle(key: string): string {
    const normalized: string = key.toLowerCase();
    if (normalized.indexOf('custom') >= 0) return '站点';
    if (normalized === 'smileys_&_emotion') return '表情';
    if (normalized === 'people_&_body') return '动作';
    if (normalized === 'animals_&_nature') return '自然';
    if (normalized === 'food_&_drink') return '食物';
    if (normalized === 'activities') return '活动';
    if (normalized === 'travel_&_places') return '地点';
    if (normalized === 'objects') return '物件';
    if (normalized === 'symbols') return '符号';
    if (normalized === 'flags') return '旗帜';
    const compact: string = key.replace(/_&_/g, '·').replace(/_/g, ' ').trim();
    return compact.length > 0 ? compact : '表情';
  }

  private normalizeSearchQuery(query: string): string {
    return query !== undefined && query !== null ? query.trim().toLowerCase() : '';
  }

  private getAllEmojis(): Emoji[] {
    const out: Emoji[] = [];
    const seen: Map<string, boolean> = new Map();
    for (let i = 0; i < this.groups.length; i++) {
      const group: EmojiPanelGroup = this.groups[i];
      for (let j = 0; j < group.emojis.length; j++) {
        const emoji: Emoji = group.emojis[j];
        if (seen.has(emoji.name)) {
          continue;
        }
        seen.set(emoji.name, true);
        out.push(emoji);
      }
    }
    return out;
  }

  private getRecentEmojis(): Emoji[] {
    if (this.recentEmojiNames.length === 0) {
      return [];
    }
    const indexMap: Map<string, Emoji> = new Map();
    const all: Emoji[] = this.getAllEmojis();
    for (let i = 0; i < all.length; i++) {
      indexMap.set(all[i].name, all[i]);
    }
    const out: Emoji[] = [];
    for (let i = 0; i < this.recentEmojiNames.length; i++) {
      const name: string = this.recentEmojiNames[i];
      if (indexMap.has(name)) {
        out.push(indexMap.get(name) as Emoji);
      }
    }
    return out;
  }

  private getGroupTabs(): EmojiPanelTab[] {
    const tabs: EmojiPanelTab[] = [];
    const recentEmojis: Emoji[] = this.getRecentEmojis();
    if (recentEmojis.length > 0) {
      const recent: EmojiPanelTab = new EmojiPanelTab();
      recent.key = 'recent';
      recent.title = '最近';
      tabs.push(recent);
    }
    for (let i = 0; i < this.groups.length; i++) {
      const tab: EmojiPanelTab = new EmojiPanelTab();
      tab.key = this.groups[i].key;
      tab.title = this.groups[i].title;
      tabs.push(tab);
    }
    return tabs;
  }

  private ensureSelectedGroup(): void {
    if (this.normalizeSearchQuery(this.searchQuery).length > 0) {
      return;
    }
    const tabs: EmojiPanelTab[] = this.getGroupTabs();
    if (tabs.length === 0) {
      this.selectedGroupKey = '';
      return;
    }
    for (let i = 0; i < tabs.length; i++) {
      if (tabs[i].key === this.selectedGroupKey) {
        return;
      }
    }
    this.selectedGroupKey = tabs[0].key;
  }

  private matchesEmoji(emoji: Emoji, query: string): boolean {
    if (emoji.name.toLowerCase().indexOf(query) >= 0) {
      return true;
    }
    const aliases: string[] = emoji.searchAliases;
    for (let i = 0; i < aliases.length; i++) {
      if (aliases[i].toLowerCase().indexOf(query) >= 0) {
        return true;
      }
    }
    return this.formatGroupTitle(emoji.group).toLowerCase().indexOf(query) >= 0;
  }

  private getVisibleEmojis(): Emoji[] {
    const query: string = this.normalizeSearchQuery(this.searchQuery);
    if (query.length > 0) {
      const out: Emoji[] = [];
      const seen: Map<string, boolean> = new Map();
      const all: Emoji[] = this.getAllEmojis();
      for (let i = 0; i < all.length; i++) {
        const emoji: Emoji = all[i];
        if (seen.has(emoji.name) || !this.matchesEmoji(emoji, query)) {
          continue;
        }
        seen.set(emoji.name, true);
        out.push(emoji);
      }
      return out;
    }

    if (this.selectedGroupKey === 'recent') {
      return this.getRecentEmojis();
    }

    for (let i = 0; i < this.groups.length; i++) {
      if (this.groups[i].key === this.selectedGroupKey) {
        return this.groups[i].emojis;
      }
    }
    return [];
  }

  private shouldShowGroupTabs(): boolean {
    return this.normalizeSearchQuery(this.searchQuery).length === 0 && this.getGroupTabs().length > 0;
  }

  private getEmojiUrl(emoji: Emoji): string {
    const rawUrl: string = emoji.url !== undefined && emoji.url !== null ? emoji.url.trim() : '';
    if (rawUrl.length > 0) {
      EmojiResolver.registerEmojiUrl(emoji.name, rawUrl);
      return UrlUtils.resolveUrl(rawUrl);
    }
    return EmojiResolver.resolveEmojiUrl(`:${emoji.name}:`);
  }

  private getEmojiFallbackLabel(emoji: Emoji): string {
    const name: string = emoji.name !== undefined && emoji.name !== null ? emoji.name.trim() : '';
    if (name.length <= 4) {
      return name;
    }
    return name.substring(0, 4);
  }

  private handleSearchChange(value: string): void {
    this.searchQuery = value;
    if (this.normalizeSearchQuery(value).length === 0) {
      this.ensureSelectedGroup();
    }
  }

  private handleEmojiTap(emoji: Emoji): void {
    ComposerEmojiPreferences.saveRecentName(emoji.name).catch((_: Object) => {
    });
    this.onSelectEmoji(emoji);
  }

  @Builder
  private SearchBar() {
    Row() {
      Row() {
        SymbolGlyph($r('sys.symbol.magnifyingglass'))
          .fontSize(18)
          .fontColor([$r('app.color.on_surface_tertiary')])
          .margin({ right: 6 })

        TextInput({ text: this.searchQuery, placeholder: '搜索表情...' })
          .fontSize(15)
          .fontColor($r('app.color.on_surface'))
          .placeholderColor($r('app.color.on_surface_tertiary'))
          .backgroundColor(Color.Transparent)
          .layoutWeight(1)
          .onChange((value: string) => {
            this.handleSearchChange(value);
          })

        if (this.searchQuery.length > 0) {
          Row() {
            SymbolGlyph($r('sys.symbol.xmark_circle_fill'))
              .fontSize(18)
              .fontColor([$r('app.color.on_surface_tertiary')])
          }
          .width(32)
          .height(32)
          .justifyContent(FlexAlign.Center)
          .alignItems(VerticalAlign.Center)
          .onClick(() => {
            this.handleSearchChange('');
          })
        }
      }
      .height(40)
      .padding({ left: 14, right: 10 })
      .backgroundColor(ThemeManager.getCurrentAccentSurfaceVariantColorHex())
      .borderRadius(20)
      .layoutWeight(1)
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 10, bottom: 8 })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private GroupTabs() {
    Scroll() {
      Row() {
        ForEach(this.getGroupTabs(), (tab: EmojiPanelTab) => {
          Row() {
            Text(tab.title)
              .fontSize(13)
              .fontWeight(this.selectedGroupKey === tab.key ? FontWeight.Medium : FontWeight.Regular)
              .fontColor(this.selectedGroupKey === tab.key ? ThemeManager.getCurrentAccentColorHex() : $r('app.color.on_surface_secondary'))
          }
          .padding({ left: 14, right: 14, top: 9, bottom: 9 })
          .backgroundColor(this.selectedGroupKey === tab.key
            ? ThemeManager.getCurrentAccentSelectedBackgroundColorHex()
            : ThemeManager.getCurrentAccentSurfaceVariantColorHex())
          .borderRadius(18)
          .margin({ right: 8 })
          .onClick(() => {
            this.selectedGroupKey = tab.key;
          })
        }, (tab: EmojiPanelTab) => tab.key)
      }
      .padding({ left: 16, right: 16, top: 4, bottom: 10 })
      .alignItems(VerticalAlign.Center)
    }
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
  }

  @Builder
  private EmojiGrid() {
    Scroll() {
      Column() {
        if (this.normalizeSearchQuery(this.searchQuery).length > 0) {
          Text(`搜索结果 ${this.getVisibleEmojis().length}`)
            .fontSize(12)
            .fontColor($r('app.color.on_surface_secondary'))
            .width('100%')
            .padding({ left: 16, right: 16, top: 4, bottom: 8 })
        }

        Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
          ForEach(this.getVisibleEmojis(), (emoji: Emoji) => {
            Column() {
              if (this.getEmojiUrl(emoji).length > 0) {
                Image(this.getEmojiUrl(emoji))
                  .width(28)
                  .height(28)
                  .objectFit(ImageFit.Contain)
              } else {
                Text(this.getEmojiFallbackLabel(emoji))
                  .fontSize(12)
                  .fontColor($r('app.color.on_surface_secondary'))
                  .maxLines(1)
              }
            }
            .width('14.2857%')
            .height(48)
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center)
            .backgroundColor(Color.Transparent)
            .borderRadius(12)
            .onClick(() => {
              this.handleEmojiTap(emoji);
            })
          }, (emoji: Emoji) => `${emoji.group}_${emoji.name}`)
        }
        .width('100%')
        .padding({ left: 10, right: 10, top: 4, bottom: 12 })
      }
      .width('100%')
      .constraintSize({ minHeight: '100%' })
      .justifyContent(FlexAlign.Start)
      .alignItems(HorizontalAlign.Start)
    }
    .layoutWeight(1)
    .scrollBar(BarState.Off)
  }

  @Builder
  private LoadingState() {
    Column() {
      LoadingProgress()
        .width(22)
        .height(22)

      Text('正在加载表情...')
        .fontSize(12)
        .fontColor($r('app.color.on_surface_secondary'))
        .margin({ top: 10 })
    }
    .layoutWeight(1)
    .width('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  private EmptyState() {
    Column() {
      Text(this.normalizeSearchQuery(this.searchQuery).length > 0 ? '没有找到匹配的表情' : '暂无可用表情')
        .fontSize(13)
        .fontColor($r('app.color.on_surface_tertiary'))

      if (this.errorMessage.length > 0) {
        Text(this.errorMessage)
          .fontSize(12)
          .fontColor($r('app.color.warning'))
          .margin({ top: 8 })
      }
    }
    .layoutWeight(1)
    .width('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  private ErrorState() {
    Column() {
      Text(this.errorMessage.length > 0 ? this.errorMessage : '表情库加载失败')
        .fontSize(13)
        .fontColor($r('app.color.warning'))

      Button('重试')
        .type(ButtonType.Capsule)
        .height(36)
        .margin({ top: 12 })
        .backgroundColor(ThemeManager.getCurrentAccentColorHex())
        .fontColor(Color.White)
        .onClick(() => {
          this.loadEmojiGroups().catch((_: Object) => {
          });
        })
    }
    .layoutWeight(1)
    .width('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  build() {
    Column() {
      if (this.showHandle) {
        Rect()
          .width(32)
          .height(4)
          .radius(2)
          .fill($r('app.color.divider_light'))
          .margin({ top: 6, bottom: 2 })
      }

      this.SearchBar()

      if (this.shouldShowGroupTabs()) {
        this.GroupTabs()
      }

      Divider()
        .strokeWidth(0.5)
        .color($r('app.color.divider_light'))
        .margin({ left: 16, right: 16, bottom: 2 })

      if (this.isLoading && this.groups.length === 0) {
        this.LoadingState()
      } else if (this.errorMessage.length > 0 && this.groups.length === 0) {
        this.ErrorState()
      } else if (this.getVisibleEmojis().length === 0) {
        this.EmptyState()
      } else {
        this.EmojiGrid()
      }
    }
    .width('100%')
    .height(this.panelHeight)
    .backgroundColor(ThemeManager.getCurrentAccentSurfaceColorHex())
  }
}
