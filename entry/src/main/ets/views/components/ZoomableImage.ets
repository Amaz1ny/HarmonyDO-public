/**
 * 可缩放图片（Pinch + Pan + DoubleTap）
 * 用于 ImagePreviewPage：对齐安卓端“点图可放大/拖拽”的体验。
 */
@ComponentV2
export struct ZoomableImage {
  @Param url: string = '';
  @Param minScale: number = 1;
  @Param maxScale: number = 4;
  @Event onScaleChange: (scale: number) => void = () => {
  };
  @Event onLongPress: () => void = () => {
  };

  @Local private zoomScale: number = 1;
  @Local private translateX: number = 0;
  @Local private translateY: number = 0;

  private pinchStartScale: number = 1;
  private panStartX: number = 0;
  private panStartY: number = 0;

  aboutToAppear(): void {
    this.reset();
  }

  private clamp(v: number, min: number, max: number): number {
    if (v < min) return min;
    if (v > max) return max;
    return v;
  }

  private reset(): void {
    this.zoomScale = this.minScale;
    this.translateX = 0;
    this.translateY = 0;
    this.pinchStartScale = this.zoomScale;
    this.panStartX = 0;
    this.panStartY = 0;
    this.onScaleChange(this.zoomScale);
  }

  private toggleZoom(): void {
    if (this.zoomScale > this.minScale + 0.01) {
      this.reset();
      return;
    }
    // 默认双击放大到 2x（受 maxScale 限制）
    const target: number = this.clamp(2, this.minScale, this.maxScale);
    this.zoomScale = target;
    this.translateX = 0;
    this.translateY = 0;
    this.pinchStartScale = this.zoomScale;
    this.onScaleChange(this.zoomScale);
  }

  private onPinchStart(): void {
    this.pinchStartScale = this.zoomScale;
  }

  private onPinchUpdate(event: Object): void {
    try {
      const e: Record<string, Object> = event as Record<string, Object>;
      const scaleVal: Object | undefined = e['scale'];
      const delta: number = scaleVal !== undefined && scaleVal !== null ? Number(scaleVal.toString()) : 1;
      const next: number = this.clamp(this.pinchStartScale * delta, this.minScale, this.maxScale);
      this.zoomScale = next;
      this.onScaleChange(this.zoomScale);
    } catch (_) {
    }
  }

  private onPinchEnd(): void {
    if (this.zoomScale <= this.minScale + 0.001) {
      this.reset();
    } else {
      this.pinchStartScale = this.zoomScale;
      this.onScaleChange(this.zoomScale);
    }
  }

  private onPanStart(): void {
    this.panStartX = this.translateX;
    this.panStartY = this.translateY;
  }

  private onPanUpdate(event: Object): void {
    // 未放大时不处理拖拽，避免与 Swiper 横滑冲突
    if (this.zoomScale <= this.minScale + 0.01) return;
    try {
      const e: Record<string, Object> = event as Record<string, Object>;
      const dxVal: Object | undefined = e['offsetX'];
      const dyVal: Object | undefined = e['offsetY'];
      const dx: number = dxVal !== undefined && dxVal !== null ? Number(dxVal.toString()) : 0;
      const dy: number = dyVal !== undefined && dyVal !== null ? Number(dyVal.toString()) : 0;
      this.translateX = this.panStartX + dx;
      this.translateY = this.panStartY + dy;
    } catch (_) {
    }
  }

  private onPanEnd(): void {
    if (this.zoomScale <= this.minScale + 0.001) {
      this.translateX = 0;
      this.translateY = 0;
    }
  }

  build() {
    Stack() {
      Image(this.url)
        .width('100%')
        .height('100%')
        .objectFit(ImageFit.Contain)
        .interpolation(ImageInterpolation.High)
        .draggable(false)
        .enableAnalyzer(false)
        .translate({ x: this.translateX, y: this.translateY })
        .scale({ x: this.zoomScale, y: this.zoomScale })
    }
    .width('100%')
    .height('100%')
    .clip(true)
    .gesture(
      GestureGroup(GestureMode.Parallel,
        PinchGesture({ fingers: 2 })
          .onActionStart(() => {
            this.onPinchStart();
          })
          .onActionUpdate((event: Object) => {
            this.onPinchUpdate(event);
          })
          .onActionEnd(() => {
            this.onPinchEnd();
          }),
        PanGesture({ direction: PanDirection.All })
          .onActionStart(() => {
            this.onPanStart();
          })
          .onActionUpdate((event: Object) => {
            this.onPanUpdate(event);
          })
          .onActionEnd(() => {
            this.onPanEnd();
          }),
        TapGesture({ count: 2 })
          .onAction(() => {
            this.toggleZoom();
          }),
        LongPressGesture()
          .onAction(() => {
            this.onLongPress();
          })
      )
    )
  }
}
