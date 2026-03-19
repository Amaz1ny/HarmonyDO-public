/**
 * AnimatedGradientBackground
 *
 * 鸿蒙端复刻 Flutter/安卓的 AnimatedGradientBackground（流体渐变动效）。
 * 目标：在 UserProfilePage 头图背景中实现“极光/流体”效果：
 * - 线性渐变打底
 * - 多个径向渐变色块按不同相位/速度流动
 * - 叠加高光
 *
 * 参考（Flutter 真值）：d:\harmony\fluxdo-main\lib\widgets\common\animated_gradient_background.dart
 */

interface RgbColor {
  r: number;
  g: number;
  b: number;
}

interface BlobConfig {
  speedMultiplier: number;
  phaseOffset: number;
  colorIndex: number;
  radius: number;
  opacity: number;
  baseX: number;
  baseY: number;
  moveX: number;
  moveY: number;
}

const LOOP_DURATION_MS: number = 20000;
const FRAME_INTERVAL_MS: number = 16;

const DEFAULT_COLORS: string[] = [
  '#0f0c29', // 深紫底色
  '#6366f1', // 靛蓝色
  '#8b5cf6', // 紫色
  '#ec4899', // 粉色
  '#06b6d4' // 青色
];

const BLOB_CONFIGS: BlobConfig[] = [
  { speedMultiplier: 1, phaseOffset: 0.0, colorIndex: 1, radius: 1.2, opacity: 0.7, baseX: 0.3, baseY: 0.2, moveX: 0.4, moveY: 0.3 },
  { speedMultiplier: 2, phaseOffset: 0.25, colorIndex: 2, radius: 1.0, opacity: 0.6, baseX: 0.7, baseY: 0.6, moveX: 0.3, moveY: 0.4 },
  { speedMultiplier: 3, phaseOffset: 0.5, colorIndex: 3, radius: 0.9, opacity: 0.5, baseX: 0.2, baseY: 0.8, moveX: 0.35, moveY: 0.25 },
  { speedMultiplier: 2, phaseOffset: 0.75, colorIndex: 4, radius: 0.8, opacity: 0.5, baseX: 0.8, baseY: 0.2, moveX: 0.25, moveY: 0.35 }
];

const HIGHLIGHT_CONFIGS: BlobConfig[] = [
  { speedMultiplier: 2, phaseOffset: 0.33, colorIndex: 1, radius: 0.5, opacity: 0.4, baseX: 0.5, baseY: 0.4, moveX: 0.2, moveY: 0.2 },
  { speedMultiplier: 1, phaseOffset: 0.67, colorIndex: 3, radius: 0.4, opacity: 0.35, baseX: 0.3, baseY: 0.6, moveX: 0.2, moveY: 0.2 }
];

function clamp01(v: number): number {
  return Math.max(0, Math.min(1, v));
}

function hexToRgb(hex: string): RgbColor {
  let c: string = hex;
  if (c.startsWith('#')) c = c.substring(1);
  if (c.length !== 6) return { r: 0, g: 0, b: 0 };
  const r: number = parseInt(c.substring(0, 2), 16);
  const g: number = parseInt(c.substring(2, 4), 16);
  const b: number = parseInt(c.substring(4, 6), 16);
  return { r: r, g: g, b: b };
}

function lerp(a: number, b: number, t: number): number {
  return a + (b - a) * t;
}

function lerpHexColor(hexA: string, hexB: string, t: number): string {
  const a: RgbColor = hexToRgb(hexA);
  const b: RgbColor = hexToRgb(hexB);
  const tt: number = clamp01(t);
  const rr: number = Math.round(lerp(a.r, b.r, tt));
  const gg: number = Math.round(lerp(a.g, b.g, tt));
  const bb: number = Math.round(lerp(a.b, b.b, tt));
  const rHex: string = rr.toString(16).padStart(2, '0');
  const gHex: string = gg.toString(16).padStart(2, '0');
  const bHex: string = bb.toString(16).padStart(2, '0');
  return `#${rHex}${gHex}${bHex}`;
}

function rgba(hex: string, alpha: number): string {
  const c: RgbColor = hexToRgb(hex);
  const a: number = clamp01(alpha);
  return `rgba(${c.r},${c.g},${c.b},${a})`;
}

const BASE_GRADIENT_COLOR_0: string = DEFAULT_COLORS[0];
const BASE_GRADIENT_COLOR_1: string = lerpHexColor(DEFAULT_COLORS[0], DEFAULT_COLORS[1], 0.3);

