import { util } from '@kit.ArkTS';
import { webview } from '@kit.ArkWeb';
import { UrlUtils } from '../../common/utils/UrlUtils';
import { EmojiResolver } from '../../common/utils/EmojiResolver';
import { ClipboardService } from '../../common/utils/ClipboardService';
import { ToastService } from '../../common/utils/ToastService';
import { TimeUtils } from '../../common/utils/TimeUtils';
import { AppConstants } from '../../common/constants/AppConstants';
import { ApiClient } from '../../services/network/ApiClient';
import { LinkCount, MentionedUser, Poll, PollOption, Post } from '../../models/Post';
import { SmartAvatar } from './SmartAvatar';
import { ExpandedMenuOptions, SelectionMenu } from '@kit.ArkUI';

enum RichBlockType {
  Text = 0,
  Quote = 1,
  Code = 2,
  Image = 3,
  List = 4,
  Onebox = 5,
  Heading = 6,
  Details = 7,
  ImageGrid = 8,
  Spoiler = 9,
  Table = 10,
  Poll = 11,
  Math = 12,
  Iframe = 13,
  LazyVideo = 14,
  ChatTranscript = 15,
  Divider = 16
}

class RichTableCell {
  html: string = '';
  header: boolean = false;

  constructor() {
  }
}

class RichTableRow {
  cells: RichTableCell[] = [];

  constructor() {
  }
}

class ChatTranscriptReaction {
  emojiUrl: string = '';
  count: number = 1;

  constructor() {
  }
}

class ChatTranscriptInfo {
  username: string = '';
  datetime: string = '';
  channelName: string = '';
  isChained: boolean = false;
  avatarUrl: string = '';
  messagesHtml: string = '';
  threadTitle: string = '';
  reactions: ChatTranscriptReaction[] = [];

  constructor() {
  }
}

class AsideQuoteInfo {
  username: string = '引用';
  avatarUrl: string = '';
  titleHtml: string = '';
  contentHtml: string = '';

  constructor() {
  }
}

class RichBlock {
  key: string = '';
  order: number = 0;
  type: RichBlockType = RichBlockType.Text;
  html: string = '';
  text: string = '';
  imageUrl: string = '';
  imageIndex: number = -1;

  // Heading block
  headingLevel: number = 0;

  // Code block
  codeLanguage: string = '';

  // List block
  listOrdered: boolean = false;
  listItemsHtml: string[] = [];

  // Details block
  detailsSummary: string = '';
  detailsContentHtml: string = '';
  detailsOpen: boolean = false;

  // Image grid block (Discourse d-image-grid)
  gridColumns: number = 2;
  gridImageIndices: number[] = [];

  // Spoiler block
  spoilerHtml: string = '';

  // Table block
  tableRows: RichTableRow[] = [];

  // Poll block
  pollName: string = '';
  pollTitle: string = '';

  // Math block
  mathLatex: string = '';

  // Iframe block
  iframeSrc: string = '';
  iframeWidth: number = 0;
  iframeHeight: number = 0;
  iframeTitle: string = '';
  iframeAllow: string = '';
  iframeClasses: string = '';
  iframeAllowFullscreen: boolean = false;

  // Lazy video block
  lazyVideoProvider: string = '';
  lazyVideoId: string = '';
  lazyVideoTitle: string = '';
  lazyVideoThumbnailUrl: string = '';
  lazyVideoStartTime: string = '';
  lazyVideoUrl: string = '';

  // Chat transcript block
  chatTranscriptHtml: string = '';

  // Structured quote metadata
  quoteUsername: string = '';
  quoteAvatarUrl: string = '';
  quoteTitleHtml: string = '';
  quoteContentHtml: string = '';

  // Onebox (link preview) block
  oneboxUrl: string = '';
  oneboxTitle: string = '';
  oneboxDescription: string = '';
  oneboxSource: string = '';
  oneboxIconUrl: string = '';
  oneboxThumbnailUrl: string = '';

  constructor() {
  }
}

class RichSpanToken {
  key: string = '';
  text: string = '';
  type: RichSpanTokenType = RichSpanTokenType.Text;
  emojiUrl: string = '';
  metaId: string = '';
  rawEmoji: string = '';
  extraHtml: string = '';
  bold: boolean = false;
  italic: boolean = false;
  underline: boolean = false;
  strike: boolean = false;
  code: boolean = false;
  sup: boolean = false;
  sub: boolean = false;
  href: string | null = null;

  constructor() {
  }
}

enum RichSpanTokenType {
  Text = 0,
  Emoji = 1,
  Mention = 2,
  FootnoteRef = 3,
  InlineSpoiler = 4,
  InlineMath = 5,
  ClickCount = 6
}

class RichParseResult {
  blocks: RichBlock[] = [];
  imageUrls: string[] = [];
  // 与 imageUrls 同索引：用于预览/保存/分享的原图（original）
  imagePreviewUrls: string[] = [];
  // 与 imageUrls 同索引：图片原始宽高（来自 <img width/height> 或 style），用于自适应展示高度
  imageWidths: number[] = [];
  imageHeights: number[] = [];
  footnotes: Map<string, string> = new Map();

  constructor() {
  }
}

class ImageDisplaySize {
  width: number = 0;
  height: number = 0;

  constructor() {
  }
}

function decodeHtmlEntities(text: string): string {
  let result: string = text;
  result = result.replace(/&nbsp;/g, ' ');
  result = result.replace(/&lt;/g, '<');
  result = result.replace(/&gt;/g, '>');
  result = result.replace(/&amp;/g, '&');
  result = result.replace(/&quot;/g, '"');
  result = result.replace(/&#39;/g, '\'');

  result = result.replace(/&#x([0-9a-fA-F]+);/g, (m: string, hex: string): string => {
    const code: number = parseInt(hex, 16);
    if (isNaN(code)) return m;
    try {
      return String.fromCodePoint(code);
    } catch (_) {
      return m;
    }
  });

  result = result.replace(/&#([0-9]+);/g, (m: string, dec: string): string => {
    const code: number = parseInt(dec, 10);
    if (isNaN(code)) return m;
    try {
      return String.fromCodePoint(code);
    } catch (_) {
      return m;
    }
  });

  return result;
}

function stripHtmlKeepLines(html: string): string {
  if (html.length === 0) return '';
  let result: string = html;
  result = result.replace(/<br\s*\/?>/g, '\n');
  result = result.replace(/<\/p>/g, '\n');
  result = result.replace(/<[^>]*>/g, '');
  result = decodeHtmlEntities(result);
  result = result.replace(/\n{3,}/g, '\n\n');
  return result.trim();
}

function normalizeMultilineText(text: string): string {
  const raw: string = text !== undefined && text !== null ? text : '';
  if (raw.length === 0) return '';
  const lines: string[] = raw.replace(/\r/g, '').split('\n');
  const out: string[] = [];
  let prevBlank: boolean = true;
  for (let i = 0; i < lines.length; i++) {
    const compact: string = lines[i].replace(/[ \t\u00A0]+/g, ' ').trim();
    if (compact.length === 0) {
      if (!prevBlank && out.length > 0) {
        out.push('');
      }
      prevBlank = true;
      continue;
    }
    out.push(compact);
    prevBlank = false;
  }
  while (out.length > 0 && out[out.length - 1].length === 0) {
    out.pop();
  }
  return out.join('\n').trim();
}

function extractAttr(tag: string, attr: string): string {
  const re1: RegExp = new RegExp(`${attr}\\s*=\\s*\"([^\"]*)\"`, 'i');
  const m1: RegExpMatchArray | null = tag.match(re1);
  if (m1 !== null && m1.length > 1) {
    return m1[1];
  }
  const re2: RegExp = new RegExp(`${attr}\\s*=\\s*'([^']*)'`, 'i');
  const m2: RegExpMatchArray | null = tag.match(re2);
  if (m2 !== null && m2.length > 1) {
    return m2[1];
  }
  return '';
}

function isEmojiImg(tag: string): boolean {
  const cls: string = extractAttr(tag, 'class').toLowerCase();
  if (cls.indexOf('emoji') >= 0) return true;
  return false;
}

function parseNumericLike(raw: string): number | null {
  const s: string = raw !== undefined && raw !== null ? raw.trim() : '';
  if (s.length === 0) return null;
  const n: number = parseFloat(s);
  if (isNaN(n)) return null;
  return n;
}

function parseStylePx(tag: string, key: string): number | null {
  const style: string = extractAttr(tag, 'style');
  if (style.trim().length === 0) return null;
  const re: RegExp = new RegExp(`${key}\\s*:\\s*([0-9.]+)\\s*px`, 'i');
  const m: RegExpMatchArray | null = style.match(re);
  if (m !== null && m.length > 1) {
    return parseNumericLike(m[1]);
  }
  return null;
}

function isSmallInlineImg(tag: string): boolean {
  const wRaw: string = extractAttr(tag, 'width');
  const hRaw: string = extractAttr(tag, 'height');
  const w: number | null = parseNumericLike(wRaw);
  const h: number | null = parseNumericLike(hRaw);
  if (w !== null && w > 0 && w <= 32) return true;
  if (h !== null && h > 0 && h <= 32) return true;

  const w2: number | null = parseStylePx(tag, 'width');
  const h2: number | null = parseStylePx(tag, 'height');
  if (w2 !== null && w2 > 0 && w2 <= 32) return true;
  if (h2 !== null && h2 > 0 && h2 <= 32) return true;
  return false;
}

function extractImgSrc(tag: string): string {
  const dataSrc: string = extractAttr(tag, 'data-src');
  if (dataSrc.trim().length > 0) return dataSrc;
  return extractAttr(tag, 'src');
}

function isImageAttachmentTailText(raw: string): boolean {
  const text: string = stripHtmlKeepLines(raw);
  const s: string = text !== undefined && text !== null ? text.trim() : '';
  if (s.length === 0) return false;

  // 常见附件尾巴：image1221x239 11.7KB / image1221×239 11.7 KB
  const compact: string = s.replace(/\s+/g, ' ').trim();
  const reLegacy: RegExp = /^image\s*\d+[x×]\d+\s*\d+(?:\.\d+)?\s*(?:kb|mb|gb|b)$/i;
  if (reLegacy.test(compact)) return true;

  // Discourse 上传元信息常见格式：文件名 + 尺寸 + 大小
  // 例：20260316_191106_3671506×1582 291 KB
  if (compact.length > 120) return false;
  const hasDim: boolean = /\b\d+\s*[x×]\s*\d+\b/i.test(compact);
  const hasSize: boolean = /\b\d+(?:\.\d+)?\s*(?:kb|mb|gb|b)\b/i.test(compact);
  if (!hasDim || !hasSize) return false;

  // 去掉“尺寸/大小/分隔符”后只剩文件名（或为空）时认为是附件尾巴
  const rest: string = compact
    .replace(/\b\d+\s*[x×]\s*\d+\b/i, '')
    .replace(/\b\d+(?:\.\d+)?\s*(?:kb|mb|gb|b)\b/i, '')
    .replace(/[\s·•\-–—()\\[\\]:]+/g, '')
    .trim();
  return rest.length === 0 || rest.length <= 80;
}

function stripHtmlCompact(html: string): string {
  const s: string = stripHtmlKeepLines(html);
  return s.replace(/\s+/g, ' ').trim();
}

function extractUrlHost(url: string): string {
  const raw: string = url !== undefined && url !== null ? url.toString().trim() : '';
  if (raw.length === 0) return '';
  let start: number = 0;
  const schemeIdx: number = raw.indexOf('://');
  if (schemeIdx >= 0) {
    start = schemeIdx + 3;
  }
  let end: number = raw.indexOf('/', start);
  if (end < 0) end = raw.length;
  let host: string = raw.substring(start, end);
  if (host.startsWith('www.')) host = host.substring(4);
  return host;
}

function findMatchingCloseTag(lowerHtml: string, startIndex: number, tagName: string): number {
  const openPat: string = `<${tagName}`;
  const closePat: string = `</${tagName}>`;
  let idx: number = startIndex;
  let depth: number = 0;

  while (idx < lowerHtml.length) {
    const nextOpen: number = lowerHtml.indexOf(openPat, idx);
    const nextClose: number = lowerHtml.indexOf(closePat, idx);
    if (nextClose < 0) return -1;

    if (nextOpen >= 0 && nextOpen < nextClose) {
      depth = depth + 1;
      idx = nextOpen + openPat.length;
      continue;
    }

    depth = depth - 1;
    if (depth === 0) {
      return nextClose;
    }
    idx = nextClose + closePat.length;
  }

  return -1;
}

