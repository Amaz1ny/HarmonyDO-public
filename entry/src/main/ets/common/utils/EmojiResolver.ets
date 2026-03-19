import { UrlUtils } from './UrlUtils';

/**
 * Emoji / Flair URL 解析（对齐 FluxDO）
 *
 * 用途：
 * - user_status.emoji（如 ":eyes:" / "eyes"） -> emoji 图片 URL
 * - flair_url 可能是 URL/相对路径/emoji 名称 -> 图片 URL
 *
 * 备注：
 * - 优先使用站点 custom emoji 映射（从 /site.json 提取）
 * - 未命中 custom emoji 时，回退到 twitter 标准路径
 */
export class EmojiResolver {
  private static customEmojiMap: Map<string, string> = new Map();
  private static hasConfigured: boolean = false;

  private static isAsciiEmojiName(name: string): boolean {
    const s: string = name !== undefined && name !== null ? name.toString().trim() : '';
    if (s.length === 0) return false;
    for (let i = 0; i < s.length; i++) {
      if (s.charCodeAt(i) > 127) return false;
    }
    // Discourse emoji shortname 通常为 a-z0-9_+-.
    const re: RegExp = /^[a-z0-9_+\-.]+$/i;
    return re.test(s);
  }

  private static normalizeEmojiName(raw: string): string {
    let s: string = raw !== undefined && raw !== null ? raw.trim() : '';
    if (s.length === 0) return '';
    if (s.startsWith(':') && s.endsWith(':') && s.length > 2) {
      s = s.substring(1, s.length - 1);
    }
    return s.trim().toLowerCase();
  }

  private static putCustomEmoji(next: Map<string, string>, nameRaw: string, urlRaw: string): void {
    const name: string = EmojiResolver.normalizeEmojiName(nameRaw);
    const url: string = urlRaw !== undefined && urlRaw !== null ? urlRaw.toString().trim() : '';
    if (name.length === 0 || url.length === 0) return;
    if (!next.has(name)) {
      next.set(name, url);
    }
  }

  /**
   * 从 /site.json 提取 custom emoji 映射
   * 兼容结构：
   * - custom_emoji: { name: url, ... }
   * - custom_emoji: [{ name, url }, ...]
   */
  static configureFromSiteJson(json: Record<string, Object>): void {
    if (json === null || json === undefined) return;
    try {
      const next: Map<string, string> = new Map();
      const candidates: Object[] = [];

      // /site.json 常见结构：custom_emoji 位于 site 子对象内
      const siteVal: Object | undefined = json['site'];
      if (siteVal !== undefined && siteVal !== null && typeof siteVal === 'object') {
        candidates.push(siteVal);
      }

      const v1: Object | undefined = json['custom_emoji'];
      if (v1 !== undefined && v1 !== null) {
        candidates.push(v1);
      }
      const v2: Object | undefined = json['customEmoji'];
      if (v2 !== undefined && v2 !== null) {
        candidates.push(v2);
      }
      const v3: Object | undefined = json['custom_emojis'];
      if (v3 !== undefined && v3 !== null) {
        candidates.push(v3);
      }
      const v4: Object | undefined = json['customEmojis'];
      if (v4 !== undefined && v4 !== null) {
        candidates.push(v4);
      }

      for (let i = 0; i < candidates.length; i++) {
        const c: Object = candidates[i];
        if (Array.isArray(c)) {
          const arr: Object[] = c as Object[];
          for (let j = 0; j < arr.length; j++) {
            const item: Object = arr[j];
            if (item === null || item === undefined || typeof item !== 'object') continue;
            const obj: Record<string, Object> = item as Record<string, Object>;
            const nameVal: Object | undefined = obj['name'];
            const urlVal: Object | undefined = obj['url'];
            if (nameVal !== undefined && nameVal !== null && urlVal !== undefined && urlVal !== null) {
              EmojiResolver.putCustomEmoji(next, nameVal.toString(), urlVal.toString());
            }
          }
          continue;
        }

        if (typeof c === 'object') {
          const obj: Record<string, Object> = c as Record<string, Object>;
          const keys: string[] = Object.keys(obj);
          for (let j = 0; j < keys.length; j++) {
            const key: string = keys[j];
            const val: Object | undefined = obj[key];
            if (val === undefined || val === null) continue;
            if (typeof val === 'string') {
              EmojiResolver.putCustomEmoji(next, key, val as string);
              continue;
            }
            if (typeof val === 'object') {
              const vObj: Record<string, Object> = val as Record<string, Object>;
              const urlVal: Object | undefined = vObj['url'];
              if (urlVal !== undefined && urlVal !== null) {
                EmojiResolver.putCustomEmoji(next, key, urlVal.toString());
              }
            }
          }
        }
      }

      if (next.size > 0) {
        EmojiResolver.customEmojiMap = next;
        EmojiResolver.hasConfigured = true;
      }
    } catch (_) {
    }
  }

  private static isUrlLike(raw: string): boolean {
    const s: string = raw.trim();
    if (s.length === 0) return false;
    if (s.startsWith('http://') || s.startsWith('https://')) return true;
    if (s.startsWith('//')) return true;
    if (s.startsWith('/')) return true;
    return false;
  }

  /**
   * 解析 emoji 名称 -> 图片 URL
   * - 支持 ":name:" / "name"
   * - 支持直接传 URL/相对路径（原样 resolve）
   */
  static resolveEmojiUrl(emoji: string | null): string {
    const raw: string = emoji !== null && emoji !== undefined ? emoji.toString().trim() : '';
    if (raw.length === 0) return '';

    if (EmojiResolver.isUrlLike(raw)) {
      return UrlUtils.resolveUrl(raw);
    }

    const name: string = EmojiResolver.normalizeEmojiName(raw);
    if (name.length === 0) return '';

    // Unicode emoji（如 🤷‍♀️）不走图片路径，交给 UI 文本兜底，避免拼出无效 URL
    if (!EmojiResolver.isAsciiEmojiName(name)) {
      return '';
    }

    if (EmojiResolver.hasConfigured && EmojiResolver.customEmojiMap.has(name)) {
      const mapped: string = EmojiResolver.customEmojiMap.get(name) as string;
      return UrlUtils.resolveUrl(mapped);
    }

    // 标准 twitter emoji 路径（Discourse 默认）
    return UrlUtils.resolveUrl(`/images/emoji/twitter/${name}.png?v=12`);
  }

  /**
   * flair_url 解析：
   * - URL/相对路径：resolveUrl
   * - :emoji:：按 emoji 解析
   * - 其它非 URL：视为 iconName（返回空，交由 UI 做最小 sys.symbol 映射兜底）
   */
  static resolveFlairUrl(flairUrl: string | null): string {
    const raw: string = flairUrl !== null && flairUrl !== undefined ? flairUrl.toString().trim() : '';
    if (raw.length === 0) return '';
    if (EmojiResolver.isUrlLike(raw)) {
      return UrlUtils.resolveUrl(raw);
    }
    if (raw.startsWith(':') && raw.endsWith(':') && raw.length > 2) {
      return EmojiResolver.resolveEmojiUrl(raw);
    }
    return '';
  }
}