@ComponentV2
export struct AnimatedGradientBackground {
  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private context: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);
  private timerId: number = -1;
  private startTimeMs: number = 0;

  private canvasWidth: number = 0;
  private canvasHeight: number = 0;

  aboutToDisappear(): void {
    this.stop();
  }

  build() {
    Canvas(this.context)
      .width('100%')
      .height('100%')
      .onReady(() => {
        this.canvasWidth = this.context.width;
        this.canvasHeight = this.context.height;
        this.start();
      })
  }

  private start(): void {
    if (this.timerId >= 0) return;
    this.startTimeMs = Date.now();
    this.drawFrame(Date.now());
    this.timerId = setInterval(() => {
      this.drawFrame(Date.now());
    }, FRAME_INTERVAL_MS);
  }

  private stop(): void {
    if (this.timerId < 0) return;
    clearInterval(this.timerId);
    this.timerId = -1;
  }

  private drawFrame(nowMs: number): void {
    const w: number = this.context.width;
    const h: number = this.context.height;
    if (w <= 0 || h <= 0) return;

    if (this.canvasWidth !== w || this.canvasHeight !== h) {
      this.canvasWidth = w;
      this.canvasHeight = h;
    }

    const elapsed: number = (nowMs - this.startTimeMs) % LOOP_DURATION_MS;
    const animValue: number = elapsed / LOOP_DURATION_MS;

    // 1) 底色线性渐变
    this.context.globalCompositeOperation = 'source-over';
    // 注意：不做 clearRect，避免在高负载（如滚动）时出现“先清空后绘制”之间的可见闪烁。
    const baseAngle: number = animValue * 2 * Math.PI;
    const shiftX: number = Math.sin(baseAngle) * w * 0.12;
    const shiftY: number = Math.cos(baseAngle) * h * 0.12;
    const baseGrad = this.context.createLinearGradient(shiftX, shiftY, w + shiftX, h + shiftY);
    baseGrad.addColorStop(0.0, BASE_GRADIENT_COLOR_0);
    baseGrad.addColorStop(1.0, BASE_GRADIENT_COLOR_1);
    this.context.fillStyle = baseGrad;
    this.context.fillRect(0, 0, w, h);

    // 2) 色块叠加（加色，贴近 Flutter BlendMode.plus）
    this.context.globalCompositeOperation = 'lighter';
    for (let i = 0; i < BLOB_CONFIGS.length; i++) {
      this.drawColorBlob(animValue, BLOB_CONFIGS[i]);
    }

    // 3) 高光
    for (let i = 0; i < HIGHLIGHT_CONFIGS.length; i++) {
      this.drawHighlight(animValue, HIGHLIGHT_CONFIGS[i]);
    }

    this.context.globalCompositeOperation = 'source-over';
  }

  private drawColorBlob(animValue: number, cfg: BlobConfig): void {
    const w: number = this.canvasWidth;
    const h: number = this.canvasHeight;
    if (w <= 0 || h <= 0) return;

    const phase: number = (animValue * cfg.speedMultiplier + cfg.phaseOffset) % 1.0;
    const angle: number = phase * 2 * Math.PI;

    const cx: number = (cfg.baseX + Math.sin(angle) * cfg.moveX) * w;
    const cy: number = (cfg.baseY + Math.cos(angle) * cfg.moveY) * h;
    const breathe: number = 0.92 + 0.08 * Math.sin(angle * 1.7 + cfg.phaseOffset * 2 * Math.PI);
    const radius: number = cfg.radius * breathe * Math.min(w, h);

    const grad = this.context.createRadialGradient(cx, cy, 0, cx, cy, radius);
    const color: string = DEFAULT_COLORS[cfg.colorIndex];
    grad.addColorStop(0.0, rgba(color, cfg.opacity));
    grad.addColorStop(0.4, rgba(color, cfg.opacity * 0.5));
    grad.addColorStop(1.0, rgba(color, 0));
    this.context.fillStyle = grad;
    // 只填充本色块的圆形区域，减少全屏 fillRect 带来的重绘负担（滚动时更稳）
    this.context.beginPath();
    this.context.arc(cx, cy, radius, 0, 2 * Math.PI, true);
    this.context.closePath();
    this.context.fill();
  }

  private drawHighlight(animValue: number, cfg: BlobConfig): void {
    const w: number = this.canvasWidth;
    const h: number = this.canvasHeight;
    if (w <= 0 || h <= 0) return;

    const phase: number = (animValue * cfg.speedMultiplier + cfg.phaseOffset) % 1.0;
    const angle: number = phase * 2 * Math.PI;

    const cx: number = (cfg.baseX + Math.sin(angle) * cfg.moveX) * w;
    const cy: number = (cfg.baseY + Math.cos(angle + Math.PI / 3) * cfg.moveY) * h;
    const breathe: number = 0.92 + 0.08 * Math.sin(angle * 1.9 + cfg.phaseOffset * 2 * Math.PI);
    const radius: number = cfg.radius * breathe * Math.min(w, h);

    const grad = this.context.createRadialGradient(cx, cy, 0, cx, cy, radius);
    const color: string = DEFAULT_COLORS[cfg.colorIndex];
    grad.addColorStop(0.0, rgba(color, cfg.opacity));
    grad.addColorStop(1.0, rgba(color, 0));
    this.context.fillStyle = grad;
    this.context.beginPath();
    this.context.arc(cx, cy, radius, 0, 2 * Math.PI, true);
    this.context.closePath();
    this.context.fill();
  }
}
