import { HdsNavDestination } from '@kit.UIDesignKit';
import { AppSettingsService } from '../../services/storage/AppSettingsService';
import {
  TrustLevelBarData,
  TrustLevelData,
  TrustLevelQuotaData,
  TrustLevelRingData,
  TrustLevelService,
  TrustLevelVetoData
} from '../../services/network/TrustLevelService';
import { RouterManager } from '../../common/utils/RouterManager';
import { WindowManager } from '../../common/utils/WindowManager';
import { LoadingSpinner } from '../components/LoadingSpinner';
import { ErrorView } from '../components/ErrorView';

const TOP_BAR_HEIGHT: number = 56;

@ComponentV2
export struct TrustLevelRequirementsPage {
  @Local isLoading: boolean = true;
  @Local isRefreshing: boolean = false;
  @Local errorMessage: string = '';
  @Local data: TrustLevelData | null = null;

  aboutToAppear(): void {
    if (this.data === null && this.errorMessage.length === 0) {
      this.loadData(true).catch(() => {
      });
    }
  }

  private async loadData(showLoading: boolean): Promise<void> {
    if (showLoading) {
      this.isLoading = true;
    }
    this.errorMessage = '';
    try {
      this.data = await TrustLevelService.fetchData();
    } catch (err) {
      const text: string = err !== undefined && err !== null ? err.toString().replace('Error: ', '').trim() : '';
      this.errorMessage = text.length > 0 ? text : '加载信任要求失败';
    } finally {
      this.isLoading = false;
      this.isRefreshing = false;
    }
  }

  private getBadgeTextColor(): string {
    if (this.data === null) {
      return '#F59E0B';
    }
    if ((this.data as TrustLevelData).badgeType === 'success') return '#22C55E';
    if ((this.data as TrustLevelData).badgeType === 'danger') return '#EF4444';
    return '#F59E0B';
  }

  private getDisplayTitle(): string {
    if (this.data === null) {
      return '信任要求';
    }
    const title: string = (this.data as TrustLevelData).title.trim();
    return title.length > 0 ? title : '信任要求';
  }

  @Builder
  private TopBar() {
    Row() {
      Row() {
        SymbolGlyph($r('sys.symbol.chevron_left'))
          .fontSize(18)
          .fontColor([$r('app.color.on_surface')])
      }
      .width(44)
      .height(44)
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
      .onClick(() => {
        RouterManager.pop();
      })

      Text('信任要求')
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.on_surface'))
        .layoutWeight(1)

      Row() {
        SymbolGlyph($r('sys.symbol.arrow_clockwise'))
          .fontSize(18)
          .fontColor([AppSettingsService.getInstance().getPrimaryColor()])
      }
      .width(44)
      .height(44)
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
      .onClick(() => {
        this.loadData(false).catch(() => {
        });
      })
    }
    .width('100%')
    .height(TOP_BAR_HEIGHT)
    .padding({ left: 8, right: 8 })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private HeaderCard() {
    Column() {
      Text((this.data as TrustLevelData).subtitle)
        .fontSize(13)
        .fontColor($r('app.color.on_surface_secondary'))
      Text(this.getDisplayTitle())
        .fontSize(28)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.on_surface'))
        .margin({ top: 4 })
      if ((this.data as TrustLevelData).badgeText.length > 0) {
        Row() {
          Text((this.data as TrustLevelData).badgeText)
            .fontSize(12)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.getBadgeTextColor())
        }
        .padding({ left: 10, right: 10, top: 5, bottom: 5 })
        .backgroundColor(AppSettingsService.getInstance().getPrimaryColorWithAlpha(0.1))
        .borderRadius(16)
        .margin({ top: 10 })
      }
    }
    .width('100%')
    .padding(20)
    .backgroundColor($r('app.color.card_background'))
    .borderRadius(20)
  }

  @Builder
  private SectionCard(title: string) {
    Column() {
      Text(title)
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.on_surface_secondary'))
        .margin({ bottom: 16 })
      this.SectionCardContent(title)
    }
    .width('100%')
    .padding(20)
    .backgroundColor($r('app.color.card_background'))
    .borderRadius(20)
  }

