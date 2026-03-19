/**
 * 加载指示器组件
 */
@ComponentV2
export struct LoadingSpinner {
  @Param message: string = '';

  build() {
    Column() {
      LoadingProgress()
        .width(48)
        .height(48)
        .color($r('app.color.primary'))

      if (this.message.length > 0) {
        Text(this.message)
          .fontSize($r('app.float.text_size_normal'))
          .fontColor($r('app.color.on_surface_secondary'))
          .margin({ top: 12 })
      }
    }
    .width('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .padding(24)
  }
}
