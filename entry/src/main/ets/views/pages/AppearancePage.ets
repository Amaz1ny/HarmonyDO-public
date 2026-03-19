import { HdsNavDestination } from '@kit.UIDesignKit';
import { AppSettingsService } from '../../services/storage/AppSettingsService';
import { RouterManager } from '../../common/utils/RouterManager';
import { ToastService } from '../../common/utils/ToastService';
import { WindowManager } from '../../common/utils/WindowManager';

const TOP_BAR_HEIGHT: number = 56;

@ComponentV2
export struct AppearancePage {
  @Local locale: string = 'system';
  @Local themeMode: string = 'system';
  @Local themeColor: string = 'blue';
  @Local iconVariant: string = 'classic';
  @Local fontFamily: string = 'system';
  @Local contentFontScale: number = 1;
  @Local readingPanguSpacing: boolean = false;

  private settingsListener: (() => void) | null = null;

  aboutToAppear(): void {
    this.attachSettingsListener();
  }

  aboutToDisappear(): void {
    if (this.settingsListener !== null) {
      AppSettingsService.getInstance().removeListener(this.settingsListener);
      this.settingsListener = null;
    }
  }

  private attachSettingsListener(): void {
    if (this.settingsListener !== null) {
      return;
    }
    this.settingsListener = () => {
      this.syncFromService();
    };
    AppSettingsService.getInstance().addListener(this.settingsListener);
    AppSettingsService.getInstance().ensureInit().then(() => {
      this.syncFromService();
    }).catch(() => {
    });
  }

  private syncFromService(): void {
    const appearance = AppSettingsService.getInstance().getAppearanceSettings();
    this.locale = appearance.locale;
    this.themeMode = appearance.themeMode;
    this.themeColor = appearance.themeColor;
    this.iconVariant = appearance.iconVariant;
    this.fontFamily = appearance.fontFamily;
    this.contentFontScale = appearance.contentFontScale;
    this.readingPanguSpacing = appearance.readingPanguSpacing;
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

      Text('外观设置')
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.on_surface'))
        .layoutWeight(1)
    }
    .width('100%')
    .height(TOP_BAR_HEIGHT)
    .padding({ left: 8, right: 8 })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private SectionTitle(title: string, icon: Resource) {
    Row() {
      SymbolGlyph(icon)
        .fontSize(16)
        .fontColor([AppSettingsService.getInstance().getPrimaryColor()])
        .margin({ right: 8 })
      Text(title)
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.on_surface'))
    }
    .margin({ top: 16, bottom: 10 })
  }

  @Builder
  private ChoiceChip(label: string, selected: boolean, onClick: () => void) {
    Row() {
      Text(label)
        .fontSize(12)
        .fontColor(selected ? AppSettingsService.getInstance().getPrimaryColor() : $r('app.color.on_surface_secondary'))
        .fontWeight(selected ? FontWeight.Medium : FontWeight.Regular)
    }
    .padding({ left: 12, right: 12, top: 8, bottom: 8 })
    .backgroundColor(selected ? AppSettingsService.getInstance().getPrimaryColorWithAlpha(0.12) : $r('app.color.surface_variant'))
    .borderRadius(16)
    .margin({ right: 8, bottom: 8 })
    .onClick(() => {
      onClick();
    })
  }

  @Builder
  private SettingCard(title: string, desc: string) {
    Column() {
      Text(title)
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
      Text(desc)
        .fontSize(12)
        .fontColor($r('app.color.on_surface_secondary'))
        .margin({ top: 4, bottom: 12 })
      this.SettingCardContent(title)
    }
    .width('100%')
    .padding(16)
    .backgroundColor($r('app.color.card_background'))
    .borderRadius(16)
    .margin({ bottom: 10 })
  }

