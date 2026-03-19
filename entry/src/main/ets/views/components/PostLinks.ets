import { LinkCount } from '../../models/Post';

const MAX_COLLAPSED_LINKS: number = 5;

function formatClicks(count: number): string {
  const v: number = count !== undefined && count !== null ? Math.round(count) : 0;
  if (v >= 1000) {
    const k: string = (v / 1000).toFixed(1);
    return `${k}k`;
  }
  return `${v}`;
}

@ComponentV2
export struct PostLinks {
  @Param linkCounts: LinkCount[] | null = null;
  @Event onOpenLink: (url: string) => void = () => {
  };

  @Local private expanded: boolean = false;
  @Local private showAll: boolean = false;

  private getInternalLinks(): LinkCount[] {
    if (this.linkCounts === null) return [];
    const list: LinkCount[] = this.linkCounts as LinkCount[];
    const out: LinkCount[] = [];
    const seen: Set<string> = new Set<string>();

    for (let i: number = 0; i < list.length; i++) {
      const l: LinkCount = list[i];
      if (l === null || l === undefined) continue;
      if (!l.internal || !l.reflection) continue;
      const title: string = l.title !== null ? (l.title as string).trim() : '';
      if (title.length === 0) continue;
      if (seen.has(title)) continue;
      seen.add(title);
      out.push(l);
    }
    return out;
  }

  private getDisplayedLinks(links: LinkCount[]): LinkCount[] {
    if (this.showAll || links.length <= MAX_COLLAPSED_LINKS) return links;
    const out: LinkCount[] = [];
    for (let i: number = 0; i < links.length && i < MAX_COLLAPSED_LINKS; i++) {
      out.push(links[i]);
    }
    return out;
  }

  private canShowMore(links: LinkCount[]): boolean {
    return !this.showAll && links.length > MAX_COLLAPSED_LINKS;
  }

  private remainingCount(links: LinkCount[]): number {
    const n: number = links.length - MAX_COLLAPSED_LINKS;
    return n > 0 ? n : 0;
  }

  build() {
    Column() {
      if (this.getInternalLinks().length === 0) {
        Blank().width('100%').height(0)
      } else {
        Column() {
          // 标题栏（可点击展开/收起）
          Row() {
            SymbolGlyph($r('sys.symbol.link'))
              .fontSize(16)
              .fontColor([$r('app.color.primary')])
              .margin({ right: 8 })

            Text('相关链接')
              .fontSize(13)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.primary'))

            Blank().width(6)

            Row() {
              Text(`${this.getInternalLinks().length}`)
                .fontSize(11)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.primary'))
            }
            .padding({ left: 6, right: 6, top: 1, bottom: 1 })
            .backgroundColor($r('app.color.badge_background_light'))
            .borderRadius(8)

            Blank().layoutWeight(1)

            SymbolGlyph($r('sys.symbol.chevron_down'))
              .fontSize(18)
              .fontColor([$r('app.color.on_surface_secondary')])
              .rotate({ angle: this.expanded ? 180 : 0 })
          }
          .width('100%')
          .padding({ left: 12, right: 12, top: 10, bottom: 10 })
          .alignItems(VerticalAlign.Center)
          .onClick(() => {
            this.expanded = !this.expanded;
            if (!this.expanded) {
              this.showAll = false;
            }
          })

          if (this.expanded) {
            Column() {
              Divider()
                .color($r('app.color.divider_light'))
                .strokeWidth(0.5)

              ForEach(this.getDisplayedLinks(this.getInternalLinks()), (l: LinkCount) => {
                Row() {
                  SymbolGlyph($r('sys.symbol.arrow_right'))
                    .fontSize(16)
                    .fontColor([$r('app.color.on_surface_tertiary')])
                    .margin({ right: 8 })

                  Text(l.title !== null && (l.title as string).trim().length > 0 ? (l.title as string) : l.url)
                    .fontSize(13)
                    .fontColor($r('app.color.primary'))
                    .maxLines(2)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .layoutWeight(1)

                  if (l.clicks > 0) {
                    Row() {
                      Text(formatClicks(l.clicks))
                        .fontSize(10)
                        .fontColor($r('app.color.on_surface_secondary'))
                    }
                    .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                    .backgroundColor($r('app.color.surface'))
                    .borderRadius(8)
                    .margin({ left: 8 })
                  }

                  SymbolGlyph($r('sys.symbol.arrow_right'))
                    .fontSize(14)
                    .fontColor([$r('app.color.on_surface_tertiary')])
                    .margin({ left: 6 })
                }
                .width('100%')
                .padding({ left: 12, right: 12, top: 10, bottom: 10 })
                .alignItems(VerticalAlign.Center)
                .onClick(() => {
                  const url: string = l.url !== undefined && l.url !== null ? l.url.trim() : '';
                  if (url.length > 0) {
                    this.onOpenLink(url);
                  }
                })
              }, (l: LinkCount) => l.url)

              if (this.canShowMore(this.getInternalLinks())) {
                Row() {
                  SymbolGlyph($r('sys.symbol.ellipsis_circle'))
                    .fontSize(16)
                    .fontColor([$r('app.color.primary')])
                    .margin({ right: 6 })
                  Text(`还有 ${this.remainingCount(this.getInternalLinks())} 条`)
                    .fontSize(13)
                    .fontColor($r('app.color.primary'))
                }
                .width('100%')
                .justifyContent(FlexAlign.Center)
                .alignItems(VerticalAlign.Center)
                .padding({ top: 10, bottom: 10 })
                .onClick(() => {
                  this.showAll = true;
                })
              }
            }
            .width('100%')
          }
        }
        .width('100%')
        .backgroundColor($r('app.color.surface_variant'))
        .border({ width: 0.5, color: $r('app.color.divider_light') })
        .borderRadius(12)
        .margin({ top: 16 })
      }
    }
    .width('100%')
  }
}
