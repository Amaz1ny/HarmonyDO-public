import { SmartAvatar } from './SmartAvatar';
import { EmojiResolver } from '../../common/utils/EmojiResolver';

function normalizeHexColor(raw: string | null): string {
  if (raw === null || raw === undefined) return '';
  let s: string = raw.toString().trim();
  if (s.length === 0) return '';
  if (s.startsWith('#')) s = s.substring(1);

  // 支持 3 位 hex（如 FFF）
  if (s.length === 3) {
    s = `${s[0]}${s[0]}${s[1]}${s[1]}${s[2]}${s[2]}`;
  }

  // 仅接收 6 位 RGB（Discourse 常见）
  if (s.length === 6) {
    return `#${s}`;
  }
  return '';
}

function normalizeFaIconName(raw: string | null): string {
  if (raw === null) return '';
  const s: string = raw.trim().toLowerCase();
  if (s.length === 0) return '';

  const tokens: string[] = s.split(/\s+/);
  let last: string = '';
  for (let i = 0; i < tokens.length; i++) {
    let t: string = tokens[i].trim();
    if (t.length === 0) continue;
    if (
      t === 'fa-solid' || t === 'fa-regular' || t === 'fa-brands' || t === 'fa-light' || t === 'fa-thin' || t === 'fa-duotone'
      || t === 'fas' || t === 'far' || t === 'fab' || t === 'fal' || t === 'fat' || t === 'fad'
      || t === 'fa'
    ) {
      continue;
    }
    if (t.startsWith('fa-')) t = t.substring(3);
    if (t.startsWith('fas-')) t = t.substring(4);
    if (t.startsWith('far-')) t = t.substring(4);
    if (t.startsWith('fab-')) t = t.substring(4);
    last = t;
  }
  return last;
}

function getFlairSymbol(raw: string | null): Resource | null {
  const name: string = normalizeFaIconName(raw);
  if (name.length === 0) return null;

  switch (name) {
    case 'shield':
    case 'shield-halved':
      return $r('sys.symbol.security_shield');
    case 'leaf':
    case 'seedling':
    case 'sprout':
      return $r('sys.symbol.leaf');
    case 'award':
    case 'medal':
    case 'trophy':
      return $r('sys.symbol.medal');
    case 'star':
    case 'stars':
      return $r('sys.symbol.star');
    case 'check':
    case 'circle-check':
    case 'check-circle':
      return $r('sys.symbol.checkmark_circle');
    case 'user':
    case 'users':
    case 'user-group':
      return $r('sys.symbol.person');
    case 'code':
    case 'terminal':
    case 'file-code':
      return $r('sys.symbol.gearshape');
    default:
      return null;
  }
}

@ComponentV2
export struct FlairBadge {
  @Param flairUrl: string | null = null;
  @Param flairName: string | null = null;
  @Param flairBgColor: string | null = null;
  @Param flairColor: string | null = null;
  @Param badgeSize: number = 16;

  @Local private failed: boolean = false;

  private hasFlair(): boolean {
    return this.flairUrl !== null && (this.flairUrl as string).trim().length > 0;
  }

  private getFullUrl(): string {
    if (!this.hasFlair()) return '';
    return EmojiResolver.resolveFlairUrl(this.flairUrl);
  }

  private getInitialText(): string {
    const name: string = this.flairName !== null ? (this.flairName as string).trim() : '';
    if (name.length > 0) return name.substring(0, 1).toUpperCase();
    return '?';
  }

  private getIconSymbol(): Resource | null {
    const raw: string = this.flairUrl !== null && this.flairUrl !== undefined ? this.flairUrl.toString().trim() : '';
    if (raw.length === 0) return null;
    if (raw.startsWith(':') && raw.endsWith(':') && raw.length > 2) return null;
    if (raw.startsWith('http://') || raw.startsWith('https://') || raw.startsWith('//') || raw.startsWith('/')) {
      return null;
    }
    return getFlairSymbol(raw);
  }

  private getIconColorValue(): string {
    const fg: string = this.getFgColorValue();
    if (fg.length > 0) return fg;
    if (this.hasBgColor()) return '#FFFFFF';
    return '';
  }

  private getIconFontSize(): number {
    const baseSize: number = this.badgeSize;
    return this.hasBgColor() ? (baseSize * 0.6) : (baseSize * 0.8);
  }

  private getBgColorValue(): string {
    return normalizeHexColor(this.flairBgColor);
  }

  private getFgColorValue(): string {
    return normalizeHexColor(this.flairColor);
  }

  private hasBgColor(): boolean {
    return this.getBgColorValue().length > 0;
  }

  private getImageSize(): number {
    const baseSize: number = this.badgeSize;
    if (this.hasBgColor()) {
      return Math.max(8, baseSize * 0.7);
    }
    return baseSize;
  }

  build() {
    if (this.hasFlair()) {
      Row() {
        if (this.getFullUrl().length > 0 && !this.failed) {
          Image(this.getFullUrl())
            .width(this.getImageSize())
            .height(this.getImageSize())
            .objectFit(ImageFit.Contain)
            .onError(() => {
              this.failed = true;
            })
        } else if (this.getIconSymbol() !== null) {
          SymbolGlyph(this.getIconSymbol() as Resource)
            .fontSize(this.getIconFontSize())
            .fontColor([
              this.getIconColorValue().length > 0 ? this.getIconColorValue() : $r('app.color.on_surface_secondary')
            ])
        } else {
          Text(this.getInitialText())
            .fontSize(this.badgeSize * 0.6)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.getFgColorValue().length > 0 ? this.getFgColorValue() : $r('app.color.on_surface_tertiary'))
        }
      }
      .width(this.badgeSize)
      .height(this.badgeSize)
      .borderRadius(this.badgeSize / 2)
      .backgroundColor(this.hasBgColor() ? this.getBgColorValue() : Color.Transparent)
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
    }
  }
}

@ComponentV2
export struct AvatarWithFlair {
  @Param avatarUrl: string = '';
  @Param avatarSize: number = 36;
  @Param avatarRadius: number = -1;
  @Param fallbackText: string = '';
  @Param bgColor: string = '';

  @Param flairUrl: string | null = null;
  @Param flairName: string | null = null;
  @Param flairBgColor: string | null = null;
  @Param flairColor: string | null = null;
  @Param flairSize: number = 14;

  private hasFlair(): boolean {
    return this.flairUrl !== null && (this.flairUrl as string).trim().length > 0;
  }

  build() {
    Stack() {
      SmartAvatar({
        avatarUrl: this.avatarUrl,
        avatarSize: this.avatarSize,
        avatarRadius: this.avatarRadius,
        fallbackText: this.fallbackText,
        bgColor: this.bgColor
      })

      if (this.hasFlair()) {
        FlairBadge({
          flairUrl: this.flairUrl,
          flairName: this.flairName,
          flairBgColor: this.flairBgColor,
          flairColor: this.flairColor,
          badgeSize: this.flairSize
        })
          .position({
            x: Math.max(0, this.avatarSize - this.flairSize),
            y: Math.max(0, this.avatarSize - this.flairSize)
          })
      }
    }
    .width(this.avatarSize)
    .height(this.avatarSize)
  }
}
