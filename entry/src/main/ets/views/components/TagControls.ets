import { hilog } from '@kit.PerformanceAnalysisKit';
import { ApiClient } from '../../services/network/ApiClient';
import { TagInfo, TagSearchResult } from '../../models/TagSearchResult';
import { TagBadge, BadgeIconUtils } from './TopicBadges';
import { ErrorView } from './ErrorView';
import { WindowManager } from '../../common/utils/WindowManager';

/**
 * 标签相关通用组件：
 * - TagChip：排序栏内显示已选标签（可删除）
 * - TagSelectionSheet：标签选择 Sheet 内容（复用首页/分类页）
 */

export const DEFAULT_AVAILABLE_TAGS: string[] = [
  'harmonyos',
  'arkui',
  'bug',
  'resource',
  'ai',
  'tips',
  'help',
  'showcase',
  'release',
  'design'
];

@ComponentV2
export struct TagChip {
  @Param tagName: string = '';
  @Event onRemove: () => void = () => {};

  build() {
    Row() {
      if (BadgeIconUtils.getTagSymbol(this.tagName) !== null) {
        SymbolGlyph(BadgeIconUtils.getTagSymbol(this.tagName) as Resource)
          .fontSize(11)
          .fontColor([BadgeIconUtils.getTagColor(this.tagName)])
          .margin({ right: 3 })
      }
      Text(this.tagName)
        .fontSize(12)
        .fontColor($r('app.color.on_surface'))
      Row() {
        SymbolGlyph($r('sys.symbol.xmark'))
          .fontSize(12)
          .fontColor([$r('app.color.on_surface_secondary')])
      }
      .margin({ left: 4 })
      .onClick(() => {
        this.onRemove();
      })
    }
    .padding({ left: 8, right: 8, top: 4, bottom: 4 })
    .backgroundColor($r('app.color.tag_background'))
    .borderRadius(6)
    .margin({ right: 6 })
  }
}

@ComponentV2
export struct TagSelectionSheet {
  @Param title: string | Resource = '选择标签';
  @Param doneText: string | Resource = '确定';
  @Param availableTags: string[] = [];
  @Param selectedTags: string[] = [];
  @Param categoryId: number | null = null;
  @Param maxTags: number = 5;
  @Param showHeaderBar: boolean = false;
  @Param showDragHandle: boolean = true;

  @Event onToggleTag: (tagName: string) => void = () => {};
  @Event onDone: () => void = () => {};
  @Event onClear: () => void = () => {};
  @Event onBack: () => void = () => {};

  @Local private searchQuery: string = '';
  @Local private isLoading: boolean = false;
  @Local private initialized: boolean = false;
  @Local private results: TagInfo[] = [];
  @Local private errorMessage: string = '';

  private debounceTimerId: number = -1;

  aboutToAppear(): void {
    this.searchTags('');
  }

  aboutToDisappear(): void {
    this.clearDebounce();
  }

  private clearDebounce(): void {
    if (this.debounceTimerId >= 0) {
      clearTimeout(this.debounceTimerId);
      this.debounceTimerId = -1;
    }
  }

  private scheduleSearch(query: string): void {
    this.searchQuery = query;
    this.clearDebounce();
    this.debounceTimerId = setTimeout(() => {
      this.debounceTimerId = -1;
      this.searchTags(this.searchQuery);
    }, 300);
  }

  private getErrorText(err: Object): string {
    try {
      if (err !== null && err !== undefined) {
        const s: string = err.toString();
        if (s.length > 0 && s !== '[object Object]') {
          return s;
        }
      }
    } catch (_) {
    }
    try {
      return JSON.stringify(err);
    } catch (_) {
    }
    return '';
  }

  private async searchTags(query: string): Promise<void> {
    this.isLoading = true;
    this.errorMessage = '';
    try {
      const apiClient: ApiClient = ApiClient.getInstance();
      const resp: TagSearchResult = await apiClient.searchTags(
        query,
        this.categoryId,
        this.selectedTags,
        8,
        false
      );
      this.results = resp.results;
    } catch (err) {
      this.results = [];
      const errText: string = this.getErrorText(err as Object);
      this.errorMessage = errText.indexOf('Cloudflare') >= 0 ? '需要通过 Cloudflare 验证，请重试' : '标签加载失败，请重试';
      hilog.error(0x0000, 'TagSelectionSheet', 'Search tags failed: %{public}s', errText);
    } finally {
      this.isLoading = false;
      this.initialized = true;
    }
  }

  private isSelected(tagName: string): boolean {
    return this.selectedTags.indexOf(tagName) >= 0;
  }

  private getDisplayResults(): TagInfo[] {
    const out: TagInfo[] = [];
    for (let i = 0; i < this.results.length; i++) {
      const info: TagInfo = this.results[i];
      if (!this.isSelected(info.name)) {
        out.push(info);
      }
    }
    return out;
  }