function escapeRegExp(raw: string): string {
  const s: string = raw !== undefined && raw !== null ? raw.toString() : '';
  return s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

function escapeHtml(raw: string): string {
  const s: string = raw !== undefined && raw !== null ? raw.toString() : '';
  if (s.length === 0) return '';
  return s
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/\"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

function formatLinkClickCount(count: number): string {
  const safeCount: number = Number.isFinite(count) ? Math.max(0, Math.round(count)) : 0;
  if (safeCount >= 1000) {
    return `${(safeCount / 1000).toFixed(1)}k`;
  }
  return `${safeCount}`;
}

function injectLinkClickCounts(html: string, linkCounts: LinkCount[] | null): string {
  const raw: string = html !== undefined && html !== null ? html : '';
  if (raw.length === 0 || linkCounts === null || linkCounts.length === 0) {
    return raw;
  }

  let out: string = raw;
  for (let i = 0; i < linkCounts.length; i++) {
    const linkCount: LinkCount = linkCounts[i];
    const clicks: number = linkCount.clicks !== undefined && linkCount.clicks !== null ? Math.round(linkCount.clicks) : 0;
    const url: string = linkCount.url !== undefined && linkCount.url !== null ? linkCount.url.trim() : '';
    if (clicks <= 0 || url.length === 0) continue;

    const escapedUrl: string = escapeRegExp(url);
    const pattern: RegExp = new RegExp(
      `(<a(?![^>]*data-clicks)[^>]*href\\s*=\\s*(?:\"[^\"]*${escapedUrl}[^\"]*\"|'[^']*${escapedUrl}[^']*')[^>]*>)([\\s\\S]*?)(</a>)(?!\\s*<span[^>]*class\\s*=\\s*(?:\"[^\"]*click-count[^\"]*\"|'[^']*click-count[^']*'))`,
      'ig'
    );
    const formattedCount: string = formatLinkClickCount(clicks);
    out = out.replace(pattern, (_: string, openTag: string, content: string, closeTag: string): string => {
      const newOpenTag: string = openTag.replace(/^<a/i, `<a data-clicks="${formattedCount}"`);
      return `${newOpenTag}${content}${closeTag} <span class="click-count">\u2009${formattedCount}\u2009</span>`;
    });
  }
  return out;
}

function removeAvatarImgs(html: string): string {
  const raw: string = html !== undefined && html !== null ? html : '';
  if (raw.length === 0) return '';
  // 只移除 avatar img，避免 quote title 中头像被当成正文图片块渲染
  return raw
    .replace(/<img[^>]*class\s*=\s*\"[^\"]*avatar[^\"]*\"[^>]*>/gi, '')
    .replace(/<img[^>]*class\s*=\s*'[^']*avatar[^']*'[^>]*>/gi, '');
}

function extractFirstElementInnerHtmlByClass(rawHtml: string, classSubstrRaw: string): string {
  const html: string = rawHtml !== undefined && rawHtml !== null ? rawHtml : '';
  const classSubstr: string = classSubstrRaw !== undefined && classSubstrRaw !== null ? classSubstrRaw.toString().trim() : '';
  if (html.length === 0 || classSubstr.length === 0) return '';

  const pat: string = escapeRegExp(classSubstr);
  const re: RegExp = new RegExp(`<([a-z0-9]+)([^>]*\\sclass\\s*=\\s*[\"'][^\"']*${pat}[^\"']*[\"'][^>]*)>`, 'i');
  const m: RegExpExecArray | null = re.exec(html);
  if (m === null || m.length < 2 || m.index === undefined || m.index === null) return '';

  const tagName: string = m[1].toLowerCase();
  const openStart: number = m.index as number;
  const openEnd: number = openStart + m[0].length - 1; // '>' 在末尾
  if (openEnd < openStart || openEnd >= html.length) return '';

  const lower: string = html.toLowerCase();
  const closeStart: number = findMatchingCloseTag(lower, openStart, tagName);
  if (closeStart < 0 || closeStart <= openEnd) return '';
  return html.substring(openEnd + 1, closeStart);
}

function extractFirstDivInnerHtmlByClass(rawHtml: string, classSubstrRaw: string): string {
  const html: string = rawHtml !== undefined && rawHtml !== null ? rawHtml : '';
  const classSubstr: string = classSubstrRaw !== undefined && classSubstrRaw !== null ? classSubstrRaw.toString().trim().toLowerCase() : '';
  if (html.length === 0 || classSubstr.length === 0) return '';
  const lower: string = html.toLowerCase();
  let idx: number = 0;
  while (idx < html.length) {
    const divStart: number = lower.indexOf('<div', idx);
    if (divStart < 0) break;
    const openEnd: number = html.indexOf('>', divStart);
    if (openEnd < 0) break;
    const openTag: string = html.substring(divStart, openEnd + 1);
    const cls: string = extractAttr(openTag, 'class').toLowerCase();
    if (cls.indexOf(classSubstr) >= 0) {
      const closeStart: number = findMatchingCloseTag(lower, divStart, 'div');
      if (closeStart > openEnd) {
        return html.substring(openEnd + 1, closeStart);
      }
    }
    idx = openEnd + 1;
  }
  return '';
}

function extractLastAnchorOuterHtml(rawHtml: string): string {
  const html: string = rawHtml !== undefined && rawHtml !== null ? rawHtml : '';
  if (html.length === 0) return '';
  const lower: string = html.toLowerCase();
  let idx: number = 0;
  let last: number = -1;
  while (idx < html.length) {
    const aStart: number = lower.indexOf('<a', idx);
    if (aStart < 0) break;
    last = aStart;
    idx = aStart + 2;
  }
  if (last < 0) return '';
  const openEnd: number = html.indexOf('>', last);
  if (openEnd < 0) return '';
  const closeStart: number = findMatchingCloseTag(lower, last, 'a');
  if (closeStart > openEnd) {
    return html.substring(last, closeStart + '</a>'.length);
  }
  // 兜底：只返回开标签
  return html.substring(last, openEnd + 1);
}

function extractAsideQuoteContentHtml(rawInnerHtml: string): string {
  const inner: string = rawInnerHtml !== undefined && rawInnerHtml !== null ? rawInnerHtml : '';
  if (inner.length === 0) return '';
  const lower: string = inner.toLowerCase();
  const bqStart: number = lower.indexOf('<blockquote');
  if (bqStart < 0) return '';
  const openEnd: number = inner.indexOf('>', bqStart);
  if (openEnd < 0) return '';
  const closeStart: number = findMatchingCloseTag(lower, bqStart, 'blockquote');
  if (closeStart < 0 || closeStart <= openEnd) return '';
  return inner.substring(openEnd + 1, closeStart);
}

function extractAsideQuoteInfo(openTag: string, innerHtml: string): AsideQuoteInfo {
  const info: AsideQuoteInfo = new AsideQuoteInfo();
  const usernameRaw: string = extractAttr(openTag, 'data-username');
  info.username = usernameRaw.trim().length > 0 ? usernameRaw.trim() : '引用';
  info.avatarUrl = UrlUtils.resolveUrl(extractFirstImgSrcByClass(innerHtml, 'avatar'));

  let titleHtml: string = extractFirstElementInnerHtmlByClass(innerHtml, 'quote-title__text-content').trim();
  if (titleHtml.length === 0) {
    const titleDivInner: string = extractFirstDivInnerHtmlByClass(innerHtml, 'title');
    const lastAnchor: string = extractLastAnchorOuterHtml(titleDivInner);
    titleHtml = lastAnchor.trim();
  }

  info.titleHtml = removeAvatarImgs(titleHtml).trim();
  info.contentHtml = extractAsideQuoteContentHtml(innerHtml).trim();
  return info;
}

function buildAsideQuoteHtml(openTag: string, innerHtml: string): string {
  const info: AsideQuoteInfo = extractAsideQuoteInfo(openTag, innerHtml);
  const safeUser: string = escapeHtml(info.username);
  const header: string = `<p><strong>${safeUser}:</strong>${info.titleHtml.length > 0 ? ` ${info.titleHtml}` : ''}</p>`;
  if (info.contentHtml.length > 0) {
    return `${header}${info.contentHtml}`;
  }
  // 兜底：没有 blockquote 时直接用 innerHtml（但尽量避免把 avatar 当正文图片）
  const cleaned: string = removeAvatarImgs(innerHtml);
  return `${header}${cleaned}`;
}

function normalizeListItemHtml(innerHtml: string): string {
  let s: string = innerHtml !== undefined && innerHtml !== null ? innerHtml.toString().trim() : '';

  // 去掉整段包裹的 <p>...</p>（避免 li 内嵌 p 导致额外空行）
  while (true) {
    const lower: string = s.toLowerCase().trim();
    if (!lower.startsWith('<p') || !lower.endsWith('</p>')) {
      break;
    }
    const startEnd: number = lower.indexOf('>');
    const endStart: number = lower.lastIndexOf('</p>');
    if (startEnd < 0 || endStart <= startEnd) {
      break;
    }
    s = s.substring(startEnd + 1, endStart).trim();
  }

  return s;
}

function extractTopLevelListItems(listInnerHtml: string): string[] {
  const raw: string = listInnerHtml !== undefined && listInnerHtml !== null ? listInnerHtml : '';
  const lower: string = raw.toLowerCase();
  const out: string[] = [];
  let idx: number = 0;

  while (idx < raw.length) {
    const liStart: number = lower.indexOf('<li', idx);
    if (liStart < 0) break;
    const liTagEnd: number = raw.indexOf('>', liStart);
    if (liTagEnd < 0) break;

    let cursor: number = liTagEnd + 1;
    let depth: number = 1;
    while (cursor < raw.length) {
      const nextOpen: number = lower.indexOf('<li', cursor);
      const nextClose: number = lower.indexOf('</li>', cursor);
      if (nextClose < 0) {
        depth = 0;
        break;
      }
      if (nextOpen >= 0 && nextOpen < nextClose) {
        depth = depth + 1;
        cursor = nextOpen + 3;
        continue;
      }
      depth = depth - 1;
      if (depth === 0) {
        const itemHtml: string = raw.substring(liTagEnd + 1, nextClose);
        out.push(normalizeListItemHtml(itemHtml));
        idx = nextClose + '</li>'.length;
        break;
      }
      cursor = nextClose + '</li>'.length;
    }

    if (depth !== 0) {
      break;
    }
  }

  return out;
}

function extractFirstHref(html: string): string {
  const raw: string = html !== undefined && html !== null ? html : '';
  const m1: RegExpMatchArray | null = raw.match(/<a[^>]*href\s*=\s*\"([^\"]+)\"/i);
  if (m1 !== null && m1.length > 1) return m1[1];
  const m2: RegExpMatchArray | null = raw.match(/<a[^>]*href\s*=\s*'([^']+)'/i);
  if (m2 !== null && m2.length > 1) return m2[1];
  return '';
}

function extractFirstImgSrcByClass(html: string, className: string): string {
  const raw: string = html !== undefined && html !== null ? html : '';
  const re1: RegExp = new RegExp(`<img[^>]*class\\s*=\\s*\"[^\"]*${className}[^\"]*\"[^>]*>`, 'i');
  const m1: RegExpMatchArray | null = raw.match(re1);
  if (m1 !== null && m1.length > 0) return extractImgSrc(m1[0]);
  const re2: RegExp = new RegExp(`<img[^>]*class\\s*=\\s*'[^']*${className}[^']*'[^>]*>`, 'i');
  const m2: RegExpMatchArray | null = raw.match(re2);
  if (m2 !== null && m2.length > 0) return extractImgSrc(m2[0]);
  return '';
}

function extractCodeLanguageFromPreInnerHtml(innerHtml: string): string {
  const raw: string = innerHtml !== undefined && innerHtml !== null ? innerHtml : '';
  if (raw.length === 0) return '';
  // 常见：<code class="lang-css"> / <code class="language-css">
  let m: RegExpMatchArray | null = raw.match(/<code[^>]*class\s*=\s*\"[^\"]*(?:lang|language)-([a-z0-9_+.-]+)[^\"]*\"[^>]*>/i);
  if (m !== null && m.length > 1) return m[1];
  m = raw.match(/<code[^>]*class\s*=\s*'[^']*(?:lang|language)-([a-z0-9_+.-]+)[^']*'[^>]*>/i);
  if (m !== null && m.length > 1) return m[1];

  // 兜底：data-lang / data-language
  m = raw.match(/<code[^>]*data-(?:lang|language)\s*=\s*\"([a-z0-9_+.-]+)\"/i);
  if (m !== null && m.length > 1) return m[1];
  m = raw.match(/<code[^>]*data-(?:lang|language)\s*=\s*'([a-z0-9_+.-]+)'/i);
  if (m !== null && m.length > 1) return m[1];
  return '';
}

function extractNonEmojiImageSrcsFromHtml(innerHtml: string): string[] {
  const raw: string = innerHtml !== undefined && innerHtml !== null ? innerHtml : '';
  const lower: string = raw.toLowerCase();
  const out: string[] = [];
  let idx: number = 0;
  while (idx < raw.length) {
    const pos: number = lower.indexOf('<img', idx);
    if (pos < 0) break;
    const end: number = raw.indexOf('>', pos);
    if (end < 0) break;
    const tag: string = raw.substring(pos, end + 1);
    const cls: string = extractAttr(tag, 'class').toLowerCase();
    if (
      !isEmojiImg(tag)
      && !isSmallInlineImg(tag)
      && cls.indexOf('avatar') < 0
      && cls.indexOf('thumbnail') < 0
      && cls.indexOf('ytp-thumbnail-image') < 0
    ) {
      const src: string = extractImgSrc(tag);
      if (src.trim().length > 0) {
        out.push(src);
      }
    }
    idx = end + 1;
  }
  return out;
}

function getOriginalUrlFromOptimizedUrl(url: string): string {
  const raw: string = url !== undefined && url !== null ? url.toString().trim() : '';
  if (raw.length === 0) return '';
  if (raw.indexOf('/original/') >= 0) return raw;
  if (raw.indexOf('/optimized/') < 0) return raw;

  let out: string = raw.replace('/optimized/', '/original/');

  // 去掉 optimized 的尺寸后缀：..._2_690x409.jpg -> ....jpg
  let path: string = out;
  let query: string = '';
  const qIdx: number = out.indexOf('?');
  if (qIdx >= 0) {
    path = out.substring(0, qIdx);
    query = out.substring(qIdx);
  }

  path = path.replace(/_[0-9]+_[0-9]+x[0-9]+(?=\.[a-z0-9]+$)/i, '');
  path = path.replace(/_[0-9]+x[0-9]+(?=\.[a-z0-9]+$)/i, '');
  out = `${path}${query}`;
  return out;
}

class ImageDims {
  w: number = 0;
  h: number = 0;

  constructor() {
  }
}

function guessImageDimsFromUrl(url: string): ImageDims {
  const out: ImageDims = new ImageDims();
  const raw: string = url !== undefined && url !== null ? url.toString() : '';
  const s: string = raw.trim();
  if (s.length === 0) return out;

  // 常见：...1506×1582... / ...1506x1582... / ..._690x409.jpg
  const re: RegExp = /(\d{2,5})\s*[x×]\s*(\d{2,5})/ig;
  let m: RegExpExecArray | null = null;
  let lastW: number = 0;
  let lastH: number = 0;
  while (true) {
    m = re.exec(s);
    if (m === null) break;
    const w: number = parseInt(m[1], 10);
    const h: number = parseInt(m[2], 10);
    if (!isNaN(w) && !isNaN(h) && w > 0 && h > 0) {
      lastW = w;
      lastH = h;
    }
  }
  out.w = lastW;
  out.h = lastH;
  return out;
}

function extractImgDimension(tag: string, key: string): number {
  const raw: string = extractAttr(tag, key);
  const n: number | null = parseNumericLike(raw);
  if (n !== null && n > 0) return n;
  const n2: number | null = parseStylePx(tag, key);
  if (n2 !== null && n2 > 0) return n2;
  return 0;
}

class LightboxImageInfo {
  thumbSrc: string = '';
  originalHref: string = '';
  width: number = 0;
  height: number = 0;

  constructor() {
  }
}

function extractLightboxImageInfos(innerHtml: string): LightboxImageInfo[] {
  const raw: string = innerHtml !== undefined && innerHtml !== null ? innerHtml : '';
  const lower: string = raw.toLowerCase();
  const out: LightboxImageInfo[] = [];
  let idx: number = 0;

  while (idx < raw.length) {
    const aStart: number = lower.indexOf('<a', idx);
    if (aStart < 0) break;
    const aTagEnd: number = raw.indexOf('>', aStart);
    if (aTagEnd < 0) break;

    const openTag: string = raw.substring(aStart, aTagEnd + 1);
    const cls: string = extractAttr(openTag, 'class').toLowerCase();
    if (cls.indexOf('lightbox') < 0) {
      idx = aTagEnd + 1;
      continue;
    }

    const href: string = normalizeHref(extractAttr(openTag, 'href'));
    if (href.length === 0) {
      idx = aTagEnd + 1;
      continue;
    }

    const aClose: number = lower.indexOf('</a>', aTagEnd + 1);
    if (aClose < 0) {
      idx = aTagEnd + 1;
      continue;
    }

    const inner: string = raw.substring(aTagEnd + 1, aClose);
    const innerLower: string = inner.toLowerCase();
    const imgStart: number = innerLower.indexOf('<img');

    let thumbSrc: string = '';
    let w: number = 0;
    let h: number = 0;
    if (imgStart >= 0) {
      const imgEnd: number = inner.indexOf('>', imgStart);
      if (imgEnd >= 0) {
        const imgTag: string = inner.substring(imgStart, imgEnd + 1);
        thumbSrc = extractImgSrc(imgTag);
        w = extractImgDimension(imgTag, 'width');
        h = extractImgDimension(imgTag, 'height');
      }
    }

    const info: LightboxImageInfo = new LightboxImageInfo();
    info.thumbSrc = thumbSrc;
    info.originalHref = href;
    info.width = w;
    info.height = h;
    out.push(info);

    idx = aClose + '</a>'.length;
  }

  return out;
}

class OneboxInfo {
  url: string = '';
  title: string = '';
  description: string = '';
  source: string = '';
  iconUrl: string = '';
  thumbnailUrl: string = '';

  constructor() {
  }
}

function extractOneboxInfo(openTag: string, innerHtml: string): OneboxInfo {
  const info: OneboxInfo = new OneboxInfo();
  const open: string = openTag !== undefined && openTag !== null ? openTag : '';
  const inner: string = innerHtml !== undefined && innerHtml !== null ? innerHtml : '';

  let urlRaw: string = extractAttr(open, 'data-onebox-src');
  if (urlRaw.trim().length === 0) {
    urlRaw = extractAttr(open, 'data-onebox-url');
  }
  if (urlRaw.trim().length === 0) {
    urlRaw = extractFirstHref(inner);
  }
  info.url = normalizeHref(urlRaw);

  // 标题：优先 h4/h3 内的 a
  let titleHtml: string = '';
  const h4: RegExpMatchArray | null = inner.match(/<h4[^>]*>([\s\S]*?)<\/h4>/i);
  if (h4 !== null && h4.length > 1) {
    titleHtml = h4[1];
  } else {
    const h3: RegExpMatchArray | null = inner.match(/<h3[^>]*>([\s\S]*?)<\/h3>/i);
    if (h3 !== null && h3.length > 1) {
      titleHtml = h3[1];
    }
  }

  if (titleHtml.trim().length > 0) {
    const a1: RegExpMatchArray | null = titleHtml.match(/<a[^>]*href\s*=\s*\"([^\"]+)\"[^>]*>([\s\S]*?)<\/a>/i);
    if (a1 !== null && a1.length > 2) {
      if (info.url.length === 0) {
        info.url = normalizeHref(a1[1]);
      }
      info.title = stripHtmlCompact(a1[2]);
    } else {
      const a2: RegExpMatchArray | null = titleHtml.match(/<a[^>]*href\s*=\s*'([^']+)'[^>]*>([\s\S]*?)<\/a>/i);
      if (a2 !== null && a2.length > 2) {
        if (info.url.length === 0) {
          info.url = normalizeHref(a2[1]);
        }
        info.title = stripHtmlCompact(a2[2]);
      } else {
        info.title = stripHtmlCompact(titleHtml);
      }
    }
  }

  // 描述：第一个 p
  const p1: RegExpMatchArray | null = inner.match(/<p[^>]*>([\s\S]*?)<\/p>/i);
  if (p1 !== null && p1.length > 1) {
    info.description = stripHtmlCompact(p1[1]);
  }

  // 来源：.source a
  const s1: RegExpMatchArray | null = inner.match(/class\s*=\s*\"[^\"]*source[^\"]*\"[\s\S]*?<a[^>]*>([\s\S]*?)<\/a>/i);
  if (s1 !== null && s1.length > 1) {
    info.source = stripHtmlCompact(s1[1]);
  } else {
    const s2: RegExpMatchArray | null = inner.match(/class\s*=\s*'[^']*source[^']*'[\s\S]*?<a[^>]*>([\s\S]*?)<\/a>/i);
    if (s2 !== null && s2.length > 1) {
      info.source = stripHtmlCompact(s2[1]);
    }
  }

  // 图标与缩略图
  const iconRaw: string = extractFirstImgSrcByClass(inner, 'site-icon');
  if (iconRaw.trim().length > 0) {
    info.iconUrl = UrlUtils.resolveUrl(iconRaw);
  }
  const thumbRaw: string = extractFirstImgSrcByClass(inner, 'thumbnail');
  if (thumbRaw.trim().length > 0) {
    info.thumbnailUrl = UrlUtils.resolveUrl(thumbRaw);
  }

  if (info.source.length === 0 && info.url.length > 0) {
    info.source = extractUrlHost(info.url);
  }

  return info;
}

function containsCssClass(tag: string, className: string): boolean {
  const cls: string = extractAttr(tag, 'class').toLowerCase();
  return cls.indexOf(className.toLowerCase()) >= 0;
}

function extractPollTitle(openTag: string, innerHtml: string): string {
  const attrQuestion: string = stripHtmlCompact(extractAttr(openTag, 'data-poll-question'));
  if (attrQuestion.length > 0) return attrQuestion;
  const attrTitle: string = stripHtmlCompact(extractAttr(openTag, 'data-poll-title'));
  if (attrTitle.length > 0) return attrTitle;

  const titleMatch: RegExpMatchArray | null = innerHtml.match(/<div[^>]*class\s*=\s*["'][^"']*poll-title[^"']*["'][^>]*>([\s\S]*?)<\/div>/i);
  if (titleMatch !== null && titleMatch.length > 1) {
    const title: string = stripHtmlCompact(titleMatch[1]);
    if (title.length > 0) return title;
  }

  const questionMatch: RegExpMatchArray | null = innerHtml.match(/<div[^>]*class\s*=\s*["'][^"']*poll-question[^"']*["'][^>]*>([\s\S]*?)<\/div>/i);
  if (questionMatch !== null && questionMatch.length > 1) {
    const title: string = stripHtmlCompact(questionMatch[1]);
    if (title.length > 0) return title;
  }

  return '';
}

class FootnoteExtractionResult {
  html: string = '';
  footnotes: Map<string, string> = new Map();

  constructor() {
  }
}

function removeFootnoteBackrefs(html: string): string {
  const raw: string = html !== undefined && html !== null ? html : '';
  return raw
    .replace(/<a[^>]*class\s*=\s*"[^"]*footnote-backref[^"]*"[^>]*>[\s\S]*?<\/a>/gi, '')
    .replace(/<a[^>]*class\s*=\s*'[^']*footnote-backref[^']*'[^>]*>[\s\S]*?<\/a>/gi, '');
}

function collectFootnotesFromBlock(blockHtml: string, out: Map<string, string>): void {
  const raw: string = blockHtml !== undefined && blockHtml !== null ? blockHtml : '';
  const lower: string = raw.toLowerCase();
  let idx: number = 0;
  while (idx < raw.length) {
    const liStart: number = lower.indexOf('<li', idx);
    if (liStart < 0) break;
    const openEnd: number = raw.indexOf('>', liStart);
    if (openEnd < 0) break;
    const closeStart: number = findMatchingCloseTag(lower, liStart, 'li');
    if (closeStart <= openEnd) break;
    const openTag: string = raw.substring(liStart, openEnd + 1);
    const footnoteId: string = extractAttr(openTag, 'id').trim();
    const innerHtml: string = removeFootnoteBackrefs(raw.substring(openEnd + 1, closeStart)).trim();
    if (footnoteId.length > 0 && innerHtml.length > 0) {
      out.set(footnoteId, innerHtml);
    }
    idx = closeStart + '</li>'.length;
  }
}

function extractFootnotesFromHtml(html: string): FootnoteExtractionResult {
  const result: FootnoteExtractionResult = new FootnoteExtractionResult();
  let working: string = html !== undefined && html !== null ? html : '';

  while (true) {
    const lower: string = working.toLowerCase();
    let foundStart: number = -1;
    let foundTag: string = '';
    let foundClass: string = '';
    let search: number = 0;

    while (search < working.length) {
      const sectionStart: number = lower.indexOf('<section', search);
      const olStart: number = lower.indexOf('<ol', search);
      let nextStart: number = -1;
      let tagName: string = '';
      if (sectionStart >= 0 && (olStart < 0 || sectionStart < olStart)) {
        nextStart = sectionStart;
        tagName = 'section';
      } else if (olStart >= 0) {
        nextStart = olStart;
        tagName = 'ol';
      }
      if (nextStart < 0) break;

      const openEnd: number = working.indexOf('>', nextStart);
      if (openEnd < 0) break;
      const openTag: string = working.substring(nextStart, openEnd + 1);
      const className: string = extractAttr(openTag, 'class').toLowerCase();
      const matchFootnotes: boolean =
        (tagName === 'section' && className.indexOf('footnotes') >= 0) ||
        (tagName === 'ol' && className.indexOf('footnotes-list') >= 0);
      if (matchFootnotes) {
        foundStart = nextStart;
        foundTag = tagName;
        foundClass = className;
        break;
      }
      search = openEnd + 1;
    }

    if (foundStart < 0 || foundTag.length === 0 || foundClass.length === 0) break;

    const openEnd: number = working.indexOf('>', foundStart);
    if (openEnd < 0) break;
    const closeStart: number = findMatchingCloseTag(lower, foundStart, foundTag);
    if (closeStart <= openEnd) break;
    const blockHtml: string = working.substring(openEnd + 1, closeStart);
    collectFootnotesFromBlock(blockHtml, result.footnotes);
    working = `${working.substring(0, foundStart)}${working.substring(closeStart + `</${foundTag}>`.length)}`;
  }

  result.html = working;
  return result;
}

function extractTableRows(innerHtml: string): RichTableRow[] {
  const raw0: string = innerHtml !== undefined && innerHtml !== null ? innerHtml : '';
  const raw: string = raw0
    .replace(/<\/?(thead|tbody|tfoot)[^>]*>/gi, '')
    .trim();
  const lower: string = raw.toLowerCase();
  const rows: RichTableRow[] = [];
  let idx: number = 0;

  while (idx < raw.length) {
    const trStart: number = lower.indexOf('<tr', idx);
    if (trStart < 0) break;
    const trOpenEnd: number = raw.indexOf('>', trStart);
    if (trOpenEnd < 0) break;
    const trCloseStart: number = findMatchingCloseTag(lower, trStart, 'tr');
    if (trCloseStart <= trOpenEnd) break;
    const rowInner: string = raw.substring(trOpenEnd + 1, trCloseStart);
    const rowLower: string = rowInner.toLowerCase();
    const row: RichTableRow = new RichTableRow();
    let cellIdx: number = 0;
    while (cellIdx < rowInner.length) {
      const tdStart: number = rowLower.indexOf('<td', cellIdx);
      const thStart: number = rowLower.indexOf('<th', cellIdx);
      let start: number = -1;
      let header: boolean = false;
      if (tdStart >= 0 && (thStart < 0 || tdStart < thStart)) {
        start = tdStart;
      } else if (thStart >= 0) {
        start = thStart;
        header = true;
      }
      if (start < 0) break;

      const tagName: string = header ? 'th' : 'td';
      const openEnd: number = rowInner.indexOf('>', start);
      if (openEnd < 0) break;
      const closeStart: number = findMatchingCloseTag(rowLower, start, tagName);
      if (closeStart <= openEnd) break;
      const cell: RichTableCell = new RichTableCell();
      cell.header = header;
      cell.html = rowInner.substring(openEnd + 1, closeStart).trim();
      row.cells.push(cell);
      cellIdx = closeStart + `</${tagName}>`.length;
    }
    if (row.cells.length > 0) {
      rows.push(row);
    }
    idx = trCloseStart + '</tr>'.length;
  }

  return rows;
}

function extractFirstImgSrc(html: string): string {
  const raw: string = html !== undefined && html !== null ? html : '';
  const match: RegExpMatchArray | null = raw.match(/<img[^>]*src\s*=\s*["']([^"']+)["'][^>]*>/i);
  if (match !== null && match.length > 1) {
    return UrlUtils.resolveUrl(match[1]);
  }
  return '';
}

function extractFirstAnchorHref(html: string): string {
  const raw: string = html !== undefined && html !== null ? html : '';
  const match: RegExpMatchArray | null = raw.match(/<a[^>]*href\s*=\s*["']([^"']+)["'][^>]*>/i);
  if (match !== null && match.length > 1) {
    return normalizeHref(match[1]);
  }
  return '';
}

function extractFirstAnchorHrefByClass(html: string, className: string): string {
  const raw: string = html !== undefined && html !== null ? html : '';
  const re: RegExp = new RegExp(
    `<a[^>]*class\\s*=\\s*["'][^"']*${className}[^"']*["'][^>]*href\\s*=\\s*["']([^"']+)["'][^>]*>`,
    'i'
  );
  const match: RegExpMatchArray | null = raw.match(re);
  if (match !== null && match.length > 1) {
    return normalizeHref(match[1]);
  }
  return '';
}

function extractFirstTagInnerHtmlByClass(html: string, tagName: string, className: string): string {
  const raw: string = html !== undefined && html !== null ? html : '';
  const lower: string = raw.toLowerCase();
  const searchTag: string = tagName.toLowerCase();
  let idx: number = 0;
  while (idx < raw.length) {
    const start: number = lower.indexOf(`<${searchTag}`, idx);
    if (start < 0) break;
    const openEnd: number = raw.indexOf('>', start);
    if (openEnd < 0) break;
    const openTag: string = raw.substring(start, openEnd + 1);
    if (!containsCssClass(openTag, className)) {
      idx = openEnd + 1;
      continue;
    }
    const closeStart: number = findMatchingCloseTag(lower, start, searchTag);
    if (closeStart <= openEnd) break;
    return raw.substring(openEnd + 1, closeStart);
  }
  return '';
}

function extractChatTranscriptInfo(openTag: string, innerHtml: string): ChatTranscriptInfo {
  const info: ChatTranscriptInfo = new ChatTranscriptInfo();
  info.username = extractAttr(openTag, 'data-username').trim();
  info.datetime = extractAttr(openTag, 'data-datetime').trim();
  info.channelName = stripHtmlCompact(extractAttr(openTag, 'data-channel-name'));
  info.isChained = containsCssClass(openTag, 'chat-transcript-chained');
  info.avatarUrl = extractFirstImgSrcByClass(innerHtml, 'avatar');
  info.messagesHtml = extractFirstTagInnerHtmlByClass(innerHtml, 'div', 'chat-transcript-messages').trim();
  info.threadTitle = stripHtmlCompact(
    extractFirstTagInnerHtmlByClass(innerHtml, 'div', 'chat-transcript-thread-header__title')
  );

  const reactionsHtml: string = extractFirstTagInnerHtmlByClass(innerHtml, 'div', 'chat-transcript-reactions');
  if (reactionsHtml.length > 0) {
    const reactionsLower: string = reactionsHtml.toLowerCase();
    let idx: number = 0;
    while (idx < reactionsHtml.length) {
      const start: number = reactionsLower.indexOf('<div', idx);
      if (start < 0) break;
      const openEnd: number = reactionsHtml.indexOf('>', start);
      if (openEnd < 0) break;
      const reactionOpenTag: string = reactionsHtml.substring(start, openEnd + 1);
      if (!containsCssClass(reactionOpenTag, 'chat-transcript-reaction')) {
        idx = openEnd + 1;
        continue;
      }
      const closeStart: number = findMatchingCloseTag(reactionsLower, start, 'div');
      if (closeStart <= openEnd) break;
      const reactionInner: string = reactionsHtml.substring(openEnd + 1, closeStart);
      const reaction: ChatTranscriptReaction = new ChatTranscriptReaction();
      reaction.emojiUrl = extractFirstImgSrcByClass(reactionInner, 'emoji');
      const countMatch: RegExpMatchArray | null = stripHtmlCompact(reactionInner).match(/(\d+)$/);
      reaction.count = countMatch !== null && countMatch.length > 1 ? Number(countMatch[1]) : 1;
      if (reaction.emojiUrl.length > 0) {
        info.reactions.push(reaction);
      }
      idx = closeStart + '</div>'.length;
    }
  }

  return info;
}

function convertVideoStartTimeToSeconds(rawTime: string): number {
  const text: string = rawTime !== undefined && rawTime !== null ? rawTime.trim() : '';
  if (text.length === 0) return 0;
  const match: RegExpMatchArray | null = text.match(/(?:(\d+)h)?(?:(\d+)m)?(?:(\d+)s)?/i);
  if (match === null) {
    const parsed: number = Number(text);
    return isNaN(parsed) ? 0 : Math.max(0, Math.round(parsed));
  }
  const hours: number = match.length > 1 && match[1] !== undefined ? Number(match[1]) : 0;
  const minutes: number = match.length > 2 && match[2] !== undefined ? Number(match[2]) : 0;
  const seconds: number = match.length > 3 && match[3] !== undefined ? Number(match[3]) : 0;
  const total: number = hours * 3600 + minutes * 60 + seconds;
  if (total > 0) return total;
  const parsed: number = Number(text);
  return isNaN(parsed) ? 0 : Math.max(0, Math.round(parsed));
}

function buildLazyVideoEmbedUrl(provider: string, videoId: string, startTime: string): string {
  const p: string = provider !== undefined && provider !== null ? provider.trim().toLowerCase() : '';
  const id: string = videoId !== undefined && videoId !== null ? videoId.trim() : '';
  if (id.length === 0) return '';
  if (p === 'youtube') {
    let url: string = `https://www.youtube.com/embed/${id}?autoplay=1&rel=0`;
    const seconds: number = convertVideoStartTimeToSeconds(startTime);
    if (seconds > 0) {
      url = `${url}&start=${seconds}`;
    }
    return url;
  }
  if (p === 'vimeo') {
    const separator: string = id.indexOf('?') >= 0 ? '&' : '?';
    return `https://player.vimeo.com/video/${id}${separator}autoplay=1`;
  }
  if (p === 'tiktok') {
    return `https://www.tiktok.com/embed/v2/${id}`;
  }
  return '';
}

function estimateAspectRatio(width: number, height: number, classes: string): number {
  const cls: string = classes !== undefined && classes !== null ? classes.toLowerCase() : '';
  if (
    cls.indexOf('youtube-onebox') >= 0 ||
    cls.indexOf('lazyyt') >= 0 ||
    cls.indexOf('vimeo-onebox') >= 0 ||
    cls.indexOf('loom-onebox') >= 0
  ) {
    return 16 / 9;
  }
  if (width > 0 && height > 0) {
    return width / height;
  }
  return 16 / 9;
}

function escapeHtmlText(rawText: string): string {
  const text: string = rawText !== undefined && rawText !== null ? rawText : '';
  return text
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

function base64UrlEncode(text: string): string {
  const encoder: util.TextEncoder = new util.TextEncoder();
  const bytes: Uint8Array = encoder.encodeInto(text);
  const helper: util.Base64Helper = new util.Base64Helper();
  const base64: string = helper.encodeToStringSync(bytes);
  return base64
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=+$/g, '');
}

let richEmbedControllerSeed: number = 0;

function nextRichWebControllerId(prefix: string): string {
  richEmbedControllerSeed = richEmbedControllerSeed + 1;
  return `${prefix}_${richEmbedControllerSeed}`;
}

function parseBlocks(html: string): RichParseResult {
  const res: RichParseResult = new RichParseResult();
  const originalHtml: string = html !== undefined && html !== null ? html : '';
  if (originalHtml.trim().length === 0) {
    return res;
  }

  const footnoteExtraction: FootnoteExtractionResult = extractFootnotesFromHtml(originalHtml);
  res.footnotes = footnoteExtraction.footnotes;
  const raw: string = footnoteExtraction.html;
  if (raw.trim().length === 0) {
    return res;
  }

  const lower: string = raw.toLowerCase();
  let idx: number = 0;
  let order: number = 0;
  let textBuf: string = '';

  const flushTextBlock = (): void => {
    const s: string = textBuf !== undefined && textBuf !== null ? textBuf : '';
    if (s.trim().length === 0) {
      textBuf = '';
      return;
    }

    const compact: string = stripHtmlCompact(s);
    const hasEmoji: boolean =
      /<img[^>]*class\s*=\s*\"[^\"]*emoji[^\"]*\"/i.test(s)
      || /<img[^>]*class\s*=\s*'[^']*emoji[^']*'/i.test(s);
    // 只有标签、无可见文本且无 emoji 时不生成 Text block，避免制造大空白
    if (compact.length === 0 && !hasEmoji) {
      textBuf = '';
      return;
    }
    const b: RichBlock = new RichBlock();
    b.key = `b_${order}`;
    b.order = order;
    b.type = RichBlockType.Text;
    b.html = s;
    res.blocks.push(b);
    order = order + 1;
    textBuf = '';
  };

  const pushQuoteBlock = (innerHtml: string): void => {
    const html0: string = innerHtml !== undefined && innerHtml !== null ? innerHtml : '';
    const text: string = normalizeMultilineText(stripHtmlKeepLines(html0));
    if (text.length === 0) return;
    const b: RichBlock = new RichBlock();
    b.key = `b_${order}`;
    b.order = order;
    b.type = RichBlockType.Quote;
    b.html = html0;
    b.text = text;
    res.blocks.push(b);
    order = order + 1;
  };

  const pushAsideQuoteBlock = (openTag: string, innerHtml: string): void => {
    const info: AsideQuoteInfo = extractAsideQuoteInfo(openTag, innerHtml);
    const quoteHtml: string = buildAsideQuoteHtml(openTag, innerHtml);
    const text: string = normalizeMultilineText(stripHtmlKeepLines(quoteHtml));
    if (text.length === 0) return;
    const b: RichBlock = new RichBlock();
    b.key = `b_${order}`;
    b.order = order;
    b.type = RichBlockType.Quote;
    b.html = quoteHtml;
    b.text = text;
    b.quoteUsername = info.username;
    b.quoteAvatarUrl = info.avatarUrl;
    b.quoteTitleHtml = info.titleHtml;
    b.quoteContentHtml = info.contentHtml.length > 0 ? info.contentHtml : removeAvatarImgs(innerHtml).trim();
    res.blocks.push(b);
    order = order + 1;
  };

  const pushCodeBlock = (innerHtml: string): void => {
    const text: string = stripHtmlKeepLines(innerHtml);
    if (text.length === 0) return;
    const b: RichBlock = new RichBlock();
    b.key = `b_${order}`;
    b.order = order;
    b.type = RichBlockType.Code;
    b.text = text;
    b.codeLanguage = extractCodeLanguageFromPreInnerHtml(innerHtml);
    res.blocks.push(b);
    order = order + 1;
  };

  const pushImageMeta = (thumbSrc: string, originalHref: string, width: number, height: number): number => {
    const thumbUrl: string = UrlUtils.resolveUrl(thumbSrc);
    if (thumbUrl.length === 0) return -1;

    let previewUrl: string = normalizeHref(originalHref);
    if (previewUrl.indexOf('/optimized/') >= 0) {
      previewUrl = getOriginalUrlFromOptimizedUrl(previewUrl);
    }
    if (previewUrl.length === 0) {
      previewUrl = getOriginalUrlFromOptimizedUrl(thumbUrl);
    }
    if (previewUrl.length === 0) {
      previewUrl = thumbUrl;
    }

    let w: number = width > 0 ? width : 0;
    let h: number = height > 0 ? height : 0;
    if (w <= 0 || h <= 0) {
      const guess1 = guessImageDimsFromUrl(previewUrl);
      const guess2 = guessImageDimsFromUrl(thumbUrl);
      const gw: number = guess1.w > 0 ? guess1.w : guess2.w;
      const gh: number = guess1.h > 0 ? guess1.h : guess2.h;
      if (w <= 0 && gw > 0) w = gw;
      if (h <= 0 && gh > 0) h = gh;
    }

    const index: number = res.imageUrls.length;
    res.imageUrls.push(thumbUrl);
    res.imagePreviewUrls.push(previewUrl);
    res.imageWidths.push(w);
    res.imageHeights.push(h);
    return index;
  };

  const pushImageBlock = (thumbSrc: string, originalHref: string, width: number, height: number): void => {
    const index: number = pushImageMeta(thumbSrc, originalHref, width, height);
    if (index < 0) return;
    const b: RichBlock = new RichBlock();
    b.key = `b_${order}`;
    b.order = order;
    b.type = RichBlockType.Image;
    b.imageUrl = res.imageUrls[index];
    b.imageIndex = index;
    res.blocks.push(b);
    order = order + 1;
  };

  const pushHeadingBlock = (level: number, innerHtml: string): void => {
    const htmlText: string = innerHtml !== undefined && innerHtml !== null ? innerHtml : '';
    if (stripHtmlCompact(htmlText).length === 0) return;
    const b: RichBlock = new RichBlock();
    b.key = `b_${order}`;
    b.order = order;
    b.type = RichBlockType.Heading;
    b.headingLevel = level;
    b.html = htmlText;
    res.blocks.push(b);
    order = order + 1;
  };

  const pushListBlock = (ordered: boolean, itemsHtml: string[]): void => {
    if (itemsHtml.length === 0) return;
    const b: RichBlock = new RichBlock();
    b.key = `b_${order}`;
    b.order = order;
    b.type = RichBlockType.List;
    b.listOrdered = ordered;
    b.listItemsHtml = itemsHtml;
    res.blocks.push(b);
    order = order + 1;
  };

  const pushDetailsBlock = (openTag: string, innerHtml: string): void => {
    const inner: string = innerHtml !== undefined && innerHtml !== null ? innerHtml : '';
    let summary: string = '详情';
    const m: RegExpMatchArray | null = inner.match(/<summary[^>]*>([\s\S]*?)<\/summary>/i);
    if (m !== null && m.length > 1) {
      const v: string = stripHtmlCompact(m[1]);
      if (v.length > 0) summary = v;
    }

    let contentHtml: string = inner.replace(
      /<summary[^>]*>[\s\S]*?<\/summary>/i,
      ''
    );
    contentHtml = contentHtml.trim();

    const tagLower: string = openTag !== undefined && openTag !== null ? openTag.toLowerCase() : '';
    const isOpenByDefault: boolean = tagLower.indexOf(' open') >= 0 || tagLower.indexOf('open=') >= 0;

    const b: RichBlock = new RichBlock();
    b.key = `b_${order}`;
    b.order = order;
    b.type = RichBlockType.Details;
    b.detailsSummary = summary;
    b.detailsContentHtml = contentHtml;
    b.detailsOpen = isOpenByDefault;
    res.blocks.push(b);
    order = order + 1;
  };

  const pushSpoilerBlock = (innerHtml: string): void => {
    const htmlText: string = innerHtml !== undefined && innerHtml !== null ? innerHtml.trim() : '';
    if (htmlText.length === 0) return;
    const b: RichBlock = new RichBlock();
    b.key = `b_${order}`;
    b.order = order;
    b.type = RichBlockType.Spoiler;
    b.spoilerHtml = htmlText;
    res.blocks.push(b);
    order = order + 1;
  };

  const pushDividerBlock = (): void => {
    const b: RichBlock = new RichBlock();
    b.key = `b_${order}`;
    b.order = order;
    b.type = RichBlockType.Divider;
    res.blocks.push(b);
    order = order + 1;
  };

  const pushTableBlock = (innerHtml: string): void => {
    const rows: RichTableRow[] = extractTableRows(innerHtml);
    if (rows.length === 0) return;
    const b: RichBlock = new RichBlock();
    b.key = `b_${order}`;
    b.order = order;
    b.type = RichBlockType.Table;
    b.tableRows = rows;
    res.blocks.push(b);
    order = order + 1;
  };

  const pushPollBlock = (openTag: string, innerHtml: string): void => {
    const pollName: string = extractAttr(openTag, 'data-poll-name').trim();
    if (pollName.length === 0) return;
    const b: RichBlock = new RichBlock();
    b.key = `b_${order}`;
    b.order = order;
    b.type = RichBlockType.Poll;
    b.pollName = pollName;
    b.pollTitle = extractPollTitle(openTag, innerHtml);
    res.blocks.push(b);
    order = order + 1;
  };

  const pushMathBlock = (innerHtml: string): void => {
    const latex: string = stripHtmlKeepLines(innerHtml).trim();
    if (latex.length === 0) return;
    const b: RichBlock = new RichBlock();
    b.key = `b_${order}`;
    b.order = order;
    b.type = RichBlockType.Math;
    b.mathLatex = latex;
    res.blocks.push(b);
    order = order + 1;
  };

  const pushIframeBlock = (openTag: string): void => {
    const srcRaw: string = extractAttr(openTag, 'src').trim();
    const dataSrcRaw: string = extractAttr(openTag, 'data-src').trim();
    const src: string = UrlUtils.resolveUrl(srcRaw.length > 0 ? srcRaw : dataSrcRaw);
    if (src.length === 0) return;
    const b: RichBlock = new RichBlock();
    b.key = `b_${order}`;
    b.order = order;
    b.type = RichBlockType.Iframe;
    b.iframeSrc = src;
    b.iframeWidth = extractImgDimension(openTag, 'width');
    b.iframeHeight = extractImgDimension(openTag, 'height');
    b.iframeTitle = stripHtmlCompact(extractAttr(openTag, 'title'));
    b.iframeAllow = extractAttr(openTag, 'allow').trim();
    b.iframeClasses = extractAttr(openTag, 'class').trim();
    b.iframeAllowFullscreen = openTag.toLowerCase().indexOf('allowfullscreen') >= 0;
    res.blocks.push(b);
    order = order + 1;
  };

  const pushLazyVideoBlock = (openTag: string, innerHtml: string): void => {
    const provider: string = extractAttr(openTag, 'data-provider-name').trim();
    const videoId: string = extractAttr(openTag, 'data-video-id').trim();
    if (videoId.length === 0) return;
    const b: RichBlock = new RichBlock();
    b.key = `b_${order}`;
    b.order = order;
    b.type = RichBlockType.LazyVideo;
    b.lazyVideoProvider = provider;
    b.lazyVideoId = videoId;
    b.lazyVideoTitle = stripHtmlCompact(extractAttr(openTag, 'data-video-title'));
    b.lazyVideoStartTime = extractAttr(openTag, 'data-video-start-time').trim();
    b.lazyVideoThumbnailUrl = extractFirstImgSrc(innerHtml);
    b.lazyVideoUrl = extractFirstAnchorHrefByClass(innerHtml, 'title-link');
    if (b.lazyVideoUrl.length === 0) {
      b.lazyVideoUrl = extractFirstAnchorHref(innerHtml);
    }
    res.blocks.push(b);
    order = order + 1;
  };

  const pushChatTranscriptBlock = (openTag: string, innerHtml: string): void => {
    const b: RichBlock = new RichBlock();
    b.key = `b_${order}`;
    b.order = order;
    b.type = RichBlockType.ChatTranscript;
    b.chatTranscriptHtml = `${openTag}${innerHtml}</div>`;
    res.blocks.push(b);
    order = order + 1;
  };

  const pushImageGridBlock = (openTag: string, innerHtml: string): void => {
    const colsRaw: string = extractAttr(openTag, 'data-columns');
    let cols: number = 2;
    if (colsRaw.trim().length > 0) {
      const parsed: number = parseInt(colsRaw.trim(), 10);
      if (!isNaN(parsed) && parsed > 0) cols = parsed;
    }
    if (cols < 1) cols = 1;
    if (cols > 4) cols = 4;

    const indices: number[] = [];

    const infos: LightboxImageInfo[] = extractLightboxImageInfos(innerHtml);
    if (infos.length > 0) {
      for (let i = 0; i < infos.length; i++) {
        const info: LightboxImageInfo = infos[i];
        const thumbSrc: string = info.thumbSrc.trim().length > 0 ? info.thumbSrc : info.originalHref;
        const index: number = pushImageMeta(thumbSrc, info.originalHref, info.width, info.height);
        if (index >= 0) indices.push(index);
      }
    } else {
      const srcs: string[] = extractNonEmojiImageSrcsFromHtml(innerHtml);
      for (let i = 0; i < srcs.length; i++) {
        const index: number = pushImageMeta(srcs[i], '', 0, 0);
        if (index >= 0) indices.push(index);
      }
    }
    if (indices.length === 0) return;

    const b: RichBlock = new RichBlock();
    b.key = `b_${order}`;
    b.order = order;
    b.type = RichBlockType.ImageGrid;
    b.gridColumns = cols;
    b.gridImageIndices = indices;
    res.blocks.push(b);
    order = order + 1;
  };

  const pushOneboxBlock = (openTag: string, innerHtml: string): void => {
    const info: OneboxInfo = extractOneboxInfo(openTag, innerHtml);
    if (info.url.length === 0 && info.title.length === 0 && info.description.length === 0) return;
    const b: RichBlock = new RichBlock();
    b.key = `b_${order}`;
    b.order = order;
    b.type = RichBlockType.Onebox;
    b.oneboxUrl = info.url;
    b.oneboxTitle = info.title;
    b.oneboxDescription = info.description;
    b.oneboxSource = info.source;
    b.oneboxIconUrl = info.iconUrl;
    b.oneboxThumbnailUrl = info.thumbnailUrl;
    res.blocks.push(b);
    order = order + 1;
  };

  while (idx < raw.length) {
    const q: number = lower.indexOf('<blockquote', idx);
    const p: number = lower.indexOf('<pre', idx);
    const img: number = lower.indexOf('<img', idx);
    const aside: number = lower.indexOf('<aside', idx);
    const ul: number = lower.indexOf('<ul', idx);
    const ol: number = lower.indexOf('<ol', idx);
    const details: number = lower.indexOf('<details', idx);
    const div: number = lower.indexOf('<div', idx);
    const table: number = lower.indexOf('<table', idx);
    const iframe: number = lower.indexOf('<iframe', idx);
    const hr: number = lower.indexOf('<hr', idx);
    const h1: number = lower.indexOf('<h1', idx);
    const h2: number = lower.indexOf('<h2', idx);
    const h3: number = lower.indexOf('<h3', idx);
    const h4: number = lower.indexOf('<h4', idx);
    const h5: number = lower.indexOf('<h5', idx);
    const h6: number = lower.indexOf('<h6', idx);

    let next: number = -1;
    let nextType: number = 0;
    const consider = (pos: number, type: number): void => {
      if (pos < 0) return;
      if (next < 0 || pos < next) {
        next = pos;
        nextType = type;
      }
    };
    consider(q, 1);
    consider(p, 2);
    consider(img, 3);
    consider(aside, 4);
    consider(ul, 5);
    consider(ol, 6);
    consider(details, 7);
    consider(div, 8);
    consider(table, 9);
    consider(iframe, 10);
    consider(hr, 11);
    consider(h1, 101);
    consider(h2, 102);
    consider(h3, 103);
    consider(h4, 104);
    consider(h5, 105);
    consider(h6, 106);

    if (next < 0) {
      textBuf = `${textBuf}${raw.substring(idx)}`;
      break;
    }

    if (next > idx) {
      textBuf = `${textBuf}${raw.substring(idx, next)}`;
    }

    if (nextType === 1) {
      flushTextBlock();
      const startEnd: number = raw.indexOf('>', next);
      const end: number = lower.indexOf('</blockquote>', startEnd >= 0 ? startEnd : next);
      if (startEnd >= 0 && end >= 0) {
        pushQuoteBlock(raw.substring(startEnd + 1, end));
        idx = end + '</blockquote>'.length;
      } else {
        // 不完整的块：按纯文本兜底
        textBuf = `${textBuf}${raw.substring(next, Math.min(raw.length, next + 12))}`;
        idx = next + 12;
      }
      continue;
    }

    if (nextType === 2) {
      flushTextBlock();
      const startEnd: number = raw.indexOf('>', next);
      const end: number = lower.indexOf('</pre>', startEnd >= 0 ? startEnd : next);
      if (startEnd >= 0 && end >= 0) {
        pushCodeBlock(raw.substring(startEnd + 1, end));
        idx = end + '</pre>'.length;
      } else {
        textBuf = `${textBuf}${raw.substring(next, Math.min(raw.length, next + 5))}`;
        idx = next + 5;
      }
      continue;
    }

    if (nextType === 3) {
      const end: number = raw.indexOf('>', next);
      if (end >= 0) {
        const tag: string = raw.substring(next, end + 1);
        // 内联 emoji/小图标：保留在 Text 块中，由 tokenizeInline 负责转 ImageSpan
        if (isEmojiImg(tag) || isSmallInlineImg(tag)) {
          textBuf = `${textBuf}${tag}`;
        } else {
          flushTextBlock();
          const src: string = extractImgSrc(tag);
          const w: number = extractImgDimension(tag, 'width');
          const h: number = extractImgDimension(tag, 'height');
          pushImageBlock(src, '', w, h);
        }
        idx = end + 1;
      } else {
        idx = next + 4;
      }
      continue;
    }

    if (nextType === 4) {
      const startEnd: number = raw.indexOf('>', next);
      if (startEnd >= 0) {
        const openTag: string = raw.substring(next, startEnd + 1);
        const cls: string = extractAttr(openTag, 'class').toLowerCase();
        if (cls.indexOf('quote') >= 0) {
          flushTextBlock();
          const end: number = findMatchingCloseTag(lower, next, 'aside');
          if (end >= 0) {
            pushAsideQuoteBlock(openTag, raw.substring(startEnd + 1, end));
            idx = end + '</aside>'.length;
          } else {
            textBuf = `${textBuf}${raw.substring(next, Math.min(raw.length, next + 8))}`;
            idx = next + 8;
          }
          continue;
        }
        if (cls.indexOf('onebox') < 0) {
          // 非 onebox：当普通标签处理（交由 tokenizeInline 忽略标签，仅保留文本内容）
          textBuf = `${textBuf}${openTag}`;
          idx = startEnd + 1;
          continue;
        }

        flushTextBlock();
        const end: number = findMatchingCloseTag(lower, next, 'aside');
        if (end >= 0) {
          pushOneboxBlock(openTag, raw.substring(startEnd + 1, end));
          idx = end + '</aside>'.length;
        } else {
          textBuf = `${textBuf}${raw.substring(next, Math.min(raw.length, next + 8))}`;
          idx = next + 8;
        }
      } else {
        idx = next + 5;
      }
      continue;
    }

    if (nextType === 5 || nextType === 6) {
      const tagName: string = nextType === 5 ? 'ul' : 'ol';
      const closeTag: string = `</${tagName}>`;
      const startEnd: number = raw.indexOf('>', next);
      if (startEnd >= 0) {
        flushTextBlock();
        const end: number = findMatchingCloseTag(lower, next, tagName);
        if (end >= 0) {
          const inner: string = raw.substring(startEnd + 1, end);
          const items: string[] = extractTopLevelListItems(inner);
          if (items.length > 0) {
            pushListBlock(tagName === 'ol', items);
          } else {
            // 兜底：无法解析 items 时按纯文本保留
            textBuf = `${textBuf}${raw.substring(next, end + closeTag.length)}`;
          }
          idx = end + closeTag.length;
        } else {
          textBuf = `${textBuf}${raw.substring(next, Math.min(raw.length, next + 4))}`;
          idx = next + 4;
        }
      } else {
        idx = next + 3;
      }
      continue;
    }

    if (nextType >= 101 && nextType <= 106) {
      const level: number = nextType - 100;
      const tagName: string = `h${level}`;
      const closeTag: string = `</${tagName}>`;
      const startEnd: number = raw.indexOf('>', next);
      if (startEnd >= 0) {
        flushTextBlock();
        const end: number = findMatchingCloseTag(lower, next, tagName);
        if (end >= 0) {
          pushHeadingBlock(level, raw.substring(startEnd + 1, end));
          idx = end + closeTag.length;
        } else {
          textBuf = `${textBuf}${raw.substring(next, Math.min(raw.length, next + 4))}`;
          idx = next + 4;
        }
      } else {
        idx = next + 3;
      }
      continue;
    }

    if (nextType === 7) {
      const startEnd: number = raw.indexOf('>', next);
      if (startEnd >= 0) {
        const openTag: string = raw.substring(next, startEnd + 1);
        flushTextBlock();
        const end: number = findMatchingCloseTag(lower, next, 'details');
        if (end >= 0) {
          pushDetailsBlock(openTag, raw.substring(startEnd + 1, end));
          idx = end + '</details>'.length;
        } else {
          textBuf = `${textBuf}${raw.substring(next, Math.min(raw.length, next + 8))}`;
          idx = next + 8;
        }
      } else {
        idx = next + 8;
      }
      continue;
    }

    if (nextType === 8) {
      const startEnd: number = raw.indexOf('>', next);
      if (startEnd >= 0) {
        const openTag: string = raw.substring(next, startEnd + 1);
        const cls: string = extractAttr(openTag, 'class').toLowerCase();
        const end: number = findMatchingCloseTag(lower, next, 'div');

        if (cls.indexOf('poll') >= 0 && end >= 0) {
          flushTextBlock();
          pushPollBlock(openTag, raw.substring(startEnd + 1, end));
          idx = end + '</div>'.length;
          continue;
        }

        if (cls.indexOf('chat-transcript') >= 0 && end >= 0) {
          flushTextBlock();
          pushChatTranscriptBlock(openTag, raw.substring(startEnd + 1, end));
          idx = end + '</div>'.length;
          continue;
        }

        if (cls.indexOf('lazy-video-container') >= 0 && end >= 0) {
          flushTextBlock();
          pushLazyVideoBlock(openTag, raw.substring(startEnd + 1, end));
          idx = end + '</div>'.length;
          continue;
        }

        if (cls.indexOf('math') >= 0 && end >= 0) {
          flushTextBlock();
          pushMathBlock(raw.substring(startEnd + 1, end));
          idx = end + '</div>'.length;
          continue;
        }

        if ((cls.indexOf('spoiler') >= 0 || cls.indexOf('spoiler-blurred') >= 0) && end >= 0) {
          flushTextBlock();
          pushSpoilerBlock(raw.substring(startEnd + 1, end));
          idx = end + '</div>'.length;
          continue;
        }

        // Discourse 图片网格：div.d-image-grid
        if (cls.indexOf('d-image-grid') >= 0) {
          flushTextBlock();
          if (end >= 0) {
            pushImageGridBlock(openTag, raw.substring(startEnd + 1, end));
            idx = end + '</div>'.length;
          } else {
            textBuf = `${textBuf}${raw.substring(next, Math.min(raw.length, next + 5))}`;
            idx = next + 5;
          }
          continue;
        }

        // 单图 lightbox 容器：吞掉 meta/文件信息，只保留图片本身
        if (cls.indexOf('lightbox-wrapper') >= 0) {
          flushTextBlock();
          if (end >= 0) {
            const inner: string = raw.substring(startEnd + 1, end);
            const infos: LightboxImageInfo[] = extractLightboxImageInfos(inner);
            if (infos.length > 0) {
              for (let i = 0; i < infos.length; i++) {
                const info: LightboxImageInfo = infos[i];
                const thumbSrc: string = info.thumbSrc.trim().length > 0 ? info.thumbSrc : info.originalHref;
                pushImageBlock(thumbSrc, info.originalHref, info.width, info.height);
              }
            } else {
              const srcs: string[] = extractNonEmojiImageSrcsFromHtml(inner);
              if (srcs.length > 0) {
                for (let i = 0; i < srcs.length; i++) {
                  pushImageBlock(srcs[i], '', 0, 0);
                }
              } else {
                textBuf = `${textBuf}${raw.substring(next, end + '</div>'.length)}`;
              }
            }
            idx = end + '</div>'.length;
          } else {
            textBuf = `${textBuf}${raw.substring(next, Math.min(raw.length, next + 5))}`;
            idx = next + 5;
          }
          continue;
        }

        // 其它 div：当普通标签处理（交由 tokenizeInline 忽略标签，仅保留文本内容）
        textBuf = `${textBuf}${openTag}`;
        idx = startEnd + 1;
      } else {
        idx = next + 4;
      }
      continue;
    }

    if (nextType === 9) {
      const startEnd: number = raw.indexOf('>', next);
      if (startEnd >= 0) {
        flushTextBlock();
        const end: number = findMatchingCloseTag(lower, next, 'table');
        if (end >= 0) {
          pushTableBlock(raw.substring(startEnd + 1, end));
          idx = end + '</table>'.length;
        } else {
          textBuf = `${textBuf}${raw.substring(next, Math.min(raw.length, next + 7))}`;
          idx = next + 7;
        }
      } else {
        idx = next + 6;
      }
      continue;
    }

    if (nextType === 10) {
      const end: number = raw.indexOf('>', next);
      if (end >= 0) {
        flushTextBlock();
        const openTag: string = raw.substring(next, end + 1);
        pushIframeBlock(openTag);
        const closeStart: number = lower.indexOf('</iframe>', end + 1);
        idx = closeStart >= 0 ? (closeStart + '</iframe>'.length) : (end + 1);
      } else {
        idx = next + 7;
      }
      continue;
    }

    if (nextType === 11) {
      const end: number = raw.indexOf('>', next);
      if (end >= 0) {
        flushTextBlock();
        pushDividerBlock();
        idx = end + 1;
      } else {
        idx = next + 3;
      }
      continue;
    }

    idx = next + 1;
  }

  flushTextBlock();

  // 后处理：清理紧邻图片块的附件描述文本（避免显示 image...KB 尾巴）
  if (res.blocks.length > 1) {
    const filtered: RichBlock[] = [];
    for (let i = 0; i < res.blocks.length; i++) {
      const b: RichBlock = res.blocks[i];
      const prev: RichBlock | null = i > 0 ? res.blocks[i - 1] : null;
      if (
        prev !== null
        && (prev.type === RichBlockType.Image || prev.type === RichBlockType.ImageGrid)
        && b.type === RichBlockType.Text
      ) {
        if (isImageAttachmentTailText(b.html)) {
          continue;
        }
      }
      filtered.push(b);
    }
    res.blocks = filtered;
  }
  return res;
}

function normalizeHref(rawHref: string): string {
  const h: string = rawHref !== undefined && rawHref !== null ? rawHref.trim() : '';
  if (h.length === 0) return '';
  if (h.startsWith('http')) return h;
  if (h.startsWith('//')) return `https:${h}`;
  if (h.startsWith('/')) return UrlUtils.resolveUrl(h);
  return h;
}

function tokenizeInline(html: string): RichSpanToken[] {
  const raw0: string = html !== undefined && html !== null ? html : '';
  // cooked HTML 常包含源换行（格式化用途），与 </p>/<br> 的换行叠加会制造“双空行”
  const raw: string = raw0.replace(/\r/g, '').replace(/\n+/g, ' ');
  const out: RichSpanToken[] = [];
  let buf: string = '';
  let order: number = 0;

  let boldDepth: number = 0;
  let italicDepth: number = 0;
  let underlineDepth: number = 0;
  let strikeDepth: number = 0;
  let codeDepth: number = 0;
  let supDepth: number = 0;
  let subDepth: number = 0;

  const linkStack: string[] = [];

  const currentHref = (): string | null => {
    if (linkStack.length === 0) return null;
    return linkStack[linkStack.length - 1];
  };

  const appendToken = (text: string, href: string | null): void => {
    let decoded: string = decodeHtmlEntities(text);
    decoded = decoded.replace(/\r/g, '');
    // 连续空行最多保留 1 个
    decoded = decoded.replace(/\n[ \t]*\n+/g, '\n');
    // 去掉换行周围多余空格
    decoded = decoded.replace(/[ \t]+\n/g, '\n');
    decoded = decoded.replace(/\n[ \t]+/g, '\n');
    if (decoded.length === 0) return;

    // 去重：前一个 token 已以换行结尾时，不再重复插入换行
    if (decoded.startsWith('\n') && out.length > 0) {
      const last: RichSpanToken = out[out.length - 1];
      if (last.text.endsWith('\n')) {
        decoded = decoded.replace(/^\n+/g, '');
        if (decoded.length === 0) return;
      }
    }

    const mergeable: boolean = out.length > 0;
    if (mergeable) {
      const last: RichSpanToken = out[out.length - 1];
      const curBold: boolean = boldDepth > 0;
      const curItalic: boolean = italicDepth > 0;
      const curUnderline: boolean = underlineDepth > 0;
      const curStrike: boolean = strikeDepth > 0;
      const curCode: boolean = codeDepth > 0;
      const curSup: boolean = supDepth > 0;
      const curSub: boolean = subDepth > 0;
      if (
        last.type === RichSpanTokenType.Text
        && last.href === href
        && last.bold === curBold
        && last.italic === curItalic
        && last.underline === curUnderline
        && last.strike === curStrike
        && last.code === curCode
        && last.sup === curSup
        && last.sub === curSub
      ) {
        last.text = `${last.text}${decoded}`;
        return;
      }
    }

    const t: RichSpanToken = new RichSpanToken();
    t.key = `s_${order}`;
    t.text = decoded;
    t.type = RichSpanTokenType.Text;
    t.bold = boldDepth > 0;
    t.italic = italicDepth > 0;
    t.underline = underlineDepth > 0;
    t.strike = strikeDepth > 0;
    t.code = codeDepth > 0;
    t.sup = supDepth > 0;
    t.sub = subDepth > 0;
    t.href = href;
    out.push(t);
    order = order + 1;
  };

  const appendEmoji = (urlRaw: string, altRaw: string, href: string | null): void => {
    const url: string = UrlUtils.resolveUrl(urlRaw);
    if (url.length === 0) {
      const fallback: string = decodeHtmlEntities(altRaw);
      if (fallback.trim().length > 0) {
        appendToken(fallback, href);
      }
      return;
    }

    const alt: string = decodeHtmlEntities(altRaw);
    const t: RichSpanToken = new RichSpanToken();
    t.key = `s_${order}`;
    t.text = alt.length > 0 ? alt : ' ';
    t.type = RichSpanTokenType.Emoji;
    t.emojiUrl = url;
    t.href = href;
    out.push(t);
    order = order + 1;
  };

  const appendMentionToken = (textRaw: string, href: string | null): void => {
    const text: string = decodeHtmlEntities(textRaw).trim();
    if (text.length === 0) return;
    const t: RichSpanToken = new RichSpanToken();
    t.key = `s_${order}`;
    t.text = text;
    t.type = RichSpanTokenType.Mention;
    t.href = href;
    out.push(t);
    order = order + 1;
  };

  const appendFootnoteToken = (labelRaw: string, footnoteId: string): void => {
    const text0: string = decodeHtmlEntities(labelRaw).trim();
    if (text0.length === 0) return;
    const text: string = text0.startsWith('[') ? text0 : `[${text0}]`;
    const t: RichSpanToken = new RichSpanToken();
    t.key = `s_${order}`;
    t.text = text;
    t.type = RichSpanTokenType.FootnoteRef;
    t.metaId = footnoteId;
    out.push(t);
    order = order + 1;
  };

  const appendInlineSpoilerToken = (innerHtml: string): void => {
    const text: string = stripHtmlKeepLines(innerHtml).replace(/\n+/g, ' ').trim();
    if (text.length === 0) return;
    const t: RichSpanToken = new RichSpanToken();
    t.key = `s_${order}`;
    t.text = text;
    t.type = RichSpanTokenType.InlineSpoiler;
    t.extraHtml = innerHtml;
    out.push(t);
    order = order + 1;
  };

  const appendInlineMathToken = (innerHtml: string): void => {
    const text: string = stripHtmlKeepLines(innerHtml).replace(/\n+/g, ' ').trim();
    if (text.length === 0) return;
    const t: RichSpanToken = new RichSpanToken();
    t.key = `s_${order}`;
    t.text = text;
    t.type = RichSpanTokenType.InlineMath;
    out.push(t);
    order = order + 1;
  };

  const appendClickCountToken = (innerHtml: string): void => {
    const text: string = stripHtmlKeepLines(innerHtml).replace(/\n+/g, ' ').trim();
    if (text.length === 0) return;
    const t: RichSpanToken = new RichSpanToken();
    t.key = `s_${order}`;
    t.text = text;
    t.type = RichSpanTokenType.ClickCount;
    out.push(t);
    order = order + 1;
  };

  const flushBuf = (): void => {
    if (buf.length === 0) return;
    appendToken(buf, currentHref());
    buf = '';
  };

  let i: number = 0;
  while (i < raw.length) {
    const ch: string = raw.charAt(i);
    if (ch !== '<') {
      buf = `${buf}${ch}`;
      i = i + 1;
      continue;
    }

    const end: number = raw.indexOf('>', i);
    if (end < 0) {
      buf = `${buf}${raw.substring(i)}`;
      break;
    }

    const tagRaw: string = raw.substring(i + 1, end).trim();
    const tagLower: string = tagRaw.toLowerCase();

    // 注释
    if (tagLower.startsWith('!--')) {
      const endComment: number = raw.indexOf('-->', i);
      if (endComment >= 0) {
        i = endComment + 3;
        continue;
      }
    }

    flushBuf();

    const isClosing: boolean = tagLower.startsWith('/');
    let tagBody: string = isClosing ? tagLower.substring(1).trim() : tagLower;
    if (tagBody.endsWith('/')) {
      tagBody = tagBody.substring(0, tagBody.length - 1).trim();
    }

    const spaceIdx: number = tagBody.indexOf(' ');
    const tagName: string = (spaceIdx >= 0 ? tagBody.substring(0, spaceIdx) : tagBody).trim();

    if (!isClosing && tagName === 'a') {
      const fullTag: string = `<${tagRaw}>`;
      const cls: string = extractAttr(fullTag, 'class').toLowerCase();
      if (cls.indexOf('mention') >= 0) {
        const closeStart: number = findMatchingCloseTag(raw.toLowerCase(), i, 'a');
        if (closeStart > end) {
          const innerHtml: string = raw.substring(end + 1, closeStart);
          appendMentionToken(stripHtmlKeepLines(innerHtml), normalizeHref(extractAttr(fullTag, 'href')));
          i = closeStart + '</a>'.length;
          continue;
        }
      }
    }

    if (!isClosing && tagName === 'sup') {
      const fullTag: string = `<${tagRaw}>`;
      const cls: string = extractAttr(fullTag, 'class').toLowerCase();
      if (cls.indexOf('footnote-ref') >= 0) {
        const closeStart: number = findMatchingCloseTag(raw.toLowerCase(), i, 'sup');
        if (closeStart > end) {
          const innerHtml: string = raw.substring(end + 1, closeStart);
          const anchorHtml: string = extractLastAnchorOuterHtml(innerHtml);
          const href: string = extractAttr(anchorHtml, 'href').trim();
          const footnoteId: string = href.startsWith('#') ? href.substring(1) : href;
          appendFootnoteToken(stripHtmlKeepLines(innerHtml), footnoteId);
          i = closeStart + '</sup>'.length;
          continue;
        }
      }
    }

    if (!isClosing && tagName === 'span') {
      const fullTag: string = `<${tagRaw}>`;
      const cls: string = extractAttr(fullTag, 'class').toLowerCase();
      if (cls.indexOf('click-count') >= 0) {
        const closeStart: number = findMatchingCloseTag(raw.toLowerCase(), i, 'span');
        if (closeStart > end) {
          appendClickCountToken(raw.substring(end + 1, closeStart));
          i = closeStart + '</span>'.length;
          continue;
        }
      }
      if (cls.indexOf('math') >= 0) {
        const closeStart: number = findMatchingCloseTag(raw.toLowerCase(), i, 'span');
        if (closeStart > end) {
          appendInlineMathToken(raw.substring(end + 1, closeStart));
          i = closeStart + '</span>'.length;
          continue;
        }
      }
      if (cls.indexOf('spoiler') >= 0 || cls.indexOf('spoiler-blurred') >= 0) {
        const closeStart: number = findMatchingCloseTag(raw.toLowerCase(), i, 'span');
        if (closeStart > end) {
          appendInlineSpoilerToken(raw.substring(end + 1, closeStart));
          i = closeStart + '</span>'.length;
          continue;
        }
      }
    }

    if (tagName === 'br') {
      appendToken('\n', currentHref());
      i = end + 1;
      continue;
    }
    if (tagName === 'p') {
      if (isClosing) {
        appendToken('\n', currentHref());
      }
      i = end + 1;
      continue;
    }
    if (tagName === 'li') {
      if (!isClosing) {
        appendToken('\n• ', currentHref());
      } else {
        appendToken('\n', currentHref());
      }
      i = end + 1;
      continue;
    }

    if (tagName === 'strong' || tagName === 'b') {
      boldDepth = isClosing ? Math.max(0, boldDepth - 1) : (boldDepth + 1);
      i = end + 1;
      continue;
    }
    if (tagName === 'em' || tagName === 'i') {
      italicDepth = isClosing ? Math.max(0, italicDepth - 1) : (italicDepth + 1);
      i = end + 1;
      continue;
    }
    if (tagName === 'u') {
      underlineDepth = isClosing ? Math.max(0, underlineDepth - 1) : (underlineDepth + 1);
      i = end + 1;
      continue;
    }
    if (tagName === 's' || tagName === 'del') {
      strikeDepth = isClosing ? Math.max(0, strikeDepth - 1) : (strikeDepth + 1);
      i = end + 1;
      continue;
    }
    if (tagName === 'code') {
      codeDepth = isClosing ? Math.max(0, codeDepth - 1) : (codeDepth + 1);
      i = end + 1;
      continue;
    }
    if (tagName === 'sup') {
      supDepth = isClosing ? Math.max(0, supDepth - 1) : (supDepth + 1);
      i = end + 1;
      continue;
    }
    if (tagName === 'sub') {
      subDepth = isClosing ? Math.max(0, subDepth - 1) : (subDepth + 1);
      i = end + 1;
      continue;
    }

    if (tagName === 'a') {
      if (!isClosing) {
        const hrefRaw: string = extractAttr(`<${tagRaw}>`, 'href');
        const href: string = normalizeHref(hrefRaw);
        if (href.length > 0) {
          linkStack.push(href);
        }
      } else {
        if (linkStack.length > 0) {
          linkStack.splice(linkStack.length - 1, 1);
        }
      }
      i = end + 1;
      continue;
    }

    if (tagName === 'img') {
      const fullTag: string = `<${tagRaw}>`;
      if (isEmojiImg(fullTag) || isSmallInlineImg(fullTag)) {
        const alt: string = extractAttr(fullTag, 'alt');
        const title: string = extractAttr(fullTag, 'title');
        const value: string = alt.length > 0 ? alt : title;
        const src: string = extractImgSrc(fullTag);
        appendEmoji(src, value, currentHref());
      }
      i = end + 1;
      continue;
    }

    // 忽略其它标签（span/div 等）
    i = end + 1;
  }

  flushBuf();

  // 清理：去掉开头/结尾多余换行
  while (out.length > 0 && out[0].text.trim().length === 0 && out[0].text.indexOf('\n') >= 0) {
    out.splice(0, 1);
  }
  while (out.length > 0) {
    const last: RichSpanToken = out[out.length - 1];
    if (last.text.trim().length === 0 && last.text.indexOf('\n') >= 0) {
      out.splice(out.length - 1, 1);
      continue;
    }
    break;
  }

  return out;
}

@ComponentV2
export struct PostRichContent {
  @Param cookedHtml: string = '';
  @Param post: Post | null = null;
  // 块与块之间间距（vp）
  @Param blockGapVp: number = 8;
  // 紧凑模式：用于嵌套（li/details 等）
  @Param dense: boolean = false;
  // 引用/灰框内渲染：默认文本颜色使用 secondary
  @Param quoteMode: boolean = false;
  @Param allowPollInteraction: boolean = false;
  @Param enableSelectionQuote: boolean = false;
  @Param enableCopyQuoteSelection: boolean = false;
  @Event onOpenLink: (url: string) => void = () => {
  };
  @Event onOpenImagePreview: (urls: string[], initialIndex: number) => void = () => {
  };
  @Event onLongPressImage: (imageUrl: string, previewUrl: string) => void = () => {
  };
  @Event onQuoteSelection: (selectedText: string, sourceHtml: string) => void = (_: string, _sourceHtml: string) => {
  };
  @Event onCopyQuoteSelection: (selectedText: string, sourceHtml: string) => void = (_: string, _sourceHtml: string) => {
  };
  @Event onPostUpdated: (post: Post) => void = (_: Post) => {
  };

  @Local private parsed: RichParseResult = new RichParseResult();
  @Local private contentWidthVp: number = 0;
  @Local private selectionText: string = '';
  @Local private selectionSourceHtml: string = '';
  @Local private inlineSpoilerKeys: string[] = [];
  @Local private blockSpoilerKeys: string[] = [];
  @Local private isFootnoteSheetVisible: boolean = false;
  @Local private activeFootnoteTitle: string = '';
  @Local private activeFootnoteHtml: string = '';
  private suppressImageClickUntil: number = 0;

  aboutToAppear(): void {
    this.refreshParsedContent();
  }

  @Monitor('cookedHtml')
  onCookedHtmlChange(): void {
    this.refreshParsedContent();
  }

  private getRenderableHtml(): string {
    const raw: string = this.cookedHtml !== undefined && this.cookedHtml !== null ? this.cookedHtml : '';
    if (raw.length === 0) return '';
    if (this.post === null || this.post.linkCounts === null || this.post.linkCounts.length === 0) {
      return raw;
    }
    return injectLinkClickCounts(raw, this.post.linkCounts);
  }

  private refreshParsedContent(): void {
    this.parsed = parseBlocks(this.getRenderableHtml());
  }

  private updateContentWidthVp(widthValue: number | string | Resource): void {
    const rawWidth: number = (widthValue !== undefined && widthValue !== null && typeof widthValue === 'number')
      ? (widthValue as number) : 0;
    if (rawWidth <= 0) return;

    let resolvedWidthVp: number = rawWidth;
    const uiContext = this.getUIContext();
    if (uiContext !== undefined && uiContext !== null) {
      try {
        const convertedVp: number = uiContext.px2vp(rawWidth);
        if (convertedVp > 0) {
          resolvedWidthVp = convertedVp;

          // onAreaChange 在这里更像是直接给了 vp；若再 px2vp 一次会把正文可用宽度缩得过小，
          // 典型表现就是横向截图被压成一小块。这里用“过小宽度”启发式兜底回 raw 值。
          const tooSmallFloor: number = this.dense ? 120 : 180;
          const rawLooksReasonableFloor: number = this.dense ? 160 : 220;
          if (convertedVp < tooSmallFloor && rawWidth > rawLooksReasonableFloor) {
            resolvedWidthVp = rawWidth;
          }
        }
      } catch (_) {
      }
    }

    this.contentWidthVp = resolvedWidthVp;
  }

  private getPreviewUrls(): string[] {
    return this.parsed.imagePreviewUrls.length > 0 ? this.parsed.imagePreviewUrls : this.parsed.imageUrls;
  }

  private getImageThumbUrl(index: number): string {
    if (index < 0 || index >= this.parsed.imageUrls.length) return '';
    const u: string = this.parsed.imageUrls[index] !== undefined && this.parsed.imageUrls[index] !== null ? this.parsed.imageUrls[index] : '';
    return u;
  }

  private getImageWidth(index: number): number {
    if (index < 0 || index >= this.parsed.imageWidths.length) return 0;
    const v: number = this.parsed.imageWidths[index] !== undefined && this.parsed.imageWidths[index] !== null ? this.parsed.imageWidths[index] : 0;
    return v > 0 ? v : 0;
  }

  private getImageHeight(index: number): number {
    if (index < 0 || index >= this.parsed.imageHeights.length) return 0;
    const v: number = this.parsed.imageHeights[index] !== undefined && this.parsed.imageHeights[index] !== null ? this.parsed.imageHeights[index] : 0;
    return v > 0 ? v : 0;
  }

  private getBodyFontSize(): number {
    return this.dense ? 13 : 14;
  }

  private getBodyLineHeight(): number {
    return this.dense ? 20 : 21;
  }

  private getBodySupFontSize(): number {
    return this.dense ? 11 : 12;
  }

  private getBaseTextColor(): Resource {
    return this.quoteMode ? $r('app.color.on_surface_secondary') : $r('app.color.on_surface');
  }

  private getClickCountFontSize(baseFontSize: number): number {
    const size: number = Math.round(baseFontSize) - 4;
    return size >= 10 ? size : 10;
  }

  private getImageAvailableWidthVp(): number {
    if (this.contentWidthVp > 0) {
      return this.contentWidthVp;
    }
    return this.dense ? 240 : 300;
  }

  private getImageMaxHeightVp(): number {
    // 对齐安卓/FluxDO：正文单图基本不做人为高度压缩，避免竖图因限高再次变窄
    return this.dense ? 420 : 4096;
  }

  private getImageDefaultHeightVp(): number {
    return this.dense ? 200 : 320;
  }

  private getImageMinWidthVp(): number {
    const availableWidth: number = this.getImageAvailableWidthVp();
    // 非 dense（正文）：优先满宽显示；dense（嵌套）保持更紧凑
    if (!this.dense) {
      return availableWidth;
    }
    let minWidth: number = availableWidth * 0.54;
    const floor: number = 164;
    const ceiling: number = 224;
    if (minWidth < floor) minWidth = floor;
    if (minWidth > ceiling) minWidth = ceiling;
    if (minWidth > availableWidth) minWidth = availableWidth;
    return minWidth;
  }

  private getImageDisplaySizeVp(index: number): ImageDisplaySize {
    const size: ImageDisplaySize = new ImageDisplaySize();
    const availableWidth: number = this.getImageAvailableWidthVp();
    if (availableWidth <= 0) {
      size.width = this.dense ? 240 : 300;
      size.height = this.getImageDefaultHeightVp();
      return size;
    }

    let displayWidth: number = this.getImageWidth(index);
    let displayHeight: number = this.getImageHeight(index);
    if (displayWidth <= 0 || displayHeight <= 0) {
      size.width = availableWidth;
      size.height = this.getImageDefaultHeightVp();
      return size;
    }

    const maxH: number = this.getImageMaxHeightVp();
    // 对齐安卓/FluxDO：正文块图宽度跟随容器，原始 width/height 主要只用于保留宽高比
    const aspectRatio: number = displayHeight / displayWidth;
    displayWidth = availableWidth;
    displayHeight = displayWidth * aspectRatio;

    if (displayHeight > maxH) {
      const heightScale: number = maxH / displayHeight;
      displayHeight = maxH;
      displayWidth = displayWidth * heightScale;
    }

    if (
      !isFinite(displayWidth) || !isFinite(displayHeight)
      || displayWidth <= 0 || displayHeight <= 0
    ) {
      size.width = availableWidth;
      size.height = this.getImageDefaultHeightVp();
      return size;
    }

    size.width = displayWidth;
    size.height = displayHeight;
    return size;
  }

  private calcImageHeightVp(index: number): number {
    return this.getImageDisplaySizeVp(index).height;
  }

  private calcImageDisplayWidthVp(index: number): number {
    return this.getImageDisplaySizeVp(index).width;
  }

  private openImagePreview(index: number): void {
    if (Date.now() < this.suppressImageClickUntil) {
      return;
    }
    const previewUrls: string[] = this.getPreviewUrls();
    if (index >= 0 && index < previewUrls.length) {
      this.onOpenImagePreview(previewUrls, index);
    }
  }

  private emitImageLongPress(imageUrl: string, previewUrl: string): void {
    this.suppressImageClickUntil = Date.now() + 900;
    this.onLongPressImage(imageUrl, previewUrl);
  }

  private buildInlinePlainText(html: string): string {
    const tokens: RichSpanToken[] = tokenizeInline(html);
    let out: string = '';
    for (let i = 0; i < tokens.length; i++) {
      out = `${out}${tokens[i].text}`;
    }
    return out;
  }

  private syncSelectionText(displayText: string, selectionStart: number, selectionEnd: number, sourceHtml: string): void {
    const source: string = displayText !== undefined && displayText !== null ? displayText : '';
    const textLength: number = source.length;
    let start: number = selectionStart;
    let end: number = selectionEnd;
    if (start < 0) start = 0;
    if (end < 0) end = 0;
    if (start > textLength) start = textLength;
    if (end > textLength) end = textLength;
    if (end < start) {
      const next: number = start;
      start = end;
      end = next;
    }
    if (end <= start) {
      this.selectionText = '';
      this.selectionSourceHtml = '';
      return;
    }
    this.selectionText = source.substring(start, end).trim();
    this.selectionSourceHtml = sourceHtml !== undefined && sourceHtml !== null ? sourceHtml : '';
  }

  private wrapSelectionWithTag(tagName: string, innerHtml: string, attrs: string = ''): string {
    const tag: string = tagName !== undefined && tagName !== null ? tagName.trim() : '';
    if (tag.length === 0) {
      return innerHtml !== undefined && innerHtml !== null ? innerHtml : '';
    }
    const rawAttrs: string = attrs !== undefined && attrs !== null ? attrs.trim() : '';
    const attrText: string = rawAttrs.length > 0 ? ` ${rawAttrs}` : '';
    const inner: string = innerHtml !== undefined && innerHtml !== null ? innerHtml : '';
    return `<${tag}${attrText}>${inner}</${tag}>`;
  }

  private buildHeadingSelectionSourceHtml(level: number, html: string): string {
    const safeLevel: number = Math.max(1, Math.min(6, level));
    return this.wrapSelectionWithTag(`h${safeLevel}`, html);
  }

  private buildQuoteSelectionSourceHtml(sourceHtml: string): string {
    return this.wrapSelectionWithTag('blockquote', sourceHtml);
  }

  private buildListItemSelectionSourceHtml(ordered: boolean, index: number, sourceHtml: string): string {
    const tagName: string = ordered ? 'ol' : 'ul';
    let attrs: string = '';
    if (ordered && index > 0) {
      attrs = `start="${index + 1}"`;
    }
    return this.wrapSelectionWithTag(tagName, this.wrapSelectionWithTag('li', sourceHtml), attrs);
  }

  private buildSpoilerSelectionSourceHtml(sourceHtml: string): string {
    return this.wrapSelectionWithTag('div', sourceHtml, 'class="spoiler"');
  }

  private buildTableCellSelectionSourceHtml(sourceHtml: string, header: boolean): string {
    const cellTag: string = header ? 'th' : 'td';
    const rowHtml: string = this.wrapSelectionWithTag('tr', this.wrapSelectionWithTag(cellTag, sourceHtml));
    return this.wrapSelectionWithTag('table', rowHtml);
  }

  private buildDetailsSelectionSourceHtml(sourceHtml: string, summary: string, openByDefault: boolean): string {
    const summaryText: string = escapeHtmlText(summary !== undefined && summary !== null ? summary : '详情');
    const detailsInner: string = `${this.wrapSelectionWithTag('summary', summaryText)}${sourceHtml !== undefined && sourceHtml !== null ? sourceHtml : ''}`;
    return this.wrapSelectionWithTag('details', detailsInner, openByDefault ? 'open' : '');
  }

  private getMentionInfo(text: string): MentionedUser | null {
    if (this.post === null || this.post.mentionedUsers === null) return null;
    const mentionText: string = text !== undefined && text !== null ? text.trim().replace(/^@+/, '') : '';
    if (mentionText.length === 0) return null;
    const users: MentionedUser[] = this.post.mentionedUsers as MentionedUser[];
    for (let i = 0; i < users.length; i++) {
      const user: MentionedUser = users[i];
      if (user.username.trim().toLowerCase() === mentionText.toLowerCase()) {
        return user;
      }
    }
    return null;
  }

  private getMentionStatusEmoji(text: string): string {
    const user: MentionedUser | null = this.getMentionInfo(text);
    if (user === null || user.statusEmoji === null) return '';
    return user.statusEmoji as string;
  }

  private getMentionStatusEmojiUrl(text: string): string {
    const rawEmoji: string = this.getMentionStatusEmoji(text);
    return rawEmoji.length > 0 ? EmojiResolver.resolveEmojiUrl(rawEmoji) : '';
  }

  private isInlineSpoilerRevealed(key: string): boolean {
    for (let i = 0; i < this.inlineSpoilerKeys.length; i++) {
      if (this.inlineSpoilerKeys[i] === key) return true;
    }
    return false;
  }

  private revealInlineSpoiler(key: string): void {
    if (this.isInlineSpoilerRevealed(key)) return;
    const next: string[] = [];
    for (let i = 0; i < this.inlineSpoilerKeys.length; i++) {
      next.push(this.inlineSpoilerKeys[i]);
    }
    next.push(key);
    this.inlineSpoilerKeys = next;
  }

  private isBlockSpoilerRevealed(key: string): boolean {
    for (let i = 0; i < this.blockSpoilerKeys.length; i++) {
      if (this.blockSpoilerKeys[i] === key) return true;
    }
    return false;
  }

  private revealBlockSpoiler(key: string): void {
    if (this.isBlockSpoilerRevealed(key)) return;
    const next: string[] = [];
    for (let i = 0; i < this.blockSpoilerKeys.length; i++) {
      next.push(this.blockSpoilerKeys[i]);
    }
    next.push(key);
    this.blockSpoilerKeys = next;
  }

  private openFootnote(footnoteId: string, label: string): void {
    const id: string = footnoteId !== undefined && footnoteId !== null ? footnoteId.trim() : '';
    if (id.length === 0 || !this.parsed.footnotes.has(id)) {
      ToastService.show('脚注内容不可用');
      return;
    }
    const html: string = this.parsed.footnotes.get(id) as string;
    if (html.trim().length === 0) {
      ToastService.show('脚注内容为空');
      return;
    }
    this.activeFootnoteTitle = label.length > 0 ? label : '脚注';
    this.activeFootnoteHtml = html;
    this.isFootnoteSheetVisible = true;
  }

  private getSelectionMenuOptions(): ExpandedMenuOptions[] {
    const out: ExpandedMenuOptions[] = [];
    if (this.enableSelectionQuote) {
      out.push({
        content: '引用',
        action: () => {
          const selectedText: string = this.selectionText !== undefined && this.selectionText !== null
            ? this.selectionText.trim()
            : '';
          if (selectedText.length > 0) {
            this.onQuoteSelection(selectedText, this.selectionSourceHtml);
          }
        }
      });
    }
    if (this.enableCopyQuoteSelection) {
      out.push({
        content: '复制引用',
        action: () => {
          const selectedText: string = this.selectionText !== undefined && this.selectionText !== null
            ? this.selectionText.trim()
            : '';
          if (selectedText.length > 0) {
            this.onCopyQuoteSelection(selectedText, this.selectionSourceHtml);
          }
        }
      });
    }
    return out;
  }

  @Builder
  private QuoteSelectionMenuBuilder() {
    SelectionMenu({
      expandedMenuOptions: this.getSelectionMenuOptions()
    })
  }

  private getOneboxUrl(b: RichBlock): string {
    return b.oneboxUrl !== undefined && b.oneboxUrl !== null ? b.oneboxUrl : '';
  }

  private getOneboxSourceText(b: RichBlock): string {
    const url: string = this.getOneboxUrl(b);
    const host: string = extractUrlHost(url);
    const raw: string = b.oneboxSource !== undefined && b.oneboxSource !== null ? b.oneboxSource.toString().trim() : '';
    if (raw.length > 0) return raw;
    if (host.length > 0) return host;
    return url;
  }

  private getOneboxTitleText(b: RichBlock): string {
    const url: string = this.getOneboxUrl(b);
    const host: string = extractUrlHost(url);
    const raw: string = b.oneboxTitle !== undefined && b.oneboxTitle !== null ? b.oneboxTitle.toString().trim() : '';
    if (raw.length > 0) return raw;
    if (host.length > 0) return host;
    return url;
  }

  private getOneboxDescriptionText(b: RichBlock): string {
    return b.oneboxDescription !== undefined && b.oneboxDescription !== null ? b.oneboxDescription.toString().trim() : '';
  }

  private getOneboxIconUrl(b: RichBlock): string {
    return b.oneboxIconUrl !== undefined && b.oneboxIconUrl !== null ? b.oneboxIconUrl.toString().trim() : '';
  }

  private getOneboxThumbnailUrl(b: RichBlock): string {
    return b.oneboxThumbnailUrl !== undefined && b.oneboxThumbnailUrl !== null ? b.oneboxThumbnailUrl.toString().trim() : '';
  }

  private hasStructuredQuoteHeader(block: RichBlock): boolean {
    return block.quoteUsername.trim().length > 0
      || block.quoteAvatarUrl.trim().length > 0
      || block.quoteTitleHtml.trim().length > 0
      || block.quoteContentHtml.trim().length > 0;
  }

  private getQuoteHeaderTitleText(block: RichBlock): string {
    return stripHtmlCompact(block.quoteTitleHtml);
  }

  private getQuoteRenderableHtml(block: RichBlock): string {
    if (block.quoteContentHtml.trim().length > 0) {
      return block.quoteContentHtml;
    }
    return block.html.length > 0 ? block.html : block.text;
  }

  @Builder
  private QuoteCard(block: RichBlock, marginTop: number) {
    Column() {
      if (this.hasStructuredQuoteHeader(block)) {
        Row() {
          if (block.quoteAvatarUrl.trim().length > 0) {
            SmartAvatar({
              avatarUrl: block.quoteAvatarUrl,
              avatarSize: 24,
              avatarRadius: 12,
              fallbackText: block.quoteUsername,
              bgColor: '#E8EAF0'
            })
            Blank().width(8)
          }

          Row() {
            Text(`${block.quoteUsername}:`)
              .fontSize(13)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.on_surface_secondary'))

            if (this.getQuoteHeaderTitleText(block).length > 0) {
              Text(this.getQuoteHeaderTitleText(block))
                .fontSize(13)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.primary'))
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .layoutWeight(1)
                .margin({ left: 4 })
            }
          }
          .layoutWeight(1)
          .alignItems(VerticalAlign.Center)
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
        .padding({ left: 12, right: 12, top: 8, bottom: 0 })

        PostRichContent({
          cookedHtml: this.getQuoteRenderableHtml(block),
          post: this.post,
          dense: true,
          quoteMode: true,
          blockGapVp: 8,
          allowPollInteraction: this.allowPollInteraction,
          enableSelectionQuote: this.enableSelectionQuote,
          enableCopyQuoteSelection: this.enableCopyQuoteSelection,
          onOpenLink: (url: string) => {
            this.onOpenLink(url);
          },
          onOpenImagePreview: (urls: string[], initialIndex: number) => {
            this.onOpenImagePreview(urls, initialIndex);
          },
          onQuoteSelection: (selectedText: string, sourceHtml: string) => {
            this.onQuoteSelection(selectedText, this.buildQuoteSelectionSourceHtml(sourceHtml));
          },
          onCopyQuoteSelection: (selectedText: string, sourceHtml: string) => {
            this.onCopyQuoteSelection(selectedText, this.buildQuoteSelectionSourceHtml(sourceHtml));
          },
          onLongPressImage: (imageUrl: string, previewUrl: string) => {
            this.onLongPressImage(imageUrl, previewUrl);
          },
          onPostUpdated: (post: Post) => {
            this.onPostUpdated(post);
          }
        })
        .padding({ left: 12, right: 12, top: 8, bottom: 8 })
      } else {
        PostRichContent({
          cookedHtml: this.getQuoteRenderableHtml(block),
          post: this.post,
          dense: true,
          quoteMode: true,
          blockGapVp: 8,
          allowPollInteraction: this.allowPollInteraction,
          enableSelectionQuote: this.enableSelectionQuote,
          enableCopyQuoteSelection: this.enableCopyQuoteSelection,
          onOpenLink: (url: string) => {
            this.onOpenLink(url);
          },
          onOpenImagePreview: (urls: string[], initialIndex: number) => {
            this.onOpenImagePreview(urls, initialIndex);
          },
          onQuoteSelection: (selectedText: string, sourceHtml: string) => {
            this.onQuoteSelection(selectedText, this.buildQuoteSelectionSourceHtml(sourceHtml));
          },
          onCopyQuoteSelection: (selectedText: string, sourceHtml: string) => {
            this.onCopyQuoteSelection(selectedText, this.buildQuoteSelectionSourceHtml(sourceHtml));
          },
          onLongPressImage: (imageUrl: string, previewUrl: string) => {
            this.onLongPressImage(imageUrl, previewUrl);
          },
          onPostUpdated: (post: Post) => {
            this.onPostUpdated(post);
          }
        })
        .padding({ left: 12, right: 12, top: 10, bottom: 10 })
      }
    }
    .width('100%')
    .backgroundColor($r('app.color.surface_variant'))
    .borderRadius({ topLeft: 4, bottomLeft: 4, topRight: 8, bottomRight: 8 })
    .borderWidth({ left: 4, top: 0, right: 0, bottom: 0 })
    .borderColor({ left: $r('app.color.on_surface_secondary') })
    .margin({ top: marginTop })
  }

  private getHeadingFontSize(level: number): number {
    switch (level) {
      case 1:
        return 20;
      case 2:
        return 18;
      case 3:
        return 16;
      case 4:
        return 15;
      case 5:
        return 14;
      case 6:
        return 13;
      default:
        return 16;
    }
  }

  private getCodeLangLabel(language: string): string {
    const raw: string = language !== undefined && language !== null ? language.toString().trim() : '';
    return raw.length > 0 ? raw.toUpperCase() : '代码';
  }

  private isMermaidLanguage(language: string): boolean {
    const raw: string = language !== undefined && language !== null ? language.toString().trim().toLowerCase() : '';
    return raw === 'mermaid';
  }

  private normalizeCodeText(text: string): string {
    let raw: string = text !== undefined && text !== null ? text : '';
    raw = raw.replace(/\r/g, '');
    if (raw.endsWith('\n')) {
      raw = raw.substring(0, raw.length - 1);
    }
    return raw;
  }

  private getCodeLineCount(text: string): number {
    const raw: string = this.normalizeCodeText(text);
    if (raw.length === 0) {
      return 1;
    }
    return Math.max(1, raw.split('\n').length);
  }

  private getCodeLineNumberWidthVp(text: string): number {
    const digits: number = this.getCodeLineCount(text).toString().length;
    return Math.max(36, digits * 8 + 18);
  }

  private buildCodeLineNumbers(text: string): string {
    const lineCount: number = this.getCodeLineCount(text);
    let numbers: string = '';
    for (let i = 0; i < lineCount; i++) {
      numbers = numbers.length === 0 ? `${i + 1}` : `${numbers}\n${i + 1}`;
    }
    return numbers;
  }

  private getCodeContentHeight(text: string): number {
    return this.getCodeLineCount(text) * 20 + 24;
  }

  private shouldUseCodeVerticalScroll(text: string): boolean {
    return this.getCodeContentHeight(text) > 320;
  }

  private estimateCodeHeight(text: string): number {
    return Math.min(360, this.getCodeContentHeight(text));
  }

  private clampGridColumns(columns: number): number {
    let cols: number = Math.round(columns);
    if (cols < 1) cols = 1;
    if (cols > 4) cols = 4;
    return cols;
  }

  private buildRange(count: number): number[] {
    const out: number[] = [];
    const n: number = Math.max(0, Math.round(count));
    for (let i = 0; i < n; i++) {
      out.push(i);
    }
    return out;
  }

  private buildGridRowIndices(itemCount: number, columns: number): number[] {
    const cols: number = this.clampGridColumns(columns);
    if (cols <= 0) return [];
    const count: number = Math.max(0, itemCount);
    const rowCount: number = Math.ceil(count / cols);
    return this.buildRange(rowCount);
  }

  private buildGridColIndices(columns: number): number[] {
    return this.buildRange(this.clampGridColumns(columns));
  }

  private getGridImageIndex(indices: number[], row: number, col: number, columns: number): number {
    const cols: number = this.clampGridColumns(columns);
    const flatIndex: number = row * cols + col;
    if (flatIndex < 0 || flatIndex >= indices.length) return -1;
    return indices[flatIndex];
  }

  private getGridImageUrl(imageUrls: string[], indices: number[], row: number, col: number, columns: number): string {
    const imgIndex: number = this.getGridImageIndex(indices, row, col, columns);
    if (imgIndex < 0 || imgIndex >= imageUrls.length) return '';
    const url: string = imageUrls[imgIndex] !== undefined && imageUrls[imgIndex] !== null ? imageUrls[imgIndex] : '';
    return url;
  }

  @Builder
  private ClickCountInline(text: string, baseFontSize: number) {
    Span(`\u2009${text}\u2009`)
      .fontSize(this.getClickCountFontSize(baseFontSize))
      .fontColor($r('app.color.on_surface_secondary'))
      .fontWeight(FontWeight.Medium)
      .textBackgroundStyle({
        color: $r('app.color.surface_variant'),
        radius: 10
      })
  }

  @Builder
  private DividerBlock(marginTop: number) {
    Column() {
      Blank()
        .width('100%')
        .height(1)
        .backgroundColor($r('app.color.divider_light'))
    }
    .width('100%')
    .padding({ top: 12, bottom: 12 })
    .margin({ top: marginTop })
  }

  @Builder
  private HeadingBlock(html: string, level: number, marginTop: number) {
    Text() {
      ForEach(tokenizeInline(html), (t: RichSpanToken) => {
        if (t.type === RichSpanTokenType.Emoji && t.emojiUrl.length > 0) {
          ImageSpan(t.emojiUrl)
            .width(this.getHeadingFontSize(level) + 2)
            .height(this.getHeadingFontSize(level) + 2)
            .margin({ left: 1, right: 1 })
            .verticalAlign(ImageSpanAlignment.CENTER)
            .onClick(() => {
              if (t.href !== null && (t.href as string).length > 0) {
                this.onOpenLink(t.href as string);
              }
            })
        } else if (t.type === RichSpanTokenType.Mention) {
          Span(t.text)
            .fontColor($r('app.color.primary'))
            .fontWeight(FontWeight.Bold)
            .onClick(() => {
              if (t.href !== null && (t.href as string).length > 0) {
                this.onOpenLink(t.href as string);
              }
            })
          if (this.getMentionStatusEmojiUrl(t.text).length > 0) {
            ImageSpan(this.getMentionStatusEmojiUrl(t.text))
              .width(this.getHeadingFontSize(level))
              .height(this.getHeadingFontSize(level))
              .margin({ left: 2, right: 1 })
              .verticalAlign(ImageSpanAlignment.CENTER)
          } else if (this.getMentionStatusEmoji(t.text).length > 0) {
            Span(this.getMentionStatusEmoji(t.text))
              .fontSize(this.getHeadingFontSize(level) - 2)
          }
        } else if (t.type === RichSpanTokenType.FootnoteRef) {
          Span(t.text)
            .fontColor($r('app.color.primary'))
            .fontSize(Math.max(10, this.getHeadingFontSize(level) - 5))
            .fontWeight(FontWeight.Bold)
            .onClick(() => {
              this.openFootnote(t.metaId, t.text);
            })
        } else if (t.type === RichSpanTokenType.InlineSpoiler) {
          Span(this.isInlineSpoilerRevealed(t.key) ? t.text : '[剧透]')
            .fontColor(this.isInlineSpoilerRevealed(t.key) ? $r('app.color.on_surface') : $r('app.color.on_surface_secondary'))
            .fontWeight(FontWeight.Bold)
            .onClick(() => {
              this.revealInlineSpoiler(t.key);
            })
        } else if (t.type === RichSpanTokenType.InlineMath) {
          Span(t.text)
            .fontColor($r('app.color.on_surface'))
            .fontFamily('monospace')
            .fontSize(this.getHeadingFontSize(level) - 2)
            .backgroundColor($r('app.color.surface_variant'))
        } else if (t.type === RichSpanTokenType.ClickCount) {
          this.ClickCountInline(t.text, this.getHeadingFontSize(level))
        } else if (t.href !== null && (t.href as string).length > 0) {
          Span(t.text)
            .fontColor($r('app.color.primary'))
            .onClick(() => {
              this.onOpenLink(t.href as string);
            })
            .fontWeight(FontWeight.Bold)
            .fontStyle(t.italic ? FontStyle.Italic : FontStyle.Normal)
            .fontFamily(t.code ? 'monospace' : '')
        } else {
          Span(t.text)
            .fontColor($r('app.color.on_surface'))
            .decoration({ type: t.strike ? TextDecorationType.LineThrough : (t.underline ? TextDecorationType.Underline : TextDecorationType.None) })
            .fontWeight(FontWeight.Bold)
            .fontStyle(t.italic ? FontStyle.Italic : FontStyle.Normal)
            .fontFamily(t.code ? 'monospace' : '')
        }
      }, (t: RichSpanToken) => t.key)
    }
    .fontSize(this.getHeadingFontSize(level))
    .lineHeight(this.getHeadingFontSize(level) + 6)
    .copyOption(CopyOptions.LocalDevice)
    .onTextSelectionChange((selectionStart: number, selectionEnd: number) => {
      this.syncSelectionText(
        this.buildInlinePlainText(html),
        selectionStart,
        selectionEnd,
        this.buildHeadingSelectionSourceHtml(level, html)
      );
    })
    .bindSelectionMenu(TextSpanType.DEFAULT, this.QuoteSelectionMenuBuilder, TextResponseType.LONG_PRESS)
    .width('100%')
    .margin({ top: marginTop })
  }

  @Builder
  private CodeCard(text: string, language: string, marginTop: number) {
    if (this.isMermaidLanguage(language)) {
      RichMermaidBlock({
        code: text,
        marginTop: marginTop,
        onOpenImagePreview: (urls: string[], initialIndex: number) => {
          this.onOpenImagePreview(urls, initialIndex);
        }
      })
    } else {
      Column() {
        Row() {
          Text(this.getCodeLangLabel(language))
            .fontSize(12)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.on_surface_secondary'))

          Blank().layoutWeight(1)

          Row() {
            SymbolGlyph($r('sys.symbol.doc_text'))
              .fontSize(14)
              .fontColor([$r('app.color.on_surface_secondary')])
              .margin({ right: 4 })
            Text('复制')
              .fontSize(11)
              .fontColor($r('app.color.on_surface_secondary'))
          }
          .padding({ left: 4, right: 4, top: 2, bottom: 2 })
          .borderRadius(6)
          .onClick(() => {
            ClipboardService.copyText(this.normalizeCodeText(text), false).then((ok: boolean) => {
              if (ok) ToastService.show('已复制代码');
            });
          })
        }
        .width('100%')
        .padding({ left: 12, right: 12, top: 8, bottom: 8 })
        .backgroundColor($r('app.color.surface_variant'))

        Blank()
          .width('100%')
          .height(0.5)
          .backgroundColor($r('app.color.divider_light'))

        if (this.shouldUseCodeVerticalScroll(text)) {
          Scroll() {
            Row() {
              Column() {
                Text(this.buildCodeLineNumbers(text))
                  .width('100%')
                  .fontSize(12)
                  .fontColor($r('app.color.on_surface_tertiary'))
                  .lineHeight(20)
                  .fontFamily('monospace')
                  .textAlign(TextAlign.End)
                  .padding({ left: 8, right: 8, top: 12, bottom: 12 })
              }
              .width(this.getCodeLineNumberWidthVp(text))
              .backgroundColor('#FAFAFA')

              Blank()
                .width(0.5)
                .height('100%')
                .backgroundColor($r('app.color.divider_light'))

              Scroll() {
                Text(this.normalizeCodeText(text))
                  .fontSize(13)
                  .fontColor($r('app.color.on_surface'))
                  .lineHeight(20)
                  .fontFamily('monospace')
                  .padding({ left: 12, right: 12, top: 12, bottom: 12 })
              }
              .layoutWeight(1)
              .scrollable(ScrollDirection.Horizontal)
              .scrollBar(BarState.Off)
            }
            .alignItems(VerticalAlign.Top)
            .height(this.getCodeContentHeight(text))
            .width('100%')
          }
          .scrollable(ScrollDirection.Vertical)
          .scrollBar(BarState.Off)
          .height(this.estimateCodeHeight(text))
        } else {
          Row() {
            Column() {
              Text(this.buildCodeLineNumbers(text))
                .width('100%')
                .fontSize(12)
                .fontColor($r('app.color.on_surface_tertiary'))
                .lineHeight(20)
                .fontFamily('monospace')
                .textAlign(TextAlign.End)
                .padding({ left: 8, right: 8, top: 12, bottom: 12 })
            }
            .width(this.getCodeLineNumberWidthVp(text))
            .backgroundColor('#FAFAFA')

            Blank()
              .width(0.5)
              .height('100%')
              .backgroundColor($r('app.color.divider_light'))

            Scroll() {
              Text(this.normalizeCodeText(text))
                .fontSize(13)
                .fontColor($r('app.color.on_surface'))
                .lineHeight(20)
                .fontFamily('monospace')
                .padding({ left: 12, right: 12, top: 12, bottom: 12 })
            }
            .layoutWeight(1)
            .scrollable(ScrollDirection.Horizontal)
            .scrollBar(BarState.Off)
          }
          .alignItems(VerticalAlign.Top)
          .height(this.getCodeContentHeight(text))
          .width('100%')
        }
      }
      .width('100%')
      .backgroundColor($r('app.color.surface'))
      .border({ width: 0.5, color: $r('app.color.divider_light') })
      .borderRadius(10)
      .margin({ top: marginTop })
      .clip(true)
    }
  }

  @Builder
  private ImageBlock(imageIndex: number, marginTop: number) {
    if (this.getImageThumbUrl(imageIndex).length > 0) {
      Row() {
        Image(this.getImageThumbUrl(imageIndex))
          .width(this.calcImageDisplayWidthVp(imageIndex))
          .height(this.calcImageHeightVp(imageIndex))
          .objectFit(ImageFit.Contain)
          .interpolation(ImageInterpolation.High)
          .borderRadius(8)
          .draggable(false)
          .enableAnalyzer(false)
      }
      .width('100%')
      .justifyContent(FlexAlign.Start)
      .margin({ top: marginTop })
      .onClick(() => {
        this.openImagePreview(imageIndex);
      })
      .parallelGesture(
        LongPressGesture({ repeat: false, duration: 500 })
          .onAction(() => {
            const thumbUrl: string = this.getImageThumbUrl(imageIndex);
            const previewUrls: string[] = this.getPreviewUrls();
            const previewUrl: string = imageIndex >= 0 && imageIndex < previewUrls.length ? previewUrls[imageIndex] : thumbUrl;
            this.emitImageLongPress(thumbUrl, previewUrl);
          })
      )
    } else {
      Blank().height(0).width('100%')
    }
  }

  @Builder
  private ImageGridBlock(thumbUrls: string[], previewUrls: string[], indices: number[], columns: number, marginTop: number) {
    if (indices.length === 1) {
      // 单图：不要以网格形式“半宽”展示，直接按正文图片块逻辑满宽展示
      this.ImageBlock(indices[0], marginTop)
    } else {
      Column() {
        ForEach(this.buildGridRowIndices(indices.length, columns), (r: number) => {
          Row() {
            ForEach(this.buildGridColIndices(columns), (c: number) => {
              if (this.getGridImageUrl(thumbUrls, indices, r, c, columns).length > 0) {
                Column() {
                  Image(this.getGridImageUrl(thumbUrls, indices, r, c, columns))
                    .height(160)
                    .width('100%')
                    .objectFit(ImageFit.Cover)
                    .borderRadius(4)
                    .draggable(false)
                    .enableAnalyzer(false)
                }
                .layoutWeight(1)
                .onClick(() => {
                  if (this.getGridImageIndex(indices, r, c, columns) >= 0) {
                    this.openImagePreview(this.getGridImageIndex(indices, r, c, columns));
                  }
                })
                .parallelGesture(
                  LongPressGesture({ repeat: false, duration: 500 })
                    .onAction(() => {
                      const imgIdx: number = this.getGridImageIndex(indices, r, c, columns);
                      if (imgIdx >= 0 && imgIdx < thumbUrls.length) {
                        const pUrl: string = imgIdx < previewUrls.length ? previewUrls[imgIdx] : thumbUrls[imgIdx];
                        this.emitImageLongPress(thumbUrls[imgIdx], pUrl);
                      }
                    })
                )
              } else {
                Blank()
                  .height(160)
                  .layoutWeight(1)
              }

              if (c < this.clampGridColumns(columns) - 1) {
                Blank().width(6)
              }
            }, (c: number) => `${r}_${c}`)
          }
          .width('100%')
          .margin({ top: r === 0 ? 0 : 6 })
        }, (r: number) => `${r}`)
      }
      .width('100%')
      .margin({ top: marginTop })
    }
  }

  @Builder
  private InlineTextBlock(html: string, marginTop: number) {
    Text() {
      ForEach(tokenizeInline(html), (t: RichSpanToken) => {
        if (t.type === RichSpanTokenType.Emoji && t.emojiUrl.length > 0) {
          ImageSpan(t.emojiUrl)
            .width(this.getBodyFontSize() + 3)
            .height(this.getBodyFontSize() + 3)
            .margin({ left: 1, right: 1 })
            .verticalAlign(ImageSpanAlignment.CENTER)
            .onClick(() => {
              if (t.href !== null && (t.href as string).length > 0) {
                this.onOpenLink(t.href as string);
              }
            })
        } else if (t.type === RichSpanTokenType.Mention) {
          Span(t.text)
            .fontColor($r('app.color.primary'))
            .fontWeight(FontWeight.Medium)
            .onClick(() => {
              if (t.href !== null && (t.href as string).length > 0) {
                this.onOpenLink(t.href as string);
              }
            })
            .fontSize(this.getBodyFontSize() - 1)
          if (this.getMentionStatusEmojiUrl(t.text).length > 0) {
            ImageSpan(this.getMentionStatusEmojiUrl(t.text))
              .width(this.getBodyFontSize() + 2)
              .height(this.getBodyFontSize() + 2)
              .margin({ left: 2, right: 1 })
              .verticalAlign(ImageSpanAlignment.CENTER)
          } else if (this.getMentionStatusEmoji(t.text).length > 0) {
            Span(this.getMentionStatusEmoji(t.text))
              .fontSize(this.getBodyFontSize() - 1)
          }
        } else if (t.type === RichSpanTokenType.FootnoteRef) {
          Span(t.text)
            .fontColor($r('app.color.primary'))
            .fontSize(this.getBodySupFontSize())
            .fontWeight(FontWeight.Bold)
            .onClick(() => {
              this.openFootnote(t.metaId, t.text);
            })
        } else if (t.type === RichSpanTokenType.InlineSpoiler) {
          Span(this.isInlineSpoilerRevealed(t.key) ? t.text : '[剧透]')
            .fontColor(this.isInlineSpoilerRevealed(t.key) ? this.getBaseTextColor() : $r('app.color.on_surface_secondary'))
            .fontWeight(FontWeight.Medium)
            .onClick(() => {
              this.revealInlineSpoiler(t.key);
            })
        } else if (t.type === RichSpanTokenType.InlineMath) {
          Span(t.text)
            .fontColor($r('app.color.on_surface'))
            .fontFamily('monospace')
            .fontSize(this.getBodyFontSize() - 1)
            .backgroundColor($r('app.color.surface_variant'))
        } else if (t.type === RichSpanTokenType.ClickCount) {
          this.ClickCountInline(t.text, this.getBodyFontSize())
        } else if (t.href !== null && (t.href as string).length > 0) {
          Span(t.text)
            .fontColor($r('app.color.primary'))
            .onClick(() => {
              this.onOpenLink(t.href as string);
            })
            .fontWeight(t.bold ? FontWeight.Bold : FontWeight.Normal)
            .fontStyle(t.italic ? FontStyle.Italic : FontStyle.Normal)
            .fontFamily(t.code ? 'monospace' : '')
            .fontSize((t.sup || t.sub) ? this.getBodySupFontSize() : this.getBodyFontSize())
        } else {
          Span(t.text)
            .fontColor(t.code ? '#E06C75' : this.getBaseTextColor())
            .decoration({ type: t.strike ? TextDecorationType.LineThrough : (t.underline ? TextDecorationType.Underline : TextDecorationType.None) })
            .fontWeight(t.bold ? FontWeight.Bold : FontWeight.Normal)
            .fontStyle(t.italic ? FontStyle.Italic : FontStyle.Normal)
            .fontFamily(t.code ? 'monospace' : '')
            .fontSize(t.code ? (this.getBodyFontSize() - 1) : ((t.sup || t.sub) ? this.getBodySupFontSize() : this.getBodyFontSize()))
            .backgroundColor(t.code ? '#1A000000' : Color.Transparent)
        }
      }, (t: RichSpanToken) => t.key)
    }
    .fontSize(this.getBodyFontSize())
    .lineHeight(this.getBodyLineHeight())
    .copyOption(CopyOptions.LocalDevice)
    .onTextSelectionChange((selectionStart: number, selectionEnd: number) => {
      this.syncSelectionText(this.buildInlinePlainText(html), selectionStart, selectionEnd, html);
    })
    .bindSelectionMenu(TextSpanType.DEFAULT, this.QuoteSelectionMenuBuilder, TextResponseType.LONG_PRESS)
    .width('100%')
    .margin({ top: marginTop })
  }

  @Builder
  private ListBlock(ordered: boolean, itemsHtml: string[], marginTop: number) {
    Column() {
      ForEach(itemsHtml, (itemHtml: string, index: number) => {
        Row() {
          Text(ordered ? `${index + 1}.` : '•')
            .fontSize(this.getBodyFontSize())
            .lineHeight(this.getBodyLineHeight())
            .fontColor(this.getBaseTextColor())
            .width(22)
            .textAlign(TextAlign.End)

          Blank().width(8)

          Column() {
            PostRichContent({
              cookedHtml: itemHtml,
              post: this.post,
              dense: true,
              blockGapVp: 8,
              allowPollInteraction: this.allowPollInteraction,
              enableSelectionQuote: this.enableSelectionQuote,
              enableCopyQuoteSelection: this.enableCopyQuoteSelection,
              onOpenLink: (url: string) => {
                this.onOpenLink(url);
              },
              onOpenImagePreview: (urls: string[], initialIndex: number) => {
                this.onOpenImagePreview(urls, initialIndex);
              },
                  onQuoteSelection: (selectedText: string, sourceHtml: string) => {
                    this.onQuoteSelection(
                      selectedText,
                      this.buildListItemSelectionSourceHtml(ordered, index, sourceHtml)
                    );
                  },
                  onCopyQuoteSelection: (selectedText: string, sourceHtml: string) => {
                    this.onCopyQuoteSelection(
                      selectedText,
                      this.buildListItemSelectionSourceHtml(ordered, index, sourceHtml)
                    );
                  },
              onLongPressImage: (imageUrl: string, previewUrl: string) => {
                this.onLongPressImage(imageUrl, previewUrl);
              },
              onPostUpdated: (post: Post) => {
                this.onPostUpdated(post);
              }
            })
          }
          .layoutWeight(1)
        }
        .width('100%')
        .alignItems(VerticalAlign.Top)
        .margin({ top: index === 0 ? 0 : 6 })
      }, (itemHtml: string, index: number) => `${index}`)
    }
    .width('100%')
    .margin({ top: marginTop })
  }

  @Builder
  private OneboxCard(b: RichBlock, marginTop: number) {
    Column() {
      // 来源行
      Row() {
        if (this.getOneboxIconUrl(b).length > 0) {
          Image(this.getOneboxIconUrl(b))
            .width(16)
            .height(16)
            .objectFit(ImageFit.Contain)
            .borderRadius(4)
            .backgroundColor($r('app.color.surface'))
            .margin({ right: 6 })
        }
        Text(this.getOneboxSourceText(b))
          .fontSize(11)
          .fontColor($r('app.color.on_surface_secondary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      // 内容区（标题/描述 + 可选缩略图）
      if (this.getOneboxThumbnailUrl(b).length > 0) {
        Row() {
          Column() {
            if (this.getOneboxTitleText(b).length > 0) {
              Text(this.getOneboxTitleText(b))
                .fontSize(14)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.on_surface'))
                .maxLines(2)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            }
            if (this.getOneboxDescriptionText(b).length > 0) {
              Text(this.getOneboxDescriptionText(b))
                .fontSize(12)
                .fontColor($r('app.color.on_surface_secondary'))
                .maxLines(3)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .margin({ top: 4 })
            }
          }
          .layoutWeight(1)

          Blank().width(12)

          Image(this.getOneboxThumbnailUrl(b))
            .width(80)
            .height(80)
            .objectFit(ImageFit.Cover)
            .borderRadius(8)
            .backgroundColor($r('app.color.surface'))
        }
        .width('100%')
        .alignItems(VerticalAlign.Top)
        .margin({ top: 10 })
      } else {
        Column() {
          if (this.getOneboxTitleText(b).length > 0) {
            Text(this.getOneboxTitleText(b))
              .fontSize(14)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.on_surface'))
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          if (this.getOneboxDescriptionText(b).length > 0) {
            Text(this.getOneboxDescriptionText(b))
              .fontSize(12)
              .fontColor($r('app.color.on_surface_secondary'))
              .maxLines(3)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .margin({ top: 4 })
          }
        }
        .width('100%')
        .margin({ top: 10 })
      }
    }
    .width('100%')
    .padding(12)
    .backgroundColor($r('app.color.surface_variant'))
    .border({ width: 0.5, color: $r('app.color.divider_light') })
    .borderRadius(8)
    .margin({ top: marginTop })
    .onClick(() => {
      if (this.getOneboxUrl(b).length > 0) {
        this.onOpenLink(this.getOneboxUrl(b));
      }
    })
  }

  private getTableColumnCount(rows: RichTableRow[]): number {
    let maxCols: number = 1;
    for (let i = 0; i < rows.length; i++) {
      const count: number = rows[i].cells.length;
      if (count > maxCols) {
        maxCols = count;
      }
    }
    return maxCols;
  }

  private getTableCellWidthVp(rows: RichTableRow[]): number {
    const columns: number = Math.max(1, this.getTableColumnCount(rows));
    const available: number = this.contentWidthVp > 0 ? this.contentWidthVp : (this.dense ? 240 : 320);
    const minWidth: number = columns <= 2 ? 160 : 132;
    const computed: number = (available - Math.max(0, columns - 1) * 1) / columns;
    return Math.max(minWidth, computed);
  }

  @Builder
  private SpoilerBlock(b: RichBlock, marginTop: number) {
    Column() {
      if (!this.isBlockSpoilerRevealed(b.key)) {
        Column() {
          Text('剧透内容')
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.on_surface'))
          Text('点击查看')
            .fontSize(12)
            .fontColor($r('app.color.on_surface_secondary'))
            .margin({ top: 4 })
        }
        .width('100%')
        .padding({ left: 12, right: 12, top: 12, bottom: 12 })
        .backgroundColor($r('app.color.surface_variant'))
        .borderRadius(8)
        .onClick(() => {
          this.revealBlockSpoiler(b.key);
        })
      } else {
        PostRichContent({
          cookedHtml: b.spoilerHtml,
          post: this.post,
          dense: true,
          blockGapVp: 8,
          allowPollInteraction: this.allowPollInteraction,
          enableSelectionQuote: this.enableSelectionQuote,
          enableCopyQuoteSelection: this.enableCopyQuoteSelection,
          onOpenLink: (url: string) => {
            this.onOpenLink(url);
          },
          onOpenImagePreview: (urls: string[], initialIndex: number) => {
            this.onOpenImagePreview(urls, initialIndex);
          },
          onQuoteSelection: (selectedText: string, sourceHtml: string) => {
            this.onQuoteSelection(selectedText, this.buildSpoilerSelectionSourceHtml(sourceHtml));
          },
          onCopyQuoteSelection: (selectedText: string, sourceHtml: string) => {
            this.onCopyQuoteSelection(selectedText, this.buildSpoilerSelectionSourceHtml(sourceHtml));
          },
          onLongPressImage: (imageUrl: string, previewUrl: string) => {
            this.onLongPressImage(imageUrl, previewUrl);
          },
          onPostUpdated: (post: Post) => {
            this.onPostUpdated(post);
          }
        })
      }
    }
    .width('100%')
    .margin({ top: marginTop })
  }

  @Builder
  private TableBlock(rows: RichTableRow[], marginTop: number) {
    Scroll() {
      Column() {
        ForEach(rows, (row: RichTableRow, rowIndex: number) => {
          Row() {
            ForEach(row.cells, (cell: RichTableCell, cellIndex: number) => {
              Column() {
                PostRichContent({
                  cookedHtml: cell.html,
                  post: this.post,
                  dense: true,
                  blockGapVp: 6,
                  quoteMode: false,
                  allowPollInteraction: this.allowPollInteraction,
                  enableSelectionQuote: this.enableSelectionQuote,
                  enableCopyQuoteSelection: this.enableCopyQuoteSelection,
                  onOpenLink: (url: string) => {
                    this.onOpenLink(url);
                  },
                  onOpenImagePreview: (urls: string[], initialIndex: number) => {
                    this.onOpenImagePreview(urls, initialIndex);
                  },
                onQuoteSelection: (selectedText: string, sourceHtml: string) => {
                  this.onQuoteSelection(
                    selectedText,
                    this.buildTableCellSelectionSourceHtml(sourceHtml, cell.header)
                  );
                },
                onCopyQuoteSelection: (selectedText: string, sourceHtml: string) => {
                  this.onCopyQuoteSelection(
                    selectedText,
                    this.buildTableCellSelectionSourceHtml(sourceHtml, cell.header)
                  );
                },
                  onLongPressImage: (imageUrl: string, previewUrl: string) => {
                    this.onLongPressImage(imageUrl, previewUrl);
                  },
                  onPostUpdated: (post: Post) => {
                    this.onPostUpdated(post);
                  }
                })
              }
              .width(this.getTableCellWidthVp(rows))
              .padding(8)
              .backgroundColor(cell.header ? $r('app.color.surface_variant') : $r('app.color.surface'))
              .border({ width: 0.5, color: $r('app.color.divider_light') })

              if (cellIndex < row.cells.length - 1) {
                Blank().width(0)
              }
            }, (cell: RichTableCell, cellIndex: number) => `cell_${rowIndex}_${cellIndex}`)
          }
        }, (row: RichTableRow, rowIndex: number) => `row_${rowIndex}`)
      }
    }
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .width('100%')
    .margin({ top: marginTop })
    .border({ width: 0.5, color: $r('app.color.divider_light') })
    .borderRadius(8)
    .clip(true)
  }

  @Builder
  private FootnoteSheetBuilder() {
    Column() {
      Row() {
        Text(this.activeFootnoteTitle.length > 0 ? this.activeFootnoteTitle : '脚注')
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.on_surface'))
        Blank().layoutWeight(1)
        Text('关闭')
          .fontSize(13)
          .fontColor($r('app.color.primary'))
          .onClick(() => {
            this.isFootnoteSheetVisible = false;
          })
      }
      .width('100%')
      .margin({ bottom: 12 })

      Scroll() {
        PostRichContent({
          cookedHtml: this.activeFootnoteHtml,
          post: this.post,
          dense: true,
          blockGapVp: 8,
          allowPollInteraction: this.allowPollInteraction,
          enableSelectionQuote: this.enableSelectionQuote,
          enableCopyQuoteSelection: this.enableCopyQuoteSelection,
          onOpenLink: (url: string) => {
            this.onOpenLink(url);
          },
          onOpenImagePreview: (urls: string[], initialIndex: number) => {
            this.onOpenImagePreview(urls, initialIndex);
          },
          onQuoteSelection: (selectedText: string, sourceHtml: string) => {
            this.onQuoteSelection(selectedText, sourceHtml);
          },
          onCopyQuoteSelection: (selectedText: string, sourceHtml: string) => {
            this.onCopyQuoteSelection(selectedText, sourceHtml);
          },
          onLongPressImage: (imageUrl: string, previewUrl: string) => {
            this.onLongPressImage(imageUrl, previewUrl);
          },
          onPostUpdated: (post: Post) => {
            this.onPostUpdated(post);
          }
        })
      }
      .scrollBar(BarState.Auto)
      .width('100%')
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .padding(16)
    .backgroundColor($r('app.color.surface'))
  }

  build() {
    Column() {
      ForEach(this.parsed.blocks, (b: RichBlock) => {
        if (b.type === RichBlockType.Quote) {
          this.QuoteCard(b, b.order > 0 ? this.blockGapVp : 0)
        } else if (b.type === RichBlockType.Code) {
          this.CodeCard(b.text, b.codeLanguage, b.order > 0 ? this.blockGapVp : 0)
        } else if (b.type === RichBlockType.Image) {
          this.ImageBlock(b.imageIndex, b.order > 0 ? this.blockGapVp : 0)
        } else if (b.type === RichBlockType.List) {
          this.ListBlock(b.listOrdered, b.listItemsHtml, b.order > 0 ? this.blockGapVp : 0)
        } else if (b.type === RichBlockType.Onebox) {
          this.OneboxCard(b, b.order > 0 ? this.blockGapVp : 0)
        } else if (b.type === RichBlockType.Heading) {
          this.HeadingBlock(b.html, b.headingLevel, b.order > 0 ? this.blockGapVp : 0)
        } else if (b.type === RichBlockType.ImageGrid) {
          this.ImageGridBlock(this.parsed.imageUrls, this.getPreviewUrls(), b.gridImageIndices, b.gridColumns, b.order > 0 ? this.blockGapVp : 0)
        } else if (b.type === RichBlockType.Spoiler) {
          this.SpoilerBlock(b, b.order > 0 ? this.blockGapVp : 0)
        } else if (b.type === RichBlockType.Table) {
          this.TableBlock(b.tableRows, b.order > 0 ? this.blockGapVp : 0)
        } else if (b.type === RichBlockType.Poll) {
          RichPollBlock({
            post: this.post,
            pollName: b.pollName,
            title: b.pollTitle,
            allowInteraction: this.allowPollInteraction,
            marginTop: b.order > 0 ? this.blockGapVp : 0,
            onPollUpdated: (post: Post) => {
              this.onPostUpdated(post);
            }
          })
        } else if (b.type === RichBlockType.Math) {
          RichMathBlock({
            latex: b.mathLatex,
            marginTop: b.order > 0 ? this.blockGapVp : 0
          })
        } else if (b.type === RichBlockType.Iframe) {
          RichWebEmbedBlock({
            src: b.iframeSrc,
            title: b.iframeTitle,
            marginTop: b.order > 0 ? this.blockGapVp : 0,
            embedAspectRatio: estimateAspectRatio(b.iframeWidth, b.iframeHeight, b.iframeClasses),
            onOpenLink: (url: string) => {
              this.onOpenLink(url);
            }
          })
        } else if (b.type === RichBlockType.LazyVideo) {
          RichLazyVideoBlock({
            provider: b.lazyVideoProvider,
            videoId: b.lazyVideoId,
            title: b.lazyVideoTitle,
            thumbnailUrl: b.lazyVideoThumbnailUrl,
            videoUrl: b.lazyVideoUrl,
            startTime: b.lazyVideoStartTime,
            marginTop: b.order > 0 ? this.blockGapVp : 0,
            onOpenLink: (url: string) => {
              this.onOpenLink(url);
            }
          })
        } else if (b.type === RichBlockType.ChatTranscript) {
          RichChatTranscriptBlock({
            html: b.chatTranscriptHtml,
            post: this.post,
            marginTop: b.order > 0 ? this.blockGapVp : 0,
            allowPollInteraction: this.allowPollInteraction,
            enableSelectionQuote: this.enableSelectionQuote,
            enableCopyQuoteSelection: this.enableCopyQuoteSelection,
            onOpenLink: (url: string) => {
              this.onOpenLink(url);
            },
            onOpenImagePreview: (urls: string[], initialIndex: number) => {
              this.onOpenImagePreview(urls, initialIndex);
            },
            onQuoteSelection: (selectedText: string, sourceHtml: string) => {
              this.onQuoteSelection(selectedText, sourceHtml);
            },
            onCopyQuoteSelection: (selectedText: string, sourceHtml: string) => {
              this.onCopyQuoteSelection(selectedText, sourceHtml);
            },
            onLongPressImage: (imageUrl: string, previewUrl: string) => {
              this.onLongPressImage(imageUrl, previewUrl);
            },
            onPostUpdated: (post: Post) => {
              this.onPostUpdated(post);
            }
          })
        } else if (b.type === RichBlockType.Divider) {
          this.DividerBlock(b.order > 0 ? this.blockGapVp : 0)
        } else if (b.type === RichBlockType.Details) {
          RichDetailsBlock({
            summary: b.detailsSummary,
            contentHtml: b.detailsContentHtml,
            post: this.post,
            openByDefault: b.detailsOpen,
            marginTop: b.order > 0 ? this.blockGapVp : 0,
            allowPollInteraction: this.allowPollInteraction,
            enableSelectionQuote: this.enableSelectionQuote,
            enableCopyQuoteSelection: this.enableCopyQuoteSelection,
            onOpenLink: (url: string) => {
              this.onOpenLink(url);
            },
            onOpenImagePreview: (urls: string[], initialIndex: number) => {
              this.onOpenImagePreview(urls, initialIndex);
            },
            onQuoteSelection: (selectedText: string, sourceHtml: string) => {
              this.onQuoteSelection(
                selectedText,
                this.buildDetailsSelectionSourceHtml(sourceHtml, b.detailsSummary, b.detailsOpen)
              );
            },
            onCopyQuoteSelection: (selectedText: string, sourceHtml: string) => {
              this.onCopyQuoteSelection(
                selectedText,
                this.buildDetailsSelectionSourceHtml(sourceHtml, b.detailsSummary, b.detailsOpen)
              );
            },
            onLongPressImage: (imageUrl: string, previewUrl: string) => {
              this.onLongPressImage(imageUrl, previewUrl);
            },
            onPostUpdated: (post: Post) => {
              this.onPostUpdated(post);
            }
          })
        } else {
          this.InlineTextBlock(b.html, b.order > 0 ? this.blockGapVp : 0)
        }
      }, (b: RichBlock) => b.key)
    }
    .width('100%')
    .onAreaChange((_: Area, newArea: Area) => {
      this.updateContentWidthVp(newArea.width);
    })
    .bindSheet($$this.isFootnoteSheetVisible, this.FootnoteSheetBuilder, {
      height: SheetSize.MEDIUM,
      dragBar: true,
      backgroundColor: $r('app.color.surface'),
      onDisappear: () => {
        this.isFootnoteSheetVisible = false;
      }
    })
  }
}

@ComponentV2
struct RichMathBlock {
  @Param latex: string = '';
  @Param marginTop: number = 0;

  @Local private hasError: boolean = false;
  @Local private isLoaded: boolean = false;

  private controller: webview.WebviewController = new webview.WebviewController(nextRichWebControllerId('rich_math'));
  private didInjectContent: boolean = false;

  aboutToAppear(): void {
    this.didInjectContent = false;
    this.hasError = false;
    this.isLoaded = false;
  }

  @Monitor('latex')
  onLatexChange(): void {
    this.didInjectContent = false;
    this.hasError = false;
    this.isLoaded = false;
  }

  private getMathHeight(): number {
    const text: string = this.latex !== undefined && this.latex !== null ? this.latex : '';
    if (text.indexOf('\n') >= 0 || text.indexOf('\\begin') >= 0 || text.length > 120) {
      return 132;
    }
    if (text.length > 60) {
      return 108;
    }
    return 84;
  }

  private buildMathHtml(): string {
    const safeLatex: string = escapeHtmlText(this.latex);
    return `<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no">
  <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/katex@0.16.11/dist/katex.min.css">
  <script defer src="https://cdn.jsdelivr.net/npm/katex@0.16.11/dist/katex.min.js"></script>
  <script defer src="https://cdn.jsdelivr.net/npm/katex@0.16.11/dist/contrib/auto-render.min.js"></script>
  <style>
    html, body {
      margin: 0;
      padding: 0;
      background: transparent;
      color: #111827;
      overflow-x: auto;
      overflow-y: hidden;
      font-family: -apple-system, BlinkMacSystemFont, sans-serif;
    }
    body {
      display: flex;
      justify-content: center;
      align-items: center;
      min-height: 100vh;
      padding: 10px 12px;
      box-sizing: border-box;
    }
    #formula {
      white-space: nowrap;
      font-size: 18px;
      line-height: 1.6;
    }
  </style>
</head>
<body>
  <div id="formula">${safeLatex}</div>
  <script>
    window.addEventListener('load', function() {
      try {
        if (window.renderMathInElement) {
          window.renderMathInElement(document.body, {
            delimiters: [
              {left: '$$', right: '$$', display: true},
              {left: '$', right: '$', display: false}
            ],
            throwOnError: false
          });
          var el = document.getElementById('formula');
          if (el && window.katex) {
            try {
              window.katex.render(el.textContent || '', el, { throwOnError: false, displayMode: true });
            } catch (innerErr) {}
          }
        }
      } catch (err) {}
    });
  </script>
</body>
</html>`;
  }

  private loadMathContent(): void {
    if (this.didInjectContent || this.latex.trim().length === 0) return;
    this.didInjectContent = true;
    try {
      this.controller.setCustomUserAgent(AppConstants.USER_AGENT);
    } catch (_) {
    }
    try {
      this.controller.loadData(this.buildMathHtml(), 'text/html', 'UTF-8', AppConstants.BASE_URL, AppConstants.BASE_URL);
    } catch (_) {
      this.hasError = true;
    }
  }

  build() {
    Column() {
      Stack() {
        Web({ src: 'about:blank', controller: this.controller })
          .width('100%')
          .height(this.getMathHeight())
          .backgroundColor(Color.Transparent)
          .onPageEnd(() => {
            if (!this.didInjectContent) {
              this.loadMathContent();
            } else {
              this.isLoaded = true;
            }
          })
          .onErrorReceive((_: OnErrorReceiveEvent) => {
            this.hasError = true;
            this.isLoaded = false;
          })

        if (!this.hasError && !this.isLoaded) {
          Column() {
            Text('公式加载中…')
              .fontSize(12)
              .fontColor($r('app.color.on_surface_secondary'))
          }
          .width('100%')
          .height(this.getMathHeight())
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
          .backgroundColor($r('app.color.surface_variant'))
        }

        if (this.hasError) {
          Scroll() {
            Text(this.latex)
              .fontSize(14)
              .fontFamily('monospace')
              .fontColor($r('app.color.on_surface'))
              .padding(12)
          }
          .width('100%')
          .height(this.getMathHeight())
          .scrollable(ScrollDirection.Horizontal)
          .backgroundColor($r('app.color.surface_variant'))
        }
      }
      .width('100%')
      .height(this.getMathHeight())
      .clip(true)
      .borderRadius(8)
      .border({ width: 0.5, color: $r('app.color.divider_light') })
    }
    .width('100%')
    .margin({ top: this.marginTop })
  }
}

@ComponentV2
struct RichWebEmbedBlock {
  @Param src: string = '';
  @Param title: string = '';
  @Param embedAspectRatio: number = 16 / 9;
  @Param marginTop: number = 0;
  @Event onOpenLink: (url: string) => void = (_: string) => {
  };

  @Local private contentWidthVp: number = 0;
  @Local private isLoaded: boolean = false;
  @Local private hasError: boolean = false;

  private controller: webview.WebviewController = new webview.WebviewController(nextRichWebControllerId('rich_embed'));

  private updateContentWidthVp(widthValue: number | string | Resource): void {
    const rawWidth: number = (widthValue !== undefined && widthValue !== null && typeof widthValue === 'number')
      ? (widthValue as number) : 0;
    if (rawWidth <= 0) return;
    this.contentWidthVp = rawWidth;
  }

  private getAspectRatio(): number {
    return this.embedAspectRatio > 0 ? this.embedAspectRatio : (16 / 9);
  }

  private getEmbedHeight(): number {
    const width: number = this.contentWidthVp > 0 ? this.contentWidthVp : 320;
    return Math.max(120, Math.min(420, width / this.getAspectRatio()));
  }

  private getDisplayTitle(): string {
    const rawTitle: string = this.title !== undefined && this.title !== null ? this.title.trim() : '';
    if (rawTitle.length > 0) return rawTitle;
    const host: string = extractUrlHost(this.src);
    return host.length > 0 ? host : this.src;
  }

  build() {
    Column() {
      Stack() {
        Web({ src: this.src.length > 0 ? this.src : 'about:blank', controller: this.controller })
          .width('100%')
          .height(this.getEmbedHeight())
          .onPageBegin(() => {
            this.isLoaded = false;
            this.hasError = false;
            try {
              this.controller.setCustomUserAgent(AppConstants.USER_AGENT);
            } catch (_) {
            }
          })
          .onPageEnd(() => {
            this.isLoaded = true;
          })
          .onErrorReceive((_: OnErrorReceiveEvent) => {
            this.hasError = true;
            this.isLoaded = false;
          })

        if (!this.hasError && !this.isLoaded) {
          Column() {
            Text('嵌入内容加载中…')
              .fontSize(12)
              .fontColor($r('app.color.on_surface_secondary'))
          }
          .width('100%')
          .height(this.getEmbedHeight())
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
          .backgroundColor($r('app.color.surface_variant'))
        }

        if (this.hasError) {
          Column() {
            Text('嵌入内容加载失败')
              .fontSize(13)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.on_surface'))
            Text('浏览器打开')
              .fontSize(12)
              .fontColor($r('app.color.primary'))
              .margin({ top: 8 })
              .onClick(() => {
                if (this.src.length > 0) {
                  this.onOpenLink(this.src);
                }
              })
          }
          .width('100%')
          .height(this.getEmbedHeight())
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
          .backgroundColor($r('app.color.surface_variant'))
        }
      }
      .width('100%')
      .height(this.getEmbedHeight())
      .borderRadius(8)
      .clip(true)
      .border({ width: 0.5, color: $r('app.color.divider_light') })

      Row() {
        Text(this.getDisplayTitle())
          .layoutWeight(1)
          .fontSize(12)
          .fontColor($r('app.color.on_surface_secondary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text('浏览器打开')
          .fontSize(12)
          .fontColor($r('app.color.primary'))
          .margin({ left: 12 })
          .onClick(() => {
            if (this.src.length > 0) {
              this.onOpenLink(this.src);
            }
          })
      }
      .width('100%')
      .margin({ top: 8 })
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .margin({ top: this.marginTop })
    .onAreaChange((_: Area, newArea: Area) => {
      this.updateContentWidthVp(newArea.width);
    })
  }
}

@ComponentV2
struct RichLazyVideoBlock {
  @Param provider: string = '';
  @Param videoId: string = '';
  @Param title: string = '';
  @Param thumbnailUrl: string = '';
  @Param videoUrl: string = '';
  @Param startTime: string = '';
  @Param marginTop: number = 0;
  @Event onOpenLink: (url: string) => void = (_: string) => {
  };

  @Local private showEmbed: boolean = false;
  @Local private thumbnailFailed: boolean = false;

  private getEmbedUrl(): string {
    return buildLazyVideoEmbedUrl(this.provider, this.videoId, this.startTime);
  }

  private getBrandColor(): string {
    const raw: string = this.provider !== undefined && this.provider !== null ? this.provider.trim().toLowerCase() : '';
    if (raw === 'youtube') return '#FF0000';
    if (raw === 'vimeo') return '#1AB7EA';
    if (raw === 'tiktok') return '#111111';
    return '#666666';
  }

  private getDisplayTitle(): string {
    const rawTitle: string = this.title !== undefined && this.title !== null ? this.title.trim() : '';
    if (rawTitle.length > 0) return rawTitle;
    if (this.videoUrl.length > 0) {
      const host: string = extractUrlHost(this.videoUrl);
      if (host.length > 0) return host;
    }
    return '视频';
  }

  build() {
    if (this.showEmbed && this.getEmbedUrl().length > 0) {
      RichWebEmbedBlock({
        src: this.getEmbedUrl(),
        title: this.getDisplayTitle(),
        embedAspectRatio: 16 / 9,
        marginTop: this.marginTop,
        onOpenLink: (url: string) => {
          this.onOpenLink(url);
        }
      })
    } else {
      Column() {
        Stack() {
          if (this.thumbnailUrl.length > 0 && !this.thumbnailFailed) {
            Image(this.thumbnailUrl)
              .width('100%')
              .height(208)
              .objectFit(ImageFit.Cover)
              .onError(() => {
                this.thumbnailFailed = true;
              })
        } else {
          Column() {
            Text('▶')
              .fontSize(28)
              .fontColor(Color.White)
          }
          .width('100%')
          .height(208)
            .backgroundColor('#111111')
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center)
          }

          Column() {
            Text('▶')
              .fontSize(28)
              .fontColor(Color.White)
          }
          .width(64)
          .height(44)
          .backgroundColor(this.getBrandColor())
          .borderRadius(10)
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
        }
        .width('100%')
        .height(208)
        .onClick(() => {
          if (this.getEmbedUrl().length > 0) {
            this.showEmbed = true;
          } else if (this.videoUrl.length > 0) {
            this.onOpenLink(this.videoUrl);
          }
        })

        Row() {
          Text(this.getDisplayTitle())
            .layoutWeight(1)
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.on_surface'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })

          if (this.videoUrl.length > 0) {
            Text('打开')
              .fontSize(12)
              .fontColor($r('app.color.primary'))
              .margin({ left: 12 })
              .onClick(() => {
                this.onOpenLink(this.videoUrl);
              })
          }
        }
        .width('100%')
        .padding({ left: 12, right: 12, top: 10, bottom: 10 })
        .alignItems(VerticalAlign.Center)
        .backgroundColor($r('app.color.surface_variant'))
      }
      .width('100%')
      .borderRadius(8)
      .clip(true)
      .border({ width: 0.5, color: $r('app.color.divider_light') })
      .margin({ top: this.marginTop })
    }
  }
}

@ComponentV2
struct RichChatTranscriptBlock {
  @Param html: string = '';
  @Param post: Post | null = null;
  @Param marginTop: number = 0;
  @Param allowPollInteraction: boolean = false;
  @Param enableSelectionQuote: boolean = false;
  @Param enableCopyQuoteSelection: boolean = false;
  @Event onOpenLink: (url: string) => void = () => {
  };
  @Event onOpenImagePreview: (urls: string[], initialIndex: number) => void = () => {
  };
  @Event onQuoteSelection: (selectedText: string, sourceHtml: string) => void = (_: string, _sourceHtml: string) => {
  };
  @Event onCopyQuoteSelection: (selectedText: string, sourceHtml: string) => void = (_: string, _sourceHtml: string) => {
  };
  @Event onLongPressImage: (imageUrl: string, previewUrl: string) => void = () => {
  };
  @Event onPostUpdated: (post: Post) => void = (_: Post) => {
  };

  @Local private info: ChatTranscriptInfo = new ChatTranscriptInfo();

  aboutToAppear(): void {
    this.syncInfo();
  }

  @Monitor('html')
  onHtmlChange(): void {
    this.syncInfo();
  }

  private syncInfo(): void {
    const raw: string = this.html !== undefined && this.html !== null ? this.html.trim() : '';
    if (raw.length === 0) {
      this.info = new ChatTranscriptInfo();
      return;
    }
    const lower: string = raw.toLowerCase();
    const start: number = lower.indexOf('<div');
    const openEnd: number = start >= 0 ? raw.indexOf('>', start) : -1;
    const closeStart: number = (start >= 0 && openEnd >= 0) ? findMatchingCloseTag(lower, start, 'div') : -1;
    if (start < 0 || openEnd < 0 || closeStart <= openEnd) {
      this.info = new ChatTranscriptInfo();
      return;
    }
    const openTag: string = raw.substring(start, openEnd + 1);
    const innerHtml: string = raw.substring(openEnd + 1, closeStart);
    this.info = extractChatTranscriptInfo(openTag, innerHtml);
  }

  private getTimeText(): string {
    const time: Date | null = TimeUtils.parseUtcTime(this.info.datetime);
    const formatted: string = TimeUtils.formatRelativeTime(time);
    return formatted.length > 0 ? formatted : '';
  }

  @Builder
  private ReactionChip(reaction: ChatTranscriptReaction) {
    Row() {
      Image(reaction.emojiUrl)
        .width(16)
        .height(16)
        .objectFit(ImageFit.Contain)
      if (reaction.count > 1) {
        Text(`${reaction.count}`)
          .fontSize(11)
          .fontColor($r('app.color.on_surface_secondary'))
          .margin({ left: 4 })
      }
    }
    .padding({ left: 6, right: 6, top: 3, bottom: 3 })
    .backgroundColor($r('app.color.surface'))
    .borderRadius(10)
    .border({ width: 0.5, color: $r('app.color.divider_light') })
  }

  build() {
    Column() {
      if (this.info.channelName.length > 0 && !this.info.isChained) {
        Row() {
          Text('#')
            .fontSize(12)
            .fontColor($r('app.color.on_surface_secondary'))
          Text(this.info.channelName)
            .fontSize(11)
            .fontColor($r('app.color.on_surface_secondary'))
            .margin({ left: 4 })
        }
        .width('100%')
        .margin({ bottom: 6 })
      }

      Row() {
        SmartAvatar({
          avatarUrl: this.info.avatarUrl,
          avatarSize: 24,
          fallbackText: this.info.username,
          bgColor: '#E8EAF0'
        })

        Text(this.info.username.length > 0 ? `${this.info.username}:` : '聊天消息')
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.on_surface_secondary'))
          .margin({ left: 8 })

        if (this.getTimeText().length > 0) {
          Text(this.getTimeText())
            .fontSize(11)
            .fontColor($r('app.color.on_surface_secondary'))
            .margin({ left: 8 })
        }

        Blank().layoutWeight(1)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      if (this.info.messagesHtml.length > 0) {
        Column() {
          PostRichContent({
            cookedHtml: this.info.messagesHtml,
            post: this.post,
            dense: true,
            blockGapVp: 6,
            allowPollInteraction: this.allowPollInteraction,
            enableSelectionQuote: this.enableSelectionQuote,
            enableCopyQuoteSelection: this.enableCopyQuoteSelection,
            onOpenLink: (url: string) => {
              this.onOpenLink(url);
            },
            onOpenImagePreview: (urls: string[], initialIndex: number) => {
              this.onOpenImagePreview(urls, initialIndex);
            },
            onQuoteSelection: (selectedText: string, sourceHtml: string) => {
              this.onQuoteSelection(selectedText, sourceHtml);
            },
            onCopyQuoteSelection: (selectedText: string, sourceHtml: string) => {
              this.onCopyQuoteSelection(selectedText, sourceHtml);
            },
            onLongPressImage: (imageUrl: string, previewUrl: string) => {
              this.onLongPressImage(imageUrl, previewUrl);
            },
            onPostUpdated: (post: Post) => {
              this.onPostUpdated(post);
            }
          })
        }
        .width('100%')
        .margin({ top: 8 })
      }

      if (this.info.reactions.length > 0) {
        Flex({ wrap: FlexWrap.Wrap }) {
          ForEach(this.info.reactions, (reaction: ChatTranscriptReaction, index: number) => {
            Column() {
              this.ReactionChip(reaction)
            }
            .margin({ right: index < this.info.reactions.length - 1 ? 6 : 0, top: 4 })
          }, (reaction: ChatTranscriptReaction, index: number) => `${reaction.emojiUrl}_${index}`)
        }
        .width('100%')
        .margin({ top: 8 })
      }

      if (this.info.threadTitle.length > 0) {
        Row() {
          Text('↳')
            .fontSize(12)
            .fontColor($r('app.color.on_surface_secondary'))
          Text(this.info.threadTitle)
            .fontSize(11)
            .fontColor($r('app.color.on_surface_secondary'))
            .margin({ left: 6 })
        }
        .width('100%')
        .margin({ top: 8 })
      }
    }
    .width('100%')
    .padding(12)
    .backgroundColor($r('app.color.surface_variant'))
    .borderRadius(this.info.isChained ? 8 : 4)
    .borderWidth(
      this.info.isChained
        ? { left: 0.5, top: 0.5, right: 0.5, bottom: 0.5 }
        : { left: 4, top: 0, right: 0, bottom: 0 }
    )
    .borderColor(
      this.info.isChained
        ? {
            left: $r('app.color.divider_light'),
            top: $r('app.color.divider_light'),
            right: $r('app.color.divider_light'),
            bottom: $r('app.color.divider_light')
          }
        : {
            left: $r('app.color.on_surface_secondary'),
            top: Color.Transparent,
            right: Color.Transparent,
            bottom: Color.Transparent
          }
    )
    .margin({ top: this.marginTop })
  }
}

@ComponentV2
struct RichMermaidBlock {
  @Param code: string = '';
  @Param marginTop: number = 0;
  @Event onOpenImagePreview: (urls: string[], initialIndex: number) => void = () => {
  };

  @Local private showCode: boolean = false;
  @Local private imageFailed: boolean = false;
  @Local private retrySeed: number = 0;
  @Local private contentWidthVp: number = 0;

  private updateContentWidthVp(widthValue: number | string | Resource): void {
    const rawWidth: number = (widthValue !== undefined && widthValue !== null && typeof widthValue === 'number')
      ? (widthValue as number) : 0;
    if (rawWidth <= 0) return;
    this.contentWidthVp = rawWidth;
  }

  private getDiagramHeight(): number {
    const width: number = this.contentWidthVp > 0 ? this.contentWidthVp : 320;
    return Math.max(140, Math.min(320, width * 0.62));
  }

  private normalizeCodeText(): string {
    let raw: string = this.code !== undefined && this.code !== null ? this.code : '';
    raw = raw.replace(/\r/g, '');
    if (raw.endsWith('\n')) {
      raw = raw.substring(0, raw.length - 1);
    }
    return raw;
  }

  private getCodeLineCount(): number {
    const raw: string = this.normalizeCodeText();
    if (raw.length === 0) {
      return 1;
    }
    return Math.max(1, raw.split('\n').length);
  }

  private getCodeContentHeight(): number {
    return this.getCodeLineCount() * 20 + 24;
  }

  private shouldUseCodeVerticalScroll(): boolean {
    return this.getCodeContentHeight() > 320;
  }

  private getCodeViewportHeight(): number {
    return Math.min(360, this.getCodeContentHeight());
  }

  private buildMermaidUrl(width: number = 0): string {
    const encoded: string = base64UrlEncode(this.code);
    let url: string = `https://mermaid.ink/img/${encoded}?theme=default&bgColor=ffffff`;
    if (width > 0) {
      url = `${url}&width=${width}`;
    }
    if (this.retrySeed > 0) {
      url = `${url}&retry=${this.retrySeed}`;
    }
    return url;
  }

  build() {
    Column() {
      Row() {
        Text(this.showCode ? '图表' : '代码')
          .fontSize(12)
          .fontColor($r('app.color.on_surface_secondary'))
          .padding({ left: 8, right: 8, top: 4, bottom: 4 })
          .backgroundColor($r('app.color.surface'))
          .borderRadius(6)
          .onClick(() => {
            this.showCode = !this.showCode;
          })

        Blank().layoutWeight(1)

        Text('复制')
          .fontSize(12)
          .fontColor($r('app.color.on_surface_secondary'))
          .padding({ left: 8, right: 8, top: 4, bottom: 4 })
          .borderRadius(6)
          .onClick(() => {
            ClipboardService.copyText(this.normalizeCodeText(), false).then((ok: boolean) => {
              if (ok) {
                ToastService.show('已复制代码');
              }
            });
          })
      }
      .width('100%')
      .padding({ left: 10, right: 10, top: 8, bottom: 8 })
      .border({ width: 0.5, color: $r('app.color.divider_light') })

      if (this.showCode) {
        if (this.shouldUseCodeVerticalScroll()) {
          Scroll() {
            Scroll() {
              Text(this.normalizeCodeText())
                .width('100%')
                .fontSize(13)
                .lineHeight(20)
                .fontFamily('monospace')
                .fontColor($r('app.color.on_surface'))
                .padding(12)
            }
            .scrollable(ScrollDirection.Horizontal)
            .scrollBar(BarState.Off)
          }
          .scrollable(ScrollDirection.Vertical)
          .scrollBar(BarState.Off)
          .height(this.getCodeViewportHeight())
        } else {
          Scroll() {
            Text(this.normalizeCodeText())
              .width('100%')
              .fontSize(13)
              .lineHeight(20)
              .fontFamily('monospace')
              .fontColor($r('app.color.on_surface'))
              .padding(12)
          }
          .height(this.getCodeContentHeight())
          .scrollable(ScrollDirection.Horizontal)
          .scrollBar(BarState.Off)
        }
      } else {
        if (!this.imageFailed) {
          Image(this.buildMermaidUrl())
            .width('100%')
            .height(this.getDiagramHeight())
            .objectFit(ImageFit.Contain)
            .backgroundColor($r('app.color.surface'))
            .onError(() => {
              this.imageFailed = true;
            })
            .onClick(() => {
              const width: number = this.contentWidthVp > 0 ? Math.round(this.contentWidthVp * 3) : 2000;
              this.onOpenImagePreview([this.buildMermaidUrl(width)], 0);
            })
        } else {
          Column() {
            Text('图表加载失败')
              .fontSize(13)
              .fontColor($r('app.color.on_surface'))
            Text('重试')
              .fontSize(12)
              .fontColor($r('app.color.primary'))
              .margin({ top: 8 })
              .onClick(() => {
                this.imageFailed = false;
                this.retrySeed = this.retrySeed + 1;
              })
          }
          .width('100%')
          .height(this.getDiagramHeight())
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
          .backgroundColor($r('app.color.surface'))
        }
      }
    }
    .width('100%')
    .backgroundColor($r('app.color.surface_variant'))
    .borderRadius(10)
    .clip(true)
    .border({ width: 0.5, color: $r('app.color.divider_light') })
    .margin({ top: this.marginTop })
    .onAreaChange((_: Area, newArea: Area) => {
      this.updateContentWidthVp(newArea.width);
    })
  }
}

@ComponentV2
struct RichDetailsBlock {
  @Param summary: string = '详情';
  @Param contentHtml: string = '';
  @Param post: Post | null = null;
  @Param openByDefault: boolean = false;
  @Param marginTop: number = 0;
  @Param allowPollInteraction: boolean = false;
  @Param enableSelectionQuote: boolean = false;
  @Param enableCopyQuoteSelection: boolean = false;
  @Event onOpenLink: (url: string) => void = () => {
  };
  @Event onOpenImagePreview: (urls: string[], initialIndex: number) => void = () => {
  };
  @Event onQuoteSelection: (selectedText: string, sourceHtml: string) => void = (_: string, _sourceHtml: string) => {
  };
  @Event onCopyQuoteSelection: (selectedText: string, sourceHtml: string) => void = (_: string, _sourceHtml: string) => {
  };
  @Event onLongPressImage: (imageUrl: string, previewUrl: string) => void = () => {
  };
  @Event onPostUpdated: (post: Post) => void = (_: Post) => {
  };

  @Local private isOpen: boolean = false;

  aboutToAppear(): void {
    this.isOpen = this.openByDefault === true;
  }

  build() {
    Column() {
      // Summary（可点击展开/收起）
      Row() {
        SymbolGlyph($r('sys.symbol.chevron_down'))
          .fontSize(16)
          .fontColor([$r('app.color.on_surface_secondary')])
          .rotate({ angle: this.isOpen ? 180 : 0 })
          .margin({ right: 8 })

        Text(this.summary)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.on_surface'))
          .layoutWeight(1)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 10, bottom: 10 })
      .alignItems(VerticalAlign.Center)
      .onClick(() => {
        this.isOpen = !this.isOpen;
      })

      // Content（展开后）
      if (this.isOpen) {
        Column() {
          PostRichContent({
            cookedHtml: this.contentHtml,
            post: this.post,
            dense: true,
            blockGapVp: 8,
            allowPollInteraction: this.allowPollInteraction,
            enableSelectionQuote: this.enableSelectionQuote,
            enableCopyQuoteSelection: this.enableCopyQuoteSelection,
            onOpenLink: (url: string) => {
              this.onOpenLink(url);
            },
            onOpenImagePreview: (urls: string[], initialIndex: number) => {
              this.onOpenImagePreview(urls, initialIndex);
            },
            onQuoteSelection: (selectedText: string, sourceHtml: string) => {
              this.onQuoteSelection(selectedText, sourceHtml);
            },
            onCopyQuoteSelection: (selectedText: string, sourceHtml: string) => {
              this.onCopyQuoteSelection(selectedText, sourceHtml);
            },
            onLongPressImage: (imageUrl: string, previewUrl: string) => {
              this.onLongPressImage(imageUrl, previewUrl);
            },
            onPostUpdated: (post: Post) => {
              this.onPostUpdated(post);
            }
          })
        }
        .width('100%')
        .padding({ left: 12, right: 12, bottom: 12 })
      }
    }
    .width('100%')
    .backgroundColor($r('app.color.surface_variant'))
    .border({ width: 0.5, color: $r('app.color.divider_light') })
    .borderRadius(12)
    .margin({ top: this.marginTop })
  }
}

@ComponentV2
struct RichPollBlock {
  @Param post: Post | null = null;
  @Param pollName: string = '';
  @Param title: string = '';
  @Param allowInteraction: boolean = false;
  @Param marginTop: number = 0;
  @Event onPollUpdated: (post: Post) => void = (_: Post) => {
  };

  @Local private poll: Poll | null = null;
  @Local private userVotes: string[] = [];
  @Local private showResults: boolean = false;
  @Local private showPercentage: boolean = true;
  @Local private isVoting: boolean = false;

  aboutToAppear(): void {
    this.syncFromPost();
  }

  @Monitor('post')
  onPostChange(): void {
    this.syncFromPost();
  }

  @Monitor('pollName')
  onPollNameChange(): void {
    this.syncFromPost();
  }

  private syncFromPost(): void {
    if (this.post === null || this.pollName.trim().length === 0 || this.post.polls === null) {
      this.poll = null;
      this.userVotes = [];
      this.showResults = false;
      return;
    }

    const polls: Poll[] = this.post.polls as Poll[];
    let matched: Poll | null = null;
    for (let i = 0; i < polls.length; i++) {
      if (polls[i].name === this.pollName) {
        matched = polls[i];
        break;
      }
    }
    this.poll = matched;

    const nextVotes: string[] = [];
    if (this.post.pollsVotes !== null && this.post.pollsVotes.has(this.pollName)) {
      const rawVotes: string[] = this.post.pollsVotes.get(this.pollName) as string[];
      for (let i = 0; i < rawVotes.length; i++) {
        nextVotes.push(rawVotes[i]);
      }
    }
    this.userVotes = nextVotes;
    this.showResults = this.shouldShowResults();
  }

  private shouldShowResults(): boolean {
    if (this.poll === null) return false;
    const hasVoted: boolean = this.userVotes.length > 0;
    const isClosed: boolean = this.poll.status === 'closed';
    if (this.poll.results === 'on_close' && !isClosed) {
      return false;
    }
    if (this.poll.results === 'staff_only') {
      return false;
    }
    return hasVoted || isClosed;
  }

  private isMultiple(): boolean {
    return this.poll !== null && this.poll.type === 'multiple';
  }

  private hasVoted(optionId: string): boolean {
    for (let i = 0; i < this.userVotes.length; i++) {
      if (this.userVotes[i] === optionId) return true;
    }
    return false;
  }

  private setUserVotes(votes: string[]): void {
    const next: string[] = [];
    for (let i = 0; i < votes.length; i++) {
      next.push(votes[i]);
    }
    this.userVotes = next;
  }

  private updatePostPoll(updatedPoll: Poll, votes: string[]): void {
    if (this.post === null) return;
    if (this.post.polls === null) {
      this.post.polls = [];
    }

    let replaced: boolean = false;
    const polls: Poll[] = this.post.polls as Poll[];
    for (let i = 0; i < polls.length; i++) {
      if (polls[i].name === updatedPoll.name) {
        polls[i] = updatedPoll;
        replaced = true;
        break;
      }
    }
    if (!replaced) {
      polls.push(updatedPoll);
    }
    this.post.polls = polls;

    if (this.post.pollsVotes === null) {
      this.post.pollsVotes = new Map();
    }
    const voteMap: Map<string, string[]> = this.post.pollsVotes as Map<string, string[]>;
    voteMap.set(updatedPoll.name, votes);
    this.post.pollsVotes = voteMap;
    this.onPollUpdated(this.post);
  }

  private buildOptionText(option: PollOption): string {
    const text: string = stripHtmlKeepLines(option.html).replace(/\n+/g, ' ').trim();
    return text.length > 0 ? text : option.id;
  }

  private getOptionPercentage(option: PollOption): number {
    const voters: number = this.getCurrentPoll().voters;
    return voters > 0 ? (option.votes / voters * 100) : 0;
  }

  private async submitVotes(votes: string[]): Promise<void> {
    if (this.post === null || this.poll === null || this.isVoting || this.post.id <= 0) return;
    if (!this.allowInteraction) {
      ToastService.show('请先登录');
      return;
    }

    this.isVoting = true;
    try {
      const updated: Poll | null = await ApiClient.getInstance().votePoll(this.post.id, this.poll.name, votes);
      if (updated !== null) {
        this.poll = updated;
        this.setUserVotes(votes);
        this.showResults = this.shouldShowResults();
        this.updatePostPoll(updated, votes);
      }
    } catch (err) {
      const message: string = err !== undefined && err !== null ? err.toString() : '';
      ToastService.show(message.length > 0 ? message : '投票失败');
    } finally {
      this.isVoting = false;
    }
  }

  private async toggleOption(optionId: string): Promise<void> {
    if (this.poll === null || this.poll.status === 'closed' || this.isVoting) return;
    if (!this.allowInteraction) {
      ToastService.show('请先登录');
      return;
    }

    if (this.isMultiple()) {
      const nextVotes: string[] = [];
      let exists: boolean = false;
      for (let i = 0; i < this.userVotes.length; i++) {
        if (this.userVotes[i] === optionId) {
          exists = true;
          continue;
        }
        nextVotes.push(this.userVotes[i]);
      }
      if (!exists) {
        nextVotes.push(optionId);
      }
      this.userVotes = nextVotes;
      return;
    }

    await this.submitVotes([optionId]);
  }

  private async submitMultipleVote(): Promise<void> {
    if (this.userVotes.length === 0) {
      ToastService.show('请先选择投票项');
      return;
    }
    await this.submitVotes(this.userVotes);
  }

  private async removeVote(): Promise<void> {
    if (this.post === null || this.poll === null || this.isVoting) return;
    if (!this.allowInteraction) {
      ToastService.show('请先登录');
      return;
    }

    this.isVoting = true;
    try {
      const updated: Poll | null = await ApiClient.getInstance().removeVote(this.post.id, this.poll.name);
      if (updated !== null) {
        this.poll = updated;
        this.userVotes = [];
        this.showResults = this.shouldShowResults();
        this.updatePostPoll(updated, []);
      }
    } catch (err) {
      const message: string = err !== undefined && err !== null ? err.toString() : '';
      ToastService.show(message.length > 0 ? message : '撤销投票失败');
    } finally {
      this.isVoting = false;
    }
  }

  @Builder
  private PollAction(label: string, primary: boolean, danger: boolean, onPress: () => void) {
    Text(label)
      .fontSize(12)
      .fontWeight(FontWeight.Medium)
      .fontColor(
        primary
          ? Color.White
          : (danger ? Color.Red : $r('app.color.on_surface_secondary'))
      )
      .padding({ left: 10, right: 10, top: 6, bottom: 6 })
      .backgroundColor(primary ? $r('app.color.primary') : $r('app.color.surface'))
      .borderRadius(14)
      .border(primary ? { width: 0 } : { width: 0.5, color: $r('app.color.divider_light') })
      .onClick(() => {
        onPress();
      })
  }

  private hasPollData(): boolean {
    return this.poll !== null && (this.poll as Poll).options.length > 0;
  }

  private getCurrentPoll(): Poll {
    return this.poll !== null ? (this.poll as Poll) : new Poll();
  }

  build() {
    Column() {
      if (this.hasPollData()) {
        if (this.title.trim().length > 0) {
          Text(this.title)
            .fontSize(14)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.on_surface'))
            .margin({ bottom: 10 })
        }

        Column() {
          ForEach(this.getCurrentPoll().options, (option: PollOption, index: number) => {
            Column() {
              Row() {
                Text(
                  this.showResults
                    ? (this.hasVoted(option.id) ? '●' : '○')
                    : (this.isMultiple() ? (this.hasVoted(option.id) ? '☑' : '☐') : (this.hasVoted(option.id) ? '◉' : '○'))
                )
                  .fontSize(16)
                  .fontColor(this.hasVoted(option.id) ? $r('app.color.primary') : $r('app.color.on_surface_secondary'))
                  .margin({ right: 10 })

                Text(this.buildOptionText(option))
                  .layoutWeight(1)
                  .fontSize(13)
                  .fontWeight(this.hasVoted(option.id) ? FontWeight.Medium : FontWeight.Regular)
                  .fontColor($r('app.color.on_surface'))

                if (this.showResults) {
                  Text(this.showPercentage ? `${Math.round(this.getOptionPercentage(option))}%` : `${option.votes}`)
                    .fontSize(12)
                    .fontWeight(FontWeight.Medium)
                    .fontColor($r('app.color.primary'))
                }
              }
              .width('100%')
              .alignItems(VerticalAlign.Center)

              if (this.showResults) {
                Progress({ value: this.getOptionPercentage(option), total: 100 })
                  .height(4)
                  .color(this.hasVoted(option.id) ? $r('app.color.primary') : $r('app.color.on_surface_tertiary'))
                  .margin({ top: 8 })
              }
            }
            .width('100%')
            .padding({ left: 12, right: 12, top: 10, bottom: 10 })
            .backgroundColor(this.hasVoted(option.id) ? $r('app.color.badge_background_light') : $r('app.color.surface'))
            .border({
              width: 0.5,
              color: this.hasVoted(option.id) ? $r('app.color.primary') : $r('app.color.divider_light')
            })
            .borderRadius(8)
            .margin({ top: index === 0 ? 0 : 8 })
            .onClick(() => {
              if (!this.showResults || this.isMultiple()) {
                this.toggleOption(option.id);
              }
            })
          }, (option: PollOption) => option.id)
        }

        Row() {
          Text(`${this.getCurrentPoll().voters} 投票人${this.getCurrentPoll().status === 'closed' ? ' • 已关闭' : ''}`)
            .fontSize(12)
            .fontColor($r('app.color.on_surface_secondary'))
          Blank().layoutWeight(1)

          if (this.isMultiple() && !this.showResults && this.userVotes.length > 0 && this.getCurrentPoll().status !== 'closed') {
            this.PollAction('投票', true, false, () => {
              this.submitMultipleVote();
            })
          }

          if (!this.isMultiple() && !this.showResults && this.userVotes.length > 0 && this.getCurrentPoll().status !== 'closed') {
            this.PollAction('撤销', false, true, () => {
              this.removeVote();
            })
          }

          if (this.showResults && this.getCurrentPoll().voters > 0) {
            Blank().width(8)
            this.PollAction(this.showPercentage ? '计数' : '百分比', false, false, () => {
              this.showPercentage = !this.showPercentage;
            })
          }

          if (this.getCurrentPoll().status !== 'closed' && (this.userVotes.length > 0 || this.getCurrentPoll().results === 'always')) {
            Blank().width(8)
            this.PollAction(this.showResults ? '投票' : '查看结果', false, false, () => {
              this.showResults = !this.showResults;
            })
          }
        }
        .width('100%')
        .margin({ top: 12 })
        .alignItems(VerticalAlign.Center)
      }
    }
    .width('100%')
    .padding(this.hasPollData() ? 12 : 0)
    .backgroundColor(this.hasPollData() ? $r('app.color.surface_variant') : Color.Transparent)
    .border(this.hasPollData() ? { width: 0.5, color: $r('app.color.divider_light') } : { width: 0, color: Color.Transparent })
    .borderRadius(10)
    .margin({ top: this.marginTop })
  }
}
