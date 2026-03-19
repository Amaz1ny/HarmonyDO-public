/**
 * 话题列表骨架屏（游客态 UI 对齐阶段）
 *
 * 目标：
 * - 替代居中 LoadingSpinner，进入即呈现列表结构，减少布局跳动
 * - 轻量呼吸动效（不依赖业务，不引入额外依赖）
 */

@ComponentV2
export struct TopicListSkeleton {
  @Param itemCount: number = 8;

  @Local private _pulse: number = 0;
  private _timerId: number = -1;

  aboutToAppear(): void {
    this.startPulse();
  }

  aboutToDisappear(): void {
    this.stopPulse();
  }

  private startPulse(): void {
    this.stopPulse();
    this._timerId = setInterval(() => {
      const next: number = this._pulse < 0.5 ? 1 : 0;
      const uiContext = this.getUIContext();
      if (uiContext !== undefined && uiContext !== null) {
        uiContext.animateTo({ duration: 650, curve: Curve.EaseInOut }, () => {
          this._pulse = next;
        });
      } else {
        this._pulse = next;
      }
    }, 700);
  }

  private stopPulse(): void {
    if (this._timerId >= 0) {
      clearInterval(this._timerId);
      this._timerId = -1;
    }
  }

  private getBlockOpacity(): number {
    return 0.55 + 0.35 * this._pulse;
  }

  @Builder
  SkeletonItem() {
    Row() {
      // 头像占位
      Circle()
        .width(34)
        .height(34)
        .fill($r('app.color.skeleton_base'))
        .opacity(this.getBlockOpacity())
        .margin({ top: 2 })

      // 右侧内容占位
      Column() {
        // 标题两行
        Rect()
          .width('78%')
          .height(16)
          .radius(4)
          .fill($r('app.color.skeleton_base'))
          .opacity(this.getBlockOpacity())
        Rect()
          .width('56%')
          .height(16)
          .radius(4)
          .fill($r('app.color.skeleton_base'))
          .opacity(this.getBlockOpacity())
          .margin({ top: 8 })

        // 元信息行
        Row() {
          Rect()
            .width(64)
            .height(14)
            .radius(7)
            .fill($r('app.color.skeleton_base'))
            .opacity(this.getBlockOpacity())
          Rect()
            .width(54)
            .height(14)
            .radius(7)
            .fill($r('app.color.skeleton_base'))
            .opacity(this.getBlockOpacity())
            .margin({ left: 8 })
          Blank().layoutWeight(1)
          Rect()
            .width(88)
            .height(14)
            .radius(7)
            .fill($r('app.color.skeleton_base'))
            .opacity(this.getBlockOpacity())
        }
        .width('100%')
        .margin({ top: 10 })
        .alignItems(VerticalAlign.Center)
      }
      .layoutWeight(1)
      .margin({ left: 12 })
    }
    .width('100%')
    .padding(16)
    .backgroundColor($r('app.color.card_background'))
    .borderRadius(12)
    .margin({ bottom: 10 })
  }

  private buildIndexList(): number[] {
    const items: number[] = [];
    for (let i: number = 0; i < this.itemCount; i++) {
      items.push(i);
    }
    return items;
  }

  build() {
    Column() {
      ForEach(this.buildIndexList(), (i: number) => {
        this.SkeletonItem()
      }, (i: number) => i.toString())
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 8 })
  }
}
