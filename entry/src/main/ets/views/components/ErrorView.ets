/**
 * 错误视图组件 — 100% 复刻安卓版 ErrorView
 *
 * 布局：
 * - 错误图标（红色警告图标，48px）
 * - 标题文字（加粗，如"加载失败"）
 * - 描述文字（灰色，如具体错误信息）
 * - 重试按钮（FilledButton 带刷新图标）+ 查看详情（OutlinedButton）
 *
 * 对应 Flutter: ErrorView(error, onRetry, title, showDetails)
 */
@ComponentV2
export struct ErrorView {
  @Param title: string | Resource = $r('app.string.load_failed');
  @Param message: string = '请检查网络连接后重试';
  @Param showRetry: boolean = true;
  @Event onRetry: () => void = () => {};

  build() {
    Column() {
      // 错误图标
      SymbolGlyph($r('sys.symbol.info_circle'))
        .fontSize(48)
        .fontColor([$r('app.color.error')])
        .margin({ bottom: 16 })

      // 标题
      Text(this.title)
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.on_surface'))
        .margin({ bottom: 8 })

      // 描述信息
      Text(this.message)
        .fontSize(14)
        .fontColor($r('app.color.on_surface_secondary'))
        .textAlign(TextAlign.Center)
        .margin({ bottom: 24 })

      // 按钮行
      if (this.showRetry) {
        Row() {
          // 重试按钮（FilledButton 风格）
          Button() {
            Row() {
              SymbolGlyph($r('sys.symbol.arrow_clockwise'))
                .fontSize(18)
                .fontColor([Color.White])
                .margin({ right: 6 })
              Text($r('app.string.retry'))
                .fontSize(14)
                .fontColor(Color.White)
            }
          }
          .backgroundColor($r('app.color.primary'))
          .borderRadius(20)
          .height(40)
          .padding({ left: 20, right: 20 })
          .onClick(() => {
            this.onRetry();
          })
        }
        .justifyContent(FlexAlign.Center)
      }
    }
    .width('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .padding(24)
  }
}
