class HtmlSelectionToken {
  text: string = '';
  href: string = '';
  linkClass: string = '';
  bold: boolean = false;
  italic: boolean = false;
  underline: boolean = false;
  strike: boolean = false;
  code: boolean = false;
  sup: boolean = false;
  sub: boolean = false;
  plainStart: number = 0;
  plainEnd: number = 0;

  constructor() {
  }
}

class NormalizedTextResult {
  text: string = '';
  indexMap: number[] = [];

  constructor() {
  }
}

function decodeHtmlEntities(text: string): string {
  let result: string = text !== undefined && text !== null ? text : '';
  result = result.replace(/&nbsp;/g, ' ');
  result = result.replace(/&lt;/g, '<');
  result = result.replace(/&gt;/g, '>');
  result = result.replace(/&amp;/g, '&');
  result = result.replace(/&quot;/g, '"');
  result = result.replace(/&#39;/g, '\'');
  result = result.replace(/&#x27;/g, '\'');

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

function escapeHtml(text: string): string {
  const raw: string = text !== undefined && text !== null ? text : '';
  return raw
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

function extractAttr(tag: string, attr: string): string {
  const re1: RegExp = new RegExp(`${attr}\\s*=\\s*"([^"]*)"`, 'i');
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

function normalizeHref(rawHref: string): string {
  const href: string = rawHref !== undefined && rawHref !== null ? rawHref.trim() : '';
  if (href.length === 0) return '';
  if (href.startsWith('http://') || href.startsWith('https://')) return href;
  if (href.startsWith('//')) return `https:${href}`;
  return href;
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

function stripInlineHtml(html: string): string {
  const raw: string = html !== undefined && html !== null ? html : '';
  if (raw.length === 0) return '';
  let result: string = raw.replace(/<br\s*\/?>/gi, '\n');
  result = result.replace(/<img[^>]*alt\s*=\s*"([^"]*)"[^>]*>/gi, '$1');
  result = result.replace(/<img[^>]*alt\s*=\s*'([^']*)'[^>]*>/gi, '$1');
  result = result.replace(/<[^>]*>/g, '');
  result = decodeHtmlEntities(result);
  result = result.replace(/\r/g, '');
  result = result.replace(/[ \t]+\n/g, '\n');
  result = result.replace(/\n[ \t]+/g, '\n');
  return result;
}

function buildNormalizedText(text: string): NormalizedTextResult {
  const result: NormalizedTextResult = new NormalizedTextResult();
  const raw: string = text !== undefined && text !== null ? text : '';
  let pendingSpace: boolean = false;

  for (let i = 0; i < raw.length; i++) {
    const ch: string = raw.charAt(i);
    const isSpace: boolean = /\s/.test(ch);
    if (isSpace) {
      pendingSpace = result.text.length > 0;
      continue;
    }
    if (pendingSpace) {
      result.text = `${result.text} `;
      result.indexMap.push(i);
      pendingSpace = false;
    }
    result.text = `${result.text}${ch.toLowerCase()}`;
    result.indexMap.push(i);
  }

  return result;
}

function tokenizeHtml(html: string): HtmlSelectionToken[] {
  const raw0: string = html !== undefined && html !== null ? html : '';
  const raw: string = raw0.replace(/\r/g, '');
  const lower: string = raw.toLowerCase();
  const out: HtmlSelectionToken[] = [];
  let buf: string = '';
  let plainOffset: number = 0;

  let boldDepth: number = 0;
  let italicDepth: number = 0;
  let underlineDepth: number = 0;
  let strikeDepth: number = 0;
  let codeDepth: number = 0;
  let supDepth: number = 0;
  let subDepth: number = 0;

  const hrefStack: string[] = [];
  const linkClassStack: string[] = [];

  const currentHref = (): string => hrefStack.length > 0 ? hrefStack[hrefStack.length - 1] : '';
  const currentLinkClass = (): string => linkClassStack.length > 0 ? linkClassStack[linkClassStack.length - 1] : '';

  const pushToken = (text: string): void => {
    if (text.length === 0) return;
    const decoded: string = decodeHtmlEntities(text);
    if (decoded.length === 0) return;

    const token: HtmlSelectionToken = new HtmlSelectionToken();
    token.text = decoded;
    token.href = currentHref();
    token.linkClass = currentLinkClass();
    token.bold = boldDepth > 0;
    token.italic = italicDepth > 0;
    token.underline = underlineDepth > 0;
    token.strike = strikeDepth > 0;
    token.code = codeDepth > 0;
    token.sup = supDepth > 0;
    token.sub = subDepth > 0;
    token.plainStart = plainOffset;
    token.plainEnd = plainOffset + decoded.length;
    plainOffset = token.plainEnd;
    out.push(token);
  };

  const flushBuf = (): void => {
    if (buf.length === 0) return;
    pushToken(buf);
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
    if (tagLower.startsWith('!--')) {
      const endComment: number = raw.indexOf('-->', i);
      if (endComment >= 0) {
        i = endComment + 3;
        continue;
      }
    }

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
        flushBuf();
        const closeStart: number = findMatchingCloseTag(lower, i, 'a');
        if (closeStart > end) {
          const innerHtml: string = raw.substring(end + 1, closeStart);
          const mentionText: string = stripInlineHtml(innerHtml).trim();
          if (mentionText.length > 0) {
            const token: HtmlSelectionToken = new HtmlSelectionToken();
            token.text = mentionText;
            token.href = normalizeHref(extractAttr(fullTag, 'href'));
            token.linkClass = cls;
            token.plainStart = plainOffset;
            token.plainEnd = plainOffset + mentionText.length;
            plainOffset = token.plainEnd;
            out.push(token);
          }
          i = closeStart + '</a>'.length;
          continue;
        }
      }
    }

    flushBuf();

    if (tagName === 'br') {
      pushToken('\n');
      i = end + 1;
      continue;
    }
    if (tagName === 'p') {
      if (isClosing) {
        pushToken('\n');
      }
      i = end + 1;
      continue;
    }
    if (tagName === 'li') {
      if (!isClosing) {
        pushToken('\n• ');
      } else {
        pushToken('\n');
      }
      i = end + 1;
      continue;
    }

    if (tagName === 'strong' || tagName === 'b') {
      boldDepth = isClosing ? Math.max(0, boldDepth - 1) : boldDepth + 1;
      i = end + 1;
      continue;
    }
    if (tagName === 'em' || tagName === 'i') {
      italicDepth = isClosing ? Math.max(0, italicDepth - 1) : italicDepth + 1;
      i = end + 1;
      continue;
    }
    if (tagName === 'u') {
      underlineDepth = isClosing ? Math.max(0, underlineDepth - 1) : underlineDepth + 1;
      i = end + 1;
      continue;
    }
    if (tagName === 's' || tagName === 'del') {
      strikeDepth = isClosing ? Math.max(0, strikeDepth - 1) : strikeDepth + 1;
      i = end + 1;
      continue;
    }
    if (tagName === 'code') {
      codeDepth = isClosing ? Math.max(0, codeDepth - 1) : codeDepth + 1;
      i = end + 1;
      continue;
    }
    if (tagName === 'sup') {
      supDepth = isClosing ? Math.max(0, supDepth - 1) : supDepth + 1;
      i = end + 1;
      continue;
    }
    if (tagName === 'sub') {
      subDepth = isClosing ? Math.max(0, subDepth - 1) : subDepth + 1;
      i = end + 1;
      continue;
    }

    if (tagName === 'a') {
      if (!isClosing) {
        const fullTag: string = `<${tagRaw}>`;
        hrefStack.push(normalizeHref(extractAttr(fullTag, 'href')));
        linkClassStack.push(extractAttr(fullTag, 'class'));
      } else {
        if (hrefStack.length > 0) {
          hrefStack.splice(hrefStack.length - 1, 1);
        }
        if (linkClassStack.length > 0) {
          linkClassStack.splice(linkClassStack.length - 1, 1);
        }
      }
      i = end + 1;
      continue;
    }

    if (tagName === 'img') {
      const fullTag: string = `<${tagRaw}>`;
      const alt: string = extractAttr(fullTag, 'alt');
      if (alt.length > 0) {
        pushToken(alt);
      }
      i = end + 1;
      continue;
    }

    i = end + 1;
  }

  flushBuf();
  return out;
}

function renderTokenHtml(token: HtmlSelectionToken, text: string): string {
  let html: string = escapeHtml(text).replace(/\n/g, '<br>');
  if (token.code) {
    html = `<code>${html}</code>`;
  }
  if (token.bold) {
    html = `<strong>${html}</strong>`;
  }
  if (token.italic) {
    html = `<em>${html}</em>`;
  }
  if (token.underline) {
    html = `<u>${html}</u>`;
  }
  if (token.strike) {
    html = `<s>${html}</s>`;
  }
  if (token.sup) {
    html = `<sup>${html}</sup>`;
  }
  if (token.sub) {
    html = `<sub>${html}</sub>`;
  }
  if (token.href.length > 0) {
    const classAttr: string = token.linkClass.length > 0 ? ` class="${escapeHtml(token.linkClass)}"` : '';
    html = `<a href="${escapeHtml(token.href)}"${classAttr}>${html}</a>`;
  }
  return html;
}

export class HtmlTextMapper {
  static extractHtml(sourceHtml: string, selectedPlainText: string): string | null {
    const html: string = sourceHtml !== undefined && sourceHtml !== null ? sourceHtml : '';
    const selected: string = selectedPlainText !== undefined && selectedPlainText !== null ? selectedPlainText.trim() : '';
    if (html.length === 0 || selected.length === 0) {
      return null;
    }

    const tokens: HtmlSelectionToken[] = tokenizeHtml(html);
    if (tokens.length === 0) {
      return null;
    }

    let fullPlainText: string = '';
    for (let i = 0; i < tokens.length; i++) {
      fullPlainText = `${fullPlainText}${tokens[i].text}`;
    }
    if (fullPlainText.length === 0) {
      return null;
    }

    const normalizedFull: NormalizedTextResult = buildNormalizedText(fullPlainText);
    const normalizedSelected: NormalizedTextResult = buildNormalizedText(selected);
    if (normalizedSelected.text.length === 0) {
      return null;
    }

    const matchStart: number = normalizedFull.text.indexOf(normalizedSelected.text);
    if (matchStart < 0) {
      return null;
    }
    const matchEnd: number = matchStart + normalizedSelected.text.length - 1;
    if (matchEnd < matchStart || matchEnd >= normalizedFull.indexMap.length) {
      return null;
    }

    const originalStart: number = normalizedFull.indexMap[matchStart];
    const originalEndExclusive: number = normalizedFull.indexMap[matchEnd] + 1;
    if (originalEndExclusive <= originalStart) {
      return null;
    }

    let fragment: string = '';
    for (let i = 0; i < tokens.length; i++) {
      const token: HtmlSelectionToken = tokens[i];
      const overlapStart: number = Math.max(originalStart, token.plainStart);
      const overlapEnd: number = Math.min(originalEndExclusive, token.plainEnd);
      if (overlapEnd <= overlapStart) {
        continue;
      }

      const tokenStart: number = overlapStart - token.plainStart;
      const tokenEnd: number = overlapEnd - token.plainStart;
      const piece: string = token.text.substring(tokenStart, tokenEnd);
      fragment = `${fragment}${renderTokenHtml(token, piece)}`;
    }

    const compact: string = fragment.trim();
    return compact.length > 0 ? compact : null;
  }
}