  @Builder
  private SettingCardContent(title: string) {
    if (title === '语言') {
      Flex({ wrap: FlexWrap.Wrap }) {
        this.ChoiceChip('跟随系统', this.locale === 'system', () => {
          AppSettingsService.getInstance().setLocale('system').then(() => {
            ToastService.show('语言设置已保存，建议冷启动后查看完整生效结果');
          }).catch(() => {
          });
        })
        this.ChoiceChip('简体中文', this.locale === 'zh_CN', () => {
          AppSettingsService.getInstance().setLocale('zh_CN').then(() => {
            ToastService.show('语言设置已保存，建议冷启动后查看完整生效结果');
          }).catch(() => {
          });
        })
        this.ChoiceChip('English', this.locale === 'en_US', () => {
          AppSettingsService.getInstance().setLocale('en_US').then(() => {
            ToastService.show('当前仓库尚未补齐完整英文资源，设置会在后续资源补全后生效');
          }).catch(() => {
          });
        })
      }
    } else if (title === '主题模式') {
      Flex({ wrap: FlexWrap.Wrap }) {
        this.ChoiceChip('跟随系统', this.themeMode === 'system', () => {
          AppSettingsService.getInstance().setThemeMode('system').catch(() => {
          });
        })
        this.ChoiceChip('浅色', this.themeMode === 'light', () => {
          AppSettingsService.getInstance().setThemeMode('light').catch(() => {
          });
        })
        this.ChoiceChip('深色', this.themeMode === 'dark', () => {
          AppSettingsService.getInstance().setThemeMode('dark').catch(() => {
          });
        })
      }
    } else if (title === '主题色') {
      Row() {
        this.ColorSwatch('blue', '#0088CC')
        this.ColorSwatch('teal', '#0F8B8D')
        this.ColorSwatch('green', '#2E7D32')
        this.ColorSwatch('orange', '#F57C00')
        this.ColorSwatch('pink', '#D81B60')
        this.ColorSwatch('indigo', '#3949AB')
      }
      .width('100%')
    } else if (title === '应用图标') {
      Flex({ wrap: FlexWrap.Wrap }) {
        this.ChoiceChip('经典', this.iconVariant === 'classic', () => {
          AppSettingsService.getInstance().setIconVariant('classic').then(() => {
            ToastService.show('图标选项已保存，当前仓库暂未接入多图标资源，后续冷启动能力会继续补齐');
          }).catch(() => {
          });
        })
        this.ChoiceChip('现代', this.iconVariant === 'modern', () => {
          AppSettingsService.getInstance().setIconVariant('modern').then(() => {
            ToastService.show('图标选项已保存，当前仓库暂未接入多图标资源，后续冷启动能力会继续补齐');
          }).catch(() => {
          });
        })
      }
    } else if (title === '字体') {
      Flex({ wrap: FlexWrap.Wrap }) {
        this.ChoiceChip('系统默认', this.fontFamily === 'system', () => {
          AppSettingsService.getInstance().setFontFamily('system').catch(() => {
          });
        })
        this.ChoiceChip('衬线', this.fontFamily === 'serif', () => {
          AppSettingsService.getInstance().setFontFamily('serif').catch(() => {
          });
        })
        this.ChoiceChip('等宽', this.fontFamily === 'monospace', () => {
          AppSettingsService.getInstance().setFontFamily('monospace').catch(() => {
          });
        })
      }
    } else {
      Column() {
        Row() {
          Text('内容字号')
            .fontSize(13)
            .fontColor($r('app.color.on_surface_secondary'))
            .layoutWeight(1)
          Text(`${Math.round(this.contentFontScale * 100)}%`)
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
        }
        .width('100%')

        Row() {
          this.ChoiceChip('-5%', false, () => {
            AppSettingsService.getInstance().setContentFontScale(this.contentFontScale - 0.05).catch(() => {
            });
          })
          this.ChoiceChip('重置', false, () => {
            AppSettingsService.getInstance().setContentFontScale(1).catch(() => {
            });
          })
          this.ChoiceChip('+5%', false, () => {
            AppSettingsService.getInstance().setContentFontScale(this.contentFontScale + 0.05).catch(() => {
            });
          })
        }
        .margin({ top: 8 })

        Row() {
          Text('阅读盘古空格')
            .fontSize(13)
            .fontColor($r('app.color.on_surface_secondary'))
            .layoutWeight(1)
          Row() {
            Text(this.readingPanguSpacing ? '已开启' : '已关闭')
              .fontSize(12)
              .fontColor(this.readingPanguSpacing
                ? AppSettingsService.getInstance().getPrimaryColor()
                : $r('app.color.on_surface_secondary'))
          }
          .padding({ left: 12, right: 12, top: 7, bottom: 7 })
          .backgroundColor(this.readingPanguSpacing
            ? AppSettingsService.getInstance().getPrimaryColorWithAlpha(0.12)
            : $r('app.color.surface_variant'))
          .borderRadius(16)
          .onClick(() => {
            AppSettingsService.getInstance().setReadingPanguSpacing(!this.readingPanguSpacing).catch(() => {
            });
          })
        }
        .width('100%')
        .margin({ top: 12 })
      }
    }
  }

  @Builder
  private ColorSwatch(key: string, color: string) {
    Stack({ alignContent: Alignment.Center }) {
      Circle()
        .width(36)
        .height(36)
        .fill(color)
      if (this.themeColor === key) {
        SymbolGlyph($r('sys.symbol.checkmark'))
          .fontSize(14)
          .fontColor([Color.White])
      }
    }
    .margin({ right: 12 })
    .onClick(() => {
      AppSettingsService.getInstance().setThemeColor(key).catch(() => {
      });
    })
  }

  build() {
    HdsNavDestination() {
      Scroll() {
        Column() {
          this.TopBar()

          Column() {
            this.SectionTitle('通用', $r('sys.symbol.paintbrush'))
            this.SettingCard('语言', '切换后会写入设置，建议冷启动后检查完整资源表现')
            this.SettingCard('主题模式', '浅色、深色和跟随系统会立即应用到应用色彩模式')
            this.SettingCard('主题色', '主强调色会优先作用于首页、我的页、详情页和共享组件')
            this.SettingCard('应用图标', '图标方案会写入设置，当前仓库先按重启后生效口径交付')
            this.SettingCard('字体', '字体偏好会优先作用于阅读内容')

            this.SectionTitle('阅读', $r('sys.symbol.book'))
            this.SettingCard('阅读设置', '内容字号和阅读盘古空格会即时生效于阅读场景')
          }
          .width('100%')
          .padding({ left: 12, right: 12, bottom: 24 + WindowManager.getSystemAvoidAreaBottomVp() })
        }
        .width('100%')
        .padding({ top: WindowManager.getSystemAvoidAreaTopVp() })
        .backgroundColor($r('app.color.background'))
      }
      .backgroundColor($r('app.color.background'))
    }
    .backgroundColor($r('app.color.background'))
    .hideTitleBar(true)
    .hideToolBar(true)
  }
}
