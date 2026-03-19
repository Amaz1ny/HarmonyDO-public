import { hilog } from '@kit.PerformanceAnalysisKit';
import { image } from '@kit.ImageKit';
import { DownloadedImage, ImageDownloadService } from '../../common/utils/ImageDownloadService';

const TAG: string = 'AnimatedGifImage';

function stripFileScheme(uri: string): string {
  const raw: string = uri !== undefined && uri !== null ? uri.trim() : '';
  if (raw.startsWith('file://')) return raw.substring('file://'.length);
  return raw;
}

function clampDelayMs(rawMs: number): number {
  const n: number = rawMs !== undefined && rawMs !== null ? Math.round(rawMs) : 0;
  if (n <= 0) return 100;
  if (n < 50) return 50;
  if (n > 2000) return 2000;
  return n;
}

async function getDelayTimeListSafe(src: image.ImageSource): Promise<number[]> {
  return await new Promise<number[]>((resolve: (v: number[]) => void) => {
    try {
      src.getDelayTimeList((err: Object, list: number[]) => {
        if (err !== undefined && err !== null) {
          resolve([]);
          return;
        }
        if (list === undefined || list === null) {
          resolve([]);
          return;
        }
        resolve(list);
      });
    } catch (_) {
      resolve([]);
    }
  });
}

@ComponentV2
export struct AnimatedGifImage {
  @Param url: string = '';
  @Param imageSize: number = 36;
  @Param radius: number = -1;
  @Event onDecodeFailed: () => void = () => {
  };

  @Local private currentFrame: image.PixelMap | null = null;
  @Local private isAnimating: boolean = false;

  private frames: image.PixelMap[] = [];
  private delaysMs: number[] = [];
  private timerId: number = -1;
  private frameIndex: number = 0;
  private requestSeq: number = 0;
  private lastUrl: string = '';
  private decodeUnsupported: boolean = false;

  private getRadius(): number {
    if (this.radius >= 0) return this.radius;
    return this.imageSize / 2;
  }

  aboutToAppear(): void {
    this.loadAndPlay();
  }

  aboutToDisappear(): void {
    this.stopTimer();
    this.clearFrames();
  }

  @Monitor('url')
  onUrlChange(): void {
    this.loadAndPlay();
  }

  private stopTimer(): void {
    if (this.timerId >= 0) {
      clearTimeout(this.timerId);
      this.timerId = -1;
    }
  }

  private clearFrames(): void {
    this.frames = [];
    this.delaysMs = [];
    this.frameIndex = 0;
    this.currentFrame = null;
    this.isAnimating = false;
  }

  private scheduleNextFrame(seq: number): void {
    if (seq !== this.requestSeq) return;
    if (this.frames.length <= 1) {
      this.isAnimating = false;
      return;
    }

    const idx: number = this.frameIndex;
    const rawDelay: number = idx >= 0 && idx < this.delaysMs.length ? this.delaysMs[idx] : 100;
    const delay: number = clampDelayMs(rawDelay);
    this.isAnimating = true;

    this.timerId = setTimeout(() => {
      if (seq !== this.requestSeq) return;
      if (this.frames.length <= 1) {
        this.isAnimating = false;
        return;
      }
      const next: number = (this.frameIndex + 1) % this.frames.length;
      this.frameIndex = next;
      this.currentFrame = this.frames[next];
      this.scheduleNextFrame(seq);
    }, delay);
  }

  private async loadAndPlay(): Promise<void> {
    const rawUrl: string = this.url !== undefined && this.url !== null ? this.url.trim() : '';
    if (rawUrl !== this.lastUrl) {
      this.lastUrl = rawUrl;
      this.decodeUnsupported = false;
    }

    this.requestSeq = this.requestSeq + 1;
    const seq: number = this.requestSeq;

    this.stopTimer();
    this.clearFrames();

    if (rawUrl.length === 0) return;
    if (this.decodeUnsupported) return;

    try {
      const d: DownloadedImage = await ImageDownloadService.download(rawUrl);
      if (seq !== this.requestSeq) return;
      if (!d.ok || d.fileUri.length === 0) {
        this.onDecodeFailed();
        return;
      }

      const path: string = stripFileScheme(d.fileUri);
      const src: image.ImageSource = image.createImageSource(path);

      const frames: image.PixelMap[] = await src.createPixelMapList();
      const delays: number[] = await getDelayTimeListSafe(src);

      if (seq !== this.requestSeq) return;
      if (frames.length === 0) {
        // 解码失败：退化为静态图（不再反复尝试解码）
        this.decodeUnsupported = true;
        return;
      }

      this.frames = frames;
      this.delaysMs = delays;
      this.frameIndex = 0;
      this.currentFrame = frames[0];

      this.scheduleNextFrame(seq);
    } catch (err) {
      hilog.error(0x0000, TAG, 'Load gif failed: %{public}s', JSON.stringify(err));
      if (seq !== this.requestSeq) return;
      // 解码失败：退化为静态图（不再反复尝试解码）
      this.decodeUnsupported = true;
    }
  }

  build() {
    if (this.currentFrame !== null) {
      Image(this.currentFrame as image.PixelMap)
        .width(this.imageSize)
        .height(this.imageSize)
        .borderRadius(this.getRadius())
        .objectFit(ImageFit.Cover)
        .interpolation(ImageInterpolation.High)
    } else {
      // 兜底：先显示静态首帧（或加载失败的占位），避免空白
      Image(this.url)
        .width(this.imageSize)
        .height(this.imageSize)
        .borderRadius(this.getRadius())
        .objectFit(ImageFit.Cover)
        .interpolation(ImageInterpolation.Medium)
        .onError(() => {
          this.onDecodeFailed();
        })
    }
  }
}