  @Builder
  private SectionCardContent(title: string) {
    if (this.data === null) {
      Column() {
      }
      .width('100%')
    } else if (title === '活跃度') {
      Row() {
        ForEach((this.data as TrustLevelData).rings, (ring: TrustLevelRingData) => {
          Column() {
            Stack({ alignContent: Alignment.Center }) {
              Progress({ value: ring.max > 0 ? ring.current : 0, total: ring.max > 0 ? ring.max : 1, type: ProgressType.Ring })
                .width(72)
                .height(72)
                .color(ring.isMet ? '#22C55E' : '#F59E0B')
                .backgroundColor('#22000000')
              Column() {
                Text(`${ring.current}`)
                  .fontSize(16)
                  .fontWeight(FontWeight.Bold)
                Text(`/${ring.max}`)
                  .fontSize(10)
                  .fontColor($r('app.color.on_surface_secondary'))
              }
            }
            Text(ring.label)
              .fontSize(12)
              .fontColor($r('app.color.on_surface_secondary'))
              .textAlign(TextAlign.Center)
              .margin({ top: 10 })
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Center)
        })
      }
      .width('100%')
    } else if (title === '互动') {
      Column() {
        ForEach((this.data as TrustLevelData).bars, (bar: TrustLevelBarData) => {
          Column() {
            Row() {
              Text(bar.label)
                .fontSize(13)
                .fontColor($r('app.color.on_surface'))
                .layoutWeight(1)
              Text(bar.current)
                .fontSize(13)
                .fontWeight(FontWeight.Medium)
                .fontColor(bar.isMet ? '#22C55E' : '#F59E0B')
            }
            .width('100%')
            Progress({ value: bar.progress * 100, total: 100, type: ProgressType.Linear })
              .width('100%')
              .height(8)
              .color(bar.isMet ? '#22C55E' : '#F59E0B')
              .backgroundColor('#22000000')
              .margin({ top: 8 })
          }
          .margin({ bottom: 14 })
        })
      }
      .width('100%')
    } else {
      Column() {
        Row() {
          ForEach((this.data as TrustLevelData).quotas, (quota: TrustLevelQuotaData) => {
            Column() {
              Text(quota.label)
                .fontSize(12)
                .fontColor($r('app.color.on_surface_secondary'))
              Text(quota.value)
                .fontSize(14)
                .fontWeight(FontWeight.Medium)
                .fontColor(quota.isMet ? $r('app.color.on_surface') : $r('app.color.error'))
                .margin({ top: 6, bottom: 8 })
              Row() {
                ForEach([0, 1, 2, 3, 4], (index: number) => {
                  Row() {
                  }
                  .layoutWeight(1)
                  .height(5)
                  .backgroundColor(index < quota.usedSlots ? '#EF4444' : '#22C55E')
                  .borderRadius(4)
                  .margin({ right: index < 4 ? 3 : 0 })
                })
              }
              .width('100%')
            }
            .layoutWeight(1)
            .padding(12)
            .backgroundColor(quota.isMet ? '#F7FBF7' : '#FFF7F7')
            .borderRadius(14)
            .margin({ right: 8 })
          })
        }
        .width('100%')

        Row() {
          ForEach((this.data as TrustLevelData).vetos, (veto: TrustLevelVetoData) => {
            Column() {
              Row() {
                Text(veto.value)
                  .fontSize(22)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(veto.isMet ? '#22C55E' : '#EF4444')
              }
              Text(veto.label)
                .fontSize(13)
                .fontWeight(FontWeight.Medium)
                .margin({ top: 10 })
              Text(veto.desc)
                .fontSize(11)
                .fontColor($r('app.color.on_surface_secondary'))
                .margin({ top: 4 })
            }
            .layoutWeight(1)
            .padding(14)
            .backgroundColor(veto.isMet ? '#F7FBF7' : '#FFF7F7')
            .borderRadius(14)
            .margin({ top: 12, right: 8 })
          })
        }
        .width('100%')
      }
      .width('100%')
    }
  }

  @Builder
  private FooterCard() {
    Column() {
      if ((this.data as TrustLevelData).footerHint.length > 0) {
        Text((this.data as TrustLevelData).footerHint)
          .fontSize(12)
          .fontColor($r('app.color.on_surface_secondary'))
          .textAlign(TextAlign.Center)
      }
      if ((this.data as TrustLevelData).statusText.length > 0) {
        Row() {
          SymbolGlyph((this.data as TrustLevelData).isStatusMet ? $r('sys.symbol.checkmark_circle') : $r('sys.symbol.xmark_circle'))
            .fontSize(18)
            .fontColor([(this.data as TrustLevelData).isStatusMet ? '#22C55E' : '#EF4444'])
            .margin({ right: 8 })
          Text((this.data as TrustLevelData).statusText)
            .fontSize(13)
            .fontColor((this.data as TrustLevelData).isStatusMet ? '#22C55E' : '#EF4444')
        }
        .margin({ top: 14 })
      }
    }
    .width('100%')
    .padding(20)
    .backgroundColor($r('app.color.card_background'))
    .borderRadius(20)
  }

  build() {
    HdsNavDestination() {
      Column() {
        this.TopBar()

        if (this.isLoading) {
          LoadingSpinner({ message: '正在获取信任要求...' })
            .layoutWeight(1)
        } else if (this.errorMessage.length > 0) {
          Column() {
            ErrorView({
              title: '加载失败',
              message: this.errorMessage,
              onRetry: () => {
                this.loadData(true).catch(() => {
                });
              }
            })
          }
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else if (this.data === null) {
          Column() {
            Text('暂无数据')
              .fontSize(14)
              .fontColor($r('app.color.on_surface_secondary'))
          }
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
        } else {
          Refresh({ refreshing: this.isRefreshing }) {
            Scroll() {
              Column() {
                this.HeaderCard()
                Blank().height(12)
                this.SectionCard('活跃度')
                Blank().height(12)
                this.SectionCard('互动')
                Blank().height(12)
                this.SectionCard('合规')
                Blank().height(12)
                this.FooterCard()
                Blank().height(24 + WindowManager.getSystemAvoidAreaBottomVp())
              }
              .width('100%')
              .padding({ left: 12, right: 12, top: 12 })
            }
            .width('100%')
            .layoutWeight(1)
          }
          .onRefreshing(() => {
            this.isRefreshing = true;
            this.loadData(false).catch(() => {
            });
          })
          .layoutWeight(1)
        }
      }
      .width('100%')
      .height('100%')
      .padding({ top: WindowManager.getSystemAvoidAreaTopVp() })
      .backgroundColor($r('app.color.background'))
    }
    .backgroundColor($r('app.color.background'))
    .hideTitleBar(true)
    .hideToolBar(true)
  }
}