  build() {
    Column() {
      if (this.showDragHandle) {
        // 拖动柄（自绘，避免依赖 Sheet 自带 close/dragbar）
        Column() {
          Rect()
            .width(32)
            .height(4)
            .radius(2)
            .fill($r('app.color.divider_light'))
        }
        .width('100%')
        .padding({ top: 12 })
        .alignItems(HorizontalAlign.Center)
      }

      if (this.showHeaderBar) {
        Row() {
          Row() {
            SymbolGlyph($r('sys.symbol.chevron_left'))
              .fontSize(18)
              .fontColor([$r('app.color.on_surface')])
          }
          .width(32)
          .height(32)
          .justifyContent(FlexAlign.Center)
          .alignItems(VerticalAlign.Center)
          .onClick(() => {
            this.onBack();
          })

          Text(this.title)
            .layoutWeight(1)
            .fontSize(17)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.on_surface'))
            .textAlign(TextAlign.Center)

          Blank()
            .width(32)
            .height(32)
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 14, bottom: 2 })
        .alignItems(VerticalAlign.Center)
      }

      // 顶部：搜索框 + 确定按钮
      Row() {
        // 搜索输入框（圆角胶囊）
        Row() {
          SymbolGlyph($r('sys.symbol.magnifyingglass'))
            .fontSize(18)
            .fontColor([$r('app.color.on_surface_tertiary')])
            .margin({ right: 6 })

          TextInput({ text: this.searchQuery, placeholder: '搜索标签...' })
            .fontSize(15)
            .fontColor($r('app.color.on_surface'))
            .placeholderColor($r('app.color.on_surface_tertiary'))
            .backgroundColor(Color.Transparent)
            .layoutWeight(1)
            .onChange((value: string) => {
              this.scheduleSearch(value);
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
              this.searchQuery = '';
              this.searchTags('');
            })
          }
        }
        .height(40)
        .padding({ left: 14, right: 10 })
        .backgroundColor($r('app.color.search_background'))
        .borderRadius(20)
        .layoutWeight(1)
        .alignItems(VerticalAlign.Center)

        Button() {
          Text(this.doneText)
            .fontSize(14)
            .fontColor($r('app.color.primary'))
            .fontWeight(FontWeight.Medium)
        }
        .height(40)
        .padding({ left: 16, right: 16 })
        .borderRadius(20)
        .backgroundColor($r('app.color.badge_background_light'))
        .margin({ left: 10 })
        .onClick(() => {
          this.onDone();
        })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 16, bottom: 12 })
      .alignItems(VerticalAlign.Center)

      Divider()
        .color($r('app.color.skeleton_base'))
        .strokeWidth(0.5)
        .margin({ left: 16, right: 16 })

      // 已选标签展示区
      if (this.selectedTags.length > 0) {
        Flex({ wrap: FlexWrap.Wrap }) {
          ForEach(this.selectedTags, (t: string) => {
            TagChip({
              tagName: t,
              onRemove: () => {
                this.onToggleTag(t);
              }
            })
              .margin({ right: 8, bottom: 8 })
          })
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 12, bottom: 8 })
      }

      // 标签列表（支持 API 搜索 + 计数）
      if (!this.initialized && this.isLoading) {
        Column() {
          LoadingProgress().width(20).height(20)
        }
        .layoutWeight(1)
        .width('100%')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      } else if (this.errorMessage.length > 0) {
        Column() {
          ErrorView({
            message: this.errorMessage,
            onRetry: () => {
              this.searchTags(this.searchQuery);
            }
          })
        }
        .layoutWeight(1)
        .width('100%')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      } else if (this.getDisplayResults().length === 0) {
        Column() {
          Text(this.searchQuery.trim().length === 0 ? '暂无可用标签' : '未找到相关标签')
            .fontSize(13)
            .fontColor($r('app.color.on_surface_tertiary'))
        }
        .layoutWeight(1)
        .width('100%')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      } else {
        List() {
          ForEach(this.getDisplayResults(), (info: TagInfo) => {
            ListItem() {
              Row() {
                TagBadge({ name: info.text, bgColor: Color.Transparent })

                Blank().layoutWeight(1)

                if (info.count > 0) {
                  Text(`${info.count}`)
                    .fontSize(12)
                    .fontColor($r('app.color.on_surface_tertiary'))
                    .margin({ right: 10 })
                }

                if (this.selectedTags.length >= this.maxTags) {
                  SymbolGlyph($r('sys.symbol.lock'))
                    .fontSize(18)
                    .fontColor([$r('app.color.on_surface_tertiary')])
                } else {
                  SymbolGlyph($r('sys.symbol.plus_circle'))
                    .fontSize(18)
                    .fontColor([$r('app.color.primary')])
                }
              }
              .width('100%')
              .padding({ left: 16, right: 16, top: 12, bottom: 12 })
              .alignItems(VerticalAlign.Center)
            }
            .onClick(() => {
              if (this.selectedTags.length < this.maxTags) {
                this.onToggleTag(info.name);
              }
            })
          }, (info: TagInfo) => info.name)
        }
        .layoutWeight(1)
        .width('100%')
        .backgroundColor($r('app.color.surface'))
        .divider({ strokeWidth: 0.5, color: $r('app.color.skeleton_base'), startMargin: 16, endMargin: 16 })
      }

      // 底部操作
      Row() {
        Text(`已选 ${this.selectedTags.length} 个`)
          .fontSize(12)
          .fontColor($r('app.color.on_surface_tertiary'))
        Blank()
        Text($r('app.string.clear'))
          .fontSize(14)
          .fontColor($r('app.color.on_surface_secondary'))
          .onClick(() => {
            this.onClear();
          })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12, bottom: 20 + WindowManager.getSystemAvoidAreaBottomVp() })
      .backgroundColor($r('app.color.surface'))
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.surface'))
  }
}
