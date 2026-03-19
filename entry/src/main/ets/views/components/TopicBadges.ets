import { Category } from '../../models/Category';

/**
 * 话题/分类/标签的徽章与图标映射（对齐 Flutter 端的 topic_badges.dart / tag_icon_list.dart）
 *
 * 说明：
 * - Discourse 分类 icon 字段通常是 FontAwesome 名称或 css-like class（如 "fa-solid fa-code"）。
 * - 鸿蒙端优先用系统 SymbolGlyph 做近似映射；未知 icon 退化为 null，由调用方决定兜底（logo/lock/dot）。
 */

function normalizeFaIconName(raw: string | null): string {
  if (raw === null) return '';
  const s: string = raw.trim().toLowerCase();
  if (s.length === 0) return '';

  // 解析 css-like class：fa-solid fa-code / fas fa-code 等
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

export class BadgeIconUtils {
  /**
   * 分类 icon -> sys.symbol 映射（尽量贴近安卓/Flutter）
   */
  static getCategorySymbol(category: Category, parent: Category | null = null): Resource | null {
    const own: string = normalizeFaIconName(category.icon);
    let name: string = own;
    if (name.length === 0 && parent !== null) {
      name = normalizeFaIconName((parent as Category).icon);
    }
    if (name.length === 0) return null;

    switch (name) {
      case 'code':
      case 'terminal':
      case 'file-code':
        return $r('sys.symbol.gearshape');
      case 'award':
      case 'medal':
      case 'trophy':
        return $r('sys.symbol.medal');
      case 'book-open-reader':
      case 'book-open':
        return $r('sys.symbol.notepad');
      case 'seedling':
      case 'leaf':
        return $r('sys.symbol.leaf');
      case 'share':
      case 'share-nodes':
      case 'square-share-nodes':
        return $r('sys.symbol.share');
      case 'file-lines':
      case 'doc':
      case 'book':
        return $r('sys.symbol.doc_text');
      case 'briefcase':
        return $r('sys.symbol.briefcase');
      case 'newspaper':
        return $r('sys.symbol.doc_text');
      case 'rss':
        return $r('sys.symbol.wifi');
      case 'piggy-bank':
      case 'gift':
        return $r('sys.symbol.gift');
      case 'droplet':
      case 'faucet':
        return $r('sys.symbol.drop');
      case 'clone':
      case 'hard-drive':
      case 'database':
      case 'server':
        return $r('sys.symbol.archivebox');
      case 'hurricane':
      case 'wind':
        return $r('sys.symbol.compass');
      case 'users':
      case 'user-group':
      case 'user':
        return $r('sys.symbol.person');
      case 'bullhorn':
      case 'megaphone':
        return $r('sys.symbol.bell');
      case 'comments':
      case 'comment':
        return $r('sys.symbol.message');
      default:
        return null;
    }
  }

  /**
   * 标签名 -> 图标映射（覆盖常见中文标签；未知返回 null）
   */
  static getTagSymbol(tagName: string): Resource | null {
    const key: string = tagName.trim();
    if (key.length === 0) return null;

    switch (key) {
      // ── 中文标签 ──
      case '公告':
      case '公益推广':
      case '推广':
        return $r('sys.symbol.bell');
      case '精华神帖':
      case '优质博文':
        return $r('sys.symbol.hand_thumbsup');
      case '快问快答':
        return $r('sys.symbol.questionmark_circle');
      case '纯水':
      case '碎碎碎念':
      case '搞七捡三':
      case '搞七捻三':
        return $r('sys.symbol.drop');
      case '禁水':
        return $r('sys.symbol.lock');
      case '人工智能':
        return $r('sys.symbol.robot');
      case '软件开发':
      case '配置优化':
        return $r('sys.symbol.gearshape');
      case '软件测试':
        return $r('sys.symbol.checkmark_square_fill');
      case '树洞':
        return $r('sys.symbol.leaf');
      case '危险':
        return $r('sys.symbol.exclamationmark_triangle');
      case '羊毛':
      case '抽奖':
      case '福利':
        return $r('sys.symbol.gift');
      // ── 英文标签（linux.do 常见）──
      case 'bug':
        return $r('sys.symbol.exclamationmark_triangle');
      case 'ai':
      case 'chatgpt':
      case 'llm':
      case 'gpt':
        return $r('sys.symbol.robot');
      case 'resource':
      case 'resources':
        return $r('sys.symbol.archivebox');
      case 'tips':
      case 'tutorial':
      case 'guide':
        return $r('sys.symbol.lightbulb');
      case 'help':
      case 'question':
        return $r('sys.symbol.questionmark_circle');
      case 'showcase':
      case 'demo':
        return $r('sys.symbol.star');
      case 'release':
        return $r('sys.symbol.flag');
      case 'design':
      case 'ui':
      case 'ux':
        return $r('sys.symbol.pencil_line');
      case 'harmonyos':
      case 'harmony':
      case 'arkts':
      case 'arkui':
      case 'openharmony':
        return $r('sys.symbol.gearshape');
      case 'flutter':
      case 'dart':
        return $r('sys.symbol.leaf');
      case 'news':
      case 'announcement':
        return $r('sys.symbol.bell');
      case 'tool':
      case 'tools':
        return $r('sys.symbol.wrench_and_screwdriver');
      case 'open-source':
      case 'opensource':
        return $r('sys.symbol.person');
      case 'discussion':
        return $r('sys.symbol.message');
      case 'free':
      case 'welfare':
        return $r('sys.symbol.gift');
      case 'solved':
      case 'solution':
        return $r('sys.symbol.checkmark_circle');
      default:
        return null;
    }
  }

  /**
   * 标签名 -> 颜色（尽量用资源色；未知退回 on_surface_secondary）
   */
  static getTagColor(tagName: string): Resource {
    const key: string = tagName.trim();
    switch (key) {
      case '公告':
      case '精华神帖':
      case '碎碎碎念':
      case '优质博文':
        return $r('app.color.primary');
      case '快问快答':
      case '软件开发':
      case '配置优化':
      case '树洞':
      case 'tips':
      case 'tutorial':
      case 'guide':
      case 'solved':
      case 'solution':
        return $r('app.color.success');
      case '纯水':
      case '病友':
      case '抽奖':
      case '搞七捡三':
      case '搞七捻三':
      case '羊毛':
      case '福利':
      case 'free':
      case 'welfare':
        return $r('app.color.warning');
      case '人工智能':
      case 'ai':
      case 'chatgpt':
      case 'llm':
      case 'gpt':
        return $r('app.color.tag_purple');
      case '危险':
      case '封禁':
      case '禁水':
      case 'bug':
        return $r('app.color.error');
      default:
        return $r('app.color.on_surface_secondary');
    }
  }
}

@ComponentV2
export struct TagBadge {
  @Param name: string = '';
  @Param fontSize: number | Resource = $r('app.float.font_small');
  @Param iconSize: number = 12;
  @Param radius: number | Resource = $r('app.float.tag_radius');
  @Param paddingH: number = 6;
  @Param paddingV: number = 3;
  @Param bgColor: Resource | Color = $r('app.color.tag_background');

  build() {
    Row() {
      if (BadgeIconUtils.getTagSymbol(this.name) !== null) {
        SymbolGlyph(BadgeIconUtils.getTagSymbol(this.name) as Resource)
          .fontSize(this.iconSize)
          .fontColor([BadgeIconUtils.getTagColor(this.name)])
          .margin({ right: 4 })
      }
      Text(this.name)
        .fontSize(this.fontSize)
        .fontColor($r('app.color.on_surface_secondary'))
    }
    .padding({ left: this.paddingH, right: this.paddingH, top: this.paddingV, bottom: this.paddingV })
    .backgroundColor(this.bgColor)
    .borderRadius(this.radius)
    .alignItems(VerticalAlign.Center)
  }
}
