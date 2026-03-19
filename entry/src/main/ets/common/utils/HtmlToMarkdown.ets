class HtmlTagMatch {
  found: boolean = false;
  attrs: string = '';
  inner: string = '';

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
  result = result.replace(/&#x2F;/g, '/');

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

function escapeMarkdownCode(text: string): string {
  const raw: string = text !== undefined && text !== null ? text : '';
  return raw.replace(/`/g, '\\`');
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

function replaceUntilStable(raw: string, replacer: (input: string) => string): string {
  let prev: string = raw;
  while (true) {
    const next: string = replacer(prev);
    if (next === prev) {
      return next;
    }
    prev = next;
  }
}

function normalizeWhitespace(text: string): string {
  let result: string = text !== undefined && text !== null ? text : '';
  result = result.replace(/\r/g, '');
  result = result.replace(/\u00A0/g, ' ');
  result = result.replace(/[ \t]+\n/g, '\n');
  result = result.replace(/\n[ \t]+/g, '\n');
  result = result.replace(/[ \t]{2,}/g, ' ');
  result = result.replace(/\n{3,}/g, '\n\n');
  return result.trim();
}

function trimLeftSpaces(text: string): string {
  return (text !== undefined && text !== null ? text : '').replace(/^\s+/, '');
}

function trimRightSpaces(text: string): string {
  return (text !== undefined && text !== null ? text : '').replace(/\s+$/, '');
}

function matchWholeTag(html: string, tagName: string): HtmlTagMatch {
  const out: HtmlTagMatch = new HtmlTagMatch();
  const raw: string = html !== undefined && html !== null ? html.trim() : '';
  if (raw.length === 0) return out;
  const re: RegExp = new RegExp(`^<${tagName}\\b([^>]*)>([\\s\\S]*)<\\/${tagName}>$`, 'i');
  const match: RegExpMatchArray | null = raw.match(re);
  if (match === null) {
    return out;
  }
  out.found = true;
  out.attrs = match.length > 1 && match[1] !== undefined ? match[1] : '';
  out.inner = match.length > 2 && match[2] !== undefined ? match[2] : '';
  return out;
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

function extractDirectTagBlocks(innerHtml: string, tagName: string): string[] {
  const html: string = innerHtml !== undefined && innerHtml !== null ? innerHtml : '';
  const lower: string = html.toLowerCase();
  const out: string[] = [];
  let idx: number = 0;

  while (idx < html.length) {
    const next: number = lower.indexOf(`<${tagName}`, idx);
    if (next < 0) {
      break;
    }
    const openEnd: number = html.indexOf('>', next);
    if (openEnd < 0) {
      break;
    }
    const closeStart: number = findMatchingCloseTag(lower, next, tagName);
    if (closeStart <= openEnd) {
      break;
    }
    out.push(html.substring(next, closeStart + (`</${tagName}>`).length));
    idx = closeStart + (`</${tagName}>`).length;
  }

  return out;
}

function hasCssClass(attrs: string, className: string): boolean {
  const tag: string = `<x${attrs !== undefined && attrs !== null ? attrs : ''}>`;
  const classAttr: string = extractAttr(tag, 'class').toLowerCase();
  if (classAttr.length === 0) return false;
  const normalized: string = className !== undefined && className !== null ? className.trim().toLowerCase() : '';
  if (normalized.length === 0) return false;
  const re: RegExp = new RegExp(`(^|\\s)${normalized}(\\s|$)`, 'i');
  return re.test(classAttr);
}

function hasCssClassLike(attrs: string, keyword: string): boolean {
  const tag: string = `<x${attrs !== undefined && attrs !== null ? attrs : ''}>`;
  const classAttr: string = extractAttr(tag, 'class').toLowerCase();
  const normalized: string = keyword !== undefined && keyword !== null ? keyword.trim().toLowerCase() : '';
  if (classAttr.length === 0 || normalized.length === 0) return false;
  return classAttr.indexOf(normalized) >= 0;
}

function extractCodeLanguage(attrs: string): string {
  const fullTag: string = `<code${attrs !== undefined && attrs !== null ? attrs : ''}>`;
  const classAttr: string = extractAttr(fullTag, 'class').trim();
  if (classAttr.length === 0) return '';
  const parts: string[] = classAttr.split(/\s+/);
  for (let i: number = 0; i < parts.length; i++) {
    const item: string = parts[i].trim();
    const lower: string = item.toLowerCase();
    if (lower.startsWith('language-') && lower.length > 'language-'.length) {
      return lower.substring('language-'.length);
    }
    if (lower.startsWith('lang-') && lower.length > 'lang-'.length) {
      return lower.substring('lang-'.length);
    }
  }
  return '';
}

function stripHtmlTags(rawHtml: string): string {
  let result: string = rawHtml !== undefined && rawHtml !== null ? rawHtml : '';
  result = result.replace(/<br\s*\/?>/gi, '\n');
  result = result.replace(/<[^>]*>/g, '');
  result = decodeHtmlEntities(result);
  return normalizeWhitespace(result);
}

function buildQuoteLines(text: string): string {
  const normalized: string = normalizeWhitespace(text);
  if (normalized.length === 0) return '';
  const lines: string[] = normalized.split('\n');
  let out: string = '';
  for (let i = 0; i < lines.length; i++) {
    const line: string = trimRightSpaces(lines[i]);
    out = `${out}> ${line.length > 0 ? line : ''}`;
    if (i < lines.length - 1) {
      out = `${out}\n`;
    }
  }
  return out;
}

function convertInlineCode(codeText: string): string {
  const decoded: string = decodeHtmlEntities(codeText).replace(/\r/g, '').replace(/\n+/g, ' ').trim();
  if (decoded.length === 0) return '';
  return `\`${escapeMarkdownCode(decoded)}\``;
}

function convertFencedCode(codeText: string, language: string): string {
  const decoded: string = decodeHtmlEntities(codeText).replace(/\r/g, '');
  const normalized: string = decoded.replace(/^\n+/, '').replace(/\n+$/, '');
  const lang: string = language !== undefined && language !== null ? language.trim() : '';
  if (lang.length > 0) {
    return `\n\n\`\`\`${lang}\n${normalized}\n\`\`\`\n\n`;
  }
  return `\n\n\`\`\`\n${normalized}\n\`\`\`\n\n`;
}

function convertDetailsBlock(attrs: string, innerHtml: string): string {
  const summaryMatch: RegExpMatchArray | null = innerHtml.match(/<summary\b[^>]*>([\s\S]*?)<\/summary>/i);
  let summary: string = '详情';
  let bodyHtml: string = innerHtml;
  if (summaryMatch !== null && summaryMatch.length > 1) {
    const convertedSummary: string = HtmlToMarkdown.convert(summaryMatch[1]).replace(/\n+/g, ' ').trim();
    if (convertedSummary.length > 0) {
      summary = convertedSummary;
    }
    bodyHtml = innerHtml.replace(/<summary\b[^>]*>[\s\S]*?<\/summary>/i, '');
  }
  const bodyMarkdown: string = HtmlToMarkdown.convert(bodyHtml).trim();
  const safeSummary: string = summary.replace(/"/g, '\'');
  if (bodyMarkdown.length === 0) {
    return `[details="${safeSummary}"]\n[/details]`;
  }
  return `\n[details="${safeSummary}"]\n${bodyMarkdown}\n[/details]\n`;
}

function convertAsideQuote(attrs: string, innerHtml: string): string {
  const blockquoteMatch: HtmlTagMatch = matchWholeTag(innerHtml.trim(), 'blockquote');
  const quoteBodyHtml: string = blockquoteMatch.found ? blockquoteMatch.inner : innerHtml;
  let text: string = HtmlToMarkdown.convert(quoteBodyHtml).trim();
  text = text.replace(/^>\s?/gm, '').trim();
  if (text.length === 0) return '';

  const openTag: string = `<aside${attrs}>`;
  const username: string = extractAttr(openTag, 'data-username').trim();
  const post: string = extractAttr(openTag, 'data-post').trim();
  const topic: string = extractAttr(openTag, 'data-topic').trim();
  const prefix: string = username.length > 0 && post.length > 0 && topic.length > 0
    ? `[quote="${username}, post:${post}, topic:${topic}"]`
    : '[quote]';
  return `\n${prefix}\n${text}\n[/quote]\n`;
}

function convertListBlock(tagName: string, attrs: string, innerHtml: string): string {
  const itemBlocks: string[] = extractDirectTagBlocks(innerHtml, 'li');
  if (itemBlocks.length === 0) {
    return HtmlToMarkdown.convert(innerHtml);
  }

  let orderedIndex: number = 1;
  if (tagName.toLowerCase() === 'ol') {
    const startRaw: string = extractAttr(`<${tagName}${attrs}>`, 'start').trim();
    const parsedStart: number = parseInt(startRaw, 10);
    if (!isNaN(parsedStart) && parsedStart > 0) {
      orderedIndex = parsedStart;
    }
  }

  let out: string = '\n';
  for (let i = 0; i < itemBlocks.length; i++) {
    const liMatch: HtmlTagMatch = matchWholeTag(itemBlocks[i].trim(), 'li');
    const liInner: string = liMatch.found ? liMatch.inner : itemBlocks[i];
    let itemMarkdown: string = HtmlToMarkdown.convert(liInner).trim();
    if (itemMarkdown.length === 0) {
      continue;
    }
    itemMarkdown = itemMarkdown.replace(/\n{3,}/g, '\n\n');
    const lines: string[] = itemMarkdown.split('\n');
    const marker: string = tagName.toLowerCase() === 'ol' ? `${orderedIndex}. ` : '* ';
    out = `${out}${marker}${trimLeftSpaces(lines[0])}`;
    for (let j = 1; j < lines.length; j++) {
      out = `${out}\n\t${lines[j]}`;
    }
    if (i < itemBlocks.length - 1) {
      out = `${out}\n`;
    }
    if (tagName.toLowerCase() === 'ol') {
      orderedIndex = orderedIndex + 1;
    }
  }
  return `${out}\n`;
}

function convertTableBlock(innerHtml: string): string {
  const rowBlocks: string[] = [];
  const sectionTags: string[] = ['thead', 'tbody', 'tfoot'];
  for (let i = 0; i < sectionTags.length; i++) {
    const sectionBlocks: string[] = extractDirectTagBlocks(innerHtml, sectionTags[i]);
    for (let j = 0; j < sectionBlocks.length; j++) {
      const sectionMatch: HtmlTagMatch = matchWholeTag(sectionBlocks[j].trim(), sectionTags[i]);
      const sectionInner: string = sectionMatch.found ? sectionMatch.inner : sectionBlocks[j];
      const sectionRows: string[] = extractDirectTagBlocks(sectionInner, 'tr');
      for (let k = 0; k < sectionRows.length; k++) {
        rowBlocks.push(sectionRows[k]);
      }
    }
  }
  const directRows: string[] = extractDirectTagBlocks(innerHtml, 'tr');
  for (let i = 0; i < directRows.length; i++) {
    rowBlocks.push(directRows[i]);
  }

  if (rowBlocks.length === 0) {
    return HtmlToMarkdown.convert(innerHtml);
  }

  const rows: string[][] = [];
  let maxCols: number = 0;
  for (let i = 0; i < rowBlocks.length; i++) {
    const rowMatch: HtmlTagMatch = matchWholeTag(rowBlocks[i].trim(), 'tr');
    const rowInner: string = rowMatch.found ? rowMatch.inner : rowBlocks[i];
    const cells: string[] = [];
    const cellRegex: RegExp = /<(td|th)\b[^>]*>([\s\S]*?)<\/\1>/gi;
    let cellMatch: RegExpExecArray | null = null;
    while (true) {
      cellMatch = cellRegex.exec(rowInner);
      if (cellMatch === null) break;
      let cellMarkdown: string = HtmlToMarkdown.convert(cellMatch[2]).trim();
      cellMarkdown = cellMarkdown.replace(/\n+/g, ' ').trim();
      cellMarkdown = cellMarkdown.replace(/\|/g, '\\|');
      if (cellMarkdown.length === 0) {
        cellMarkdown = ' ';
      }
      cells.push(cellMarkdown);
    }
    if (cells.length > 0) {
      if (cells.length > maxCols) {
        maxCols = cells.length;
      }
      rows.push(cells);
    }
  }

  if (rows.length === 0 || maxCols <= 0) {
    return HtmlToMarkdown.convert(stripHtmlTags(innerHtml));
  }

  for (let i = 0; i < rows.length; i++) {
    while (rows[i].length < maxCols) {
      rows[i].push(' ');
    }
  }

  let out: string = '\n';
  out = `${out}| ${rows[0].join(' | ')} |\n|`;
  for (let i = 0; i < maxCols; i++) {
    out = `${out} --- |`;
  }
  for (let i = 1; i < rows.length; i++) {
    out = `${out}\n| ${rows[i].join(' | ')} |`;
  }
  return `${out}\n`;
}

function convertHeading(level: number, innerHtml: string): string {
  const headingLevel: number = Math.max(1, Math.min(6, level));
  const text: string = HtmlToMarkdown.convert(innerHtml).replace(/\n+/g, ' ').trim();
  if (text.length === 0) return '';
  let prefix: string = '';
  for (let i = 0; i < headingLevel; i++) {
    prefix = `${prefix}#`;
  }
  return `\n\n${prefix} ${text}\n\n`;
}

function convertPreBlock(preAttrs: string, innerHtml: string): string {
  const codeMatch: HtmlTagMatch = matchWholeTag(innerHtml.trim(), 'code');
  if (codeMatch.found) {
    return convertFencedCode(codeMatch.inner, extractCodeLanguage(codeMatch.attrs));
  }
  const lang: string = extractCodeLanguage(preAttrs);
  return convertFencedCode(innerHtml, lang);
}

function convertBlockMath(innerHtml: string): string {
  const latex: string = normalizeWhitespace(stripHtmlTags(innerHtml));
  if (latex.length === 0) return '';
  return `\n$$\n${latex}\n$$\n`;
}

function convertInlineMath(innerHtml: string): string {
  const latex: string = normalizeWhitespace(stripHtmlTags(innerHtml));
  if (latex.length === 0) return '';
  return `\$${latex}\$`;
}

function convertSpanBlock(attrs: string, innerHtml: string): string {
  if (hasCssClassLike(attrs, 'click-count') || hasCssClassLike(attrs, 'badge-notification') || hasCssClassLike(attrs, 'badge badge-notification clicks')) {
    return '';
  }
  if (hasCssClassLike(attrs, 'mathjax-math')) {
    return '';
  }
  if (hasCssClassLike(attrs, 'math') && extractAttr(`<span${attrs}>`, 'data-applied-mathjax').length > 0) {
    return convertInlineMath(innerHtml);
  }
  if (hasCssClassLike(attrs, 'spoiler')) {
    const content: string = HtmlToMarkdown.convert(innerHtml).trim();
    if (content.length === 0) return '';
    return `[spoiler]${content}[/spoiler]`;
  }
  return HtmlToMarkdown.convert(innerHtml);
}

function convertDivBlock(attrs: string, innerHtml: string): string {
  if (hasCssClassLike(attrs, 'mathjax-math')) {
    return '';
  }
  if (hasCssClassLike(attrs, 'math') && extractAttr(`<div${attrs}>`, 'data-applied-mathjax').length > 0) {
    return convertBlockMath(innerHtml);
  }
  if (hasCssClassLike(attrs, 'spoiler')) {
    const content: string = HtmlToMarkdown.convert(innerHtml).trim();
    if (content.length === 0) return '';
    return `\n[spoiler]\n${content}\n[/spoiler]\n`;
  }
  return HtmlToMarkdown.convert(innerHtml);
}

function convertImageTag(attrs: string): string {
  const tag: string = `<img${attrs}>`;
  const src: string = decodeHtmlEntities(extractAttr(tag, 'src')).trim();
  const alt: string = decodeHtmlEntities(extractAttr(tag, 'alt')).trim();
  const title: string = decodeHtmlEntities(extractAttr(tag, 'title')).trim();
  const classAttr: string = extractAttr(tag, 'class').toLowerCase();
  if (classAttr.indexOf('emoji') >= 0 || classAttr.indexOf('user-status') >= 0) {
    return alt.length > 0 ? alt : title;
  }
  if (src.length === 0) {
    return alt.length > 0 ? alt : title;
  }
  if (title.length > 0) {
    return `![${alt}](${src} "${title}")`;
  }
  return `![${alt}](${src})`;
}

function convertAnchorTag(attrs: string, innerHtml: string): string {
  const tag: string = `<a${attrs}>`;
  const href: string = decodeHtmlEntities(extractAttr(tag, 'href')).trim();
  const classAttr: string = extractAttr(tag, 'class').toLowerCase();
  let label: string = HtmlToMarkdown.convert(innerHtml).trim();
  if (classAttr.indexOf('mention') >= 0) {
    return label;
  }
  if (classAttr.indexOf('hashtag') >= 0) {
    return label;
  }
  if (label.length === 0) {
    label = href;
  }
  if (href.length === 0 || label === href) {
    return label;
  }
  return `[${label}](${href})`;
}

function convertCompositeOnce(input: string): string {
  let next: string = input;

  next = next.replace(/<body[^>]*>/gi, '');
  next = next.replace(/<\/body>/gi, '');
  next = next.replace(/<!--[\s\S]*?-->/g, '');
  next = next.replace(/<head[\s\S]*?<\/head>/gi, '');

  next = next.replace(/<hr\b[^>]*\/?>/gi, '\n---\n');
  next = next.replace(/<br\s*\/?>/gi, '\n');

  next = next.replace(/<aside\b([^>]*)>([\s\S]*?)<\/aside>/gi, (_: string, attrs: string, inner: string): string => {
    if (!hasCssClassLike(attrs, 'quote')) {
      return HtmlToMarkdown.convert(inner);
    }
    return convertAsideQuote(attrs, inner);
  });
  next = next.replace(/<blockquote\b[^>]*>([\s\S]*?)<\/blockquote>/gi, (_: string, inner: string): string => {
    const quote: string = buildQuoteLines(HtmlToMarkdown.convert(inner));
    return quote.length > 0 ? `\n${quote}\n` : '';
  });
  next = next.replace(/<details\b([^>]*)>([\s\S]*?)<\/details>/gi, (_: string, attrs: string, inner: string): string => {
    return convertDetailsBlock(attrs, inner);
  });
  next = next.replace(/<(ol|ul)\b([^>]*)>([\s\S]*?)<\/\1>/gi, (_: string, tagName: string, attrs: string, inner: string): string => {
    return convertListBlock(tagName, attrs, inner);
  });
  next = next.replace(/<table\b[^>]*>([\s\S]*?)<\/table>/gi, (_: string, inner: string): string => {
    return convertTableBlock(inner);
  });
  next = next.replace(/<pre\b([^>]*)>([\s\S]*?)<\/pre>/gi, (_: string, attrs: string, inner: string): string => {
    return convertPreBlock(attrs, inner);
  });
  next = next.replace(/<h([1-6])\b[^>]*>([\s\S]*?)<\/h\1>/gi, (_: string, level: string, inner: string): string => {
    const parsedLevel: number = parseInt(level, 10);
    return convertHeading(isNaN(parsedLevel) ? 1 : parsedLevel, inner);
  });
  next = next.replace(/<div\b([^>]*)>([\s\S]*?)<\/div>/gi, (_: string, attrs: string, inner: string): string => {
    return convertDivBlock(attrs, inner);
  });
  next = next.replace(/<p\b[^>]*>([\s\S]*?)<\/p>/gi, (_: string, inner: string): string => {
    const content: string = HtmlToMarkdown.convert(inner).trim();
    return content.length > 0 ? `\n\n${content}\n\n` : '';
  });
  next = next.replace(/<(strong|b)\b[^>]*>([\s\S]*?)<\/\1>/gi, (_: string, _tag: string, inner: string): string => {
    const content: string = HtmlToMarkdown.convert(inner).trim();
    return content.length > 0 ? `**${content}**` : '';
  });
  next = next.replace(/<(em|i)\b[^>]*>([\s\S]*?)<\/\1>/gi, (_: string, _tag: string, inner: string): string => {
    const content: string = HtmlToMarkdown.convert(inner).trim();
    return content.length > 0 ? `*${content}*` : '';
  });
  next = next.replace(/<(s|del|strike)\b[^>]*>([\s\S]*?)<\/\1>/gi, (_: string, _tag: string, inner: string): string => {
    const content: string = HtmlToMarkdown.convert(inner).trim();
    return content.length > 0 ? `~~${content}~~` : '';
  });
  next = next.replace(/<u\b[^>]*>([\s\S]*?)<\/u>/gi, (_: string, inner: string): string => {
    const content: string = HtmlToMarkdown.convert(inner).trim();
    return content.length > 0 ? `<u>${content}</u>` : '';
  });
  next = next.replace(/<code\b([^>]*)>([\s\S]*?)<\/code>/gi, (_: string, _attrs: string, inner: string): string => {
    return convertInlineCode(inner);
  });
  next = next.replace(/<a\b([^>]*)>([\s\S]*?)<\/a>/gi, (_: string, attrs: string, inner: string): string => {
    return convertAnchorTag(attrs, inner);
  });
  next = next.replace(/<img([^>]*)\/?>/gi, (_: string, attrs: string): string => {
    return convertImageTag(attrs);
  });
  next = next.replace(/<span\b([^>]*)>([\s\S]*?)<\/span>/gi, (_: string, attrs: string, inner: string): string => {
    return convertSpanBlock(attrs, inner);
  });
  next = next.replace(/<sup\b[^>]*>([\s\S]*?)<\/sup>/gi, (_: string, inner: string): string => {
    return HtmlToMarkdown.convert(inner);
  });
  next = next.replace(/<sub\b[^>]*>([\s\S]*?)<\/sub>/gi, (_: string, inner: string): string => {
    return HtmlToMarkdown.convert(inner);
  });

  return next;
}

export class HtmlToMarkdown {
  static convert(html: string): string {
    let result: string = html !== undefined && html !== null ? html : '';
    if (result.trim().length === 0) {
      return '';
    }

    result = result.replace(/\r/g, '');
    result = result.replace(/\u00A0/g, ' ');

    const asideMatch: HtmlTagMatch = matchWholeTag(result, 'aside');
    if (asideMatch.found && hasCssClassLike(asideMatch.attrs, 'quote')) {
      return normalizeWhitespace(convertAsideQuote(asideMatch.attrs, asideMatch.inner));
    }

    const blockquoteMatch: HtmlTagMatch = matchWholeTag(result, 'blockquote');
    if (blockquoteMatch.found) {
      return normalizeWhitespace(buildQuoteLines(HtmlToMarkdown.convert(blockquoteMatch.inner)));
    }

    for (let level: number = 1; level <= 6; level++) {
      const headingMatch: HtmlTagMatch = matchWholeTag(result, `h${level}`);
      if (headingMatch.found) {
        return normalizeWhitespace(convertHeading(level, headingMatch.inner));
      }
    }

    const detailsMatch: HtmlTagMatch = matchWholeTag(result, 'details');
    if (detailsMatch.found) {
      return normalizeWhitespace(convertDetailsBlock(detailsMatch.attrs, detailsMatch.inner));
    }

    const olMatch: HtmlTagMatch = matchWholeTag(result, 'ol');
    if (olMatch.found) {
      return normalizeWhitespace(convertListBlock('ol', olMatch.attrs, olMatch.inner));
    }
    const ulMatch: HtmlTagMatch = matchWholeTag(result, 'ul');
    if (ulMatch.found) {
      return normalizeWhitespace(convertListBlock('ul', ulMatch.attrs, ulMatch.inner));
    }

    const tableMatch: HtmlTagMatch = matchWholeTag(result, 'table');
    if (tableMatch.found) {
      return normalizeWhitespace(convertTableBlock(tableMatch.inner));
    }

    const preMatch: HtmlTagMatch = matchWholeTag(result, 'pre');
    if (preMatch.found) {
      return trimRightSpaces(convertPreBlock(preMatch.attrs, preMatch.inner));
    }

    result = replaceUntilStable(result, (input: string): string => {
      return convertCompositeOnce(input);
    });

    result = result.replace(/<[^>]*>/g, '');
    result = decodeHtmlEntities(result);
    return normalizeWhitespace(result);
  }
}
