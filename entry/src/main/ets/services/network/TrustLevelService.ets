import { AppLogStore } from '../storage/AppLogStore';
import { SimpleHttpClient } from './SimpleHttpClient';

const TAG_TRUST: string = 'TrustLevelService';
const TRUST_URL: string = 'https://connect.linux.do/';

export class TrustLevelRingData {
  label: string = '';
  current: number = 0;
  max: number = 0;
  isMet: boolean = false;
}

export class TrustLevelBarData {
  label: string = '';
  current: string = '';
  target: string = '';
  progress: number = 0;
  isMet: boolean = false;
}

export class TrustLevelQuotaData {
  label: string = '';
  value: string = '';
  usedSlots: number = 0;
  totalSlots: number = 5;
  isMet: boolean = false;
}

export class TrustLevelVetoData {
  label: string = '';
  desc: string = '';
  value: string = '';
  isMet: boolean = false;
}

export class TrustLevelData {
  title: string = '';
  badgeText: string = '';
  badgeType: string = 'warning';
  subtitle: string = '';
  rings: TrustLevelRingData[] = [];
  bars: TrustLevelBarData[] = [];
  quotas: TrustLevelQuotaData[] = [];
  vetos: TrustLevelVetoData[] = [];
  footerHint: string = '';
  statusText: string = '';
  isStatusMet: boolean = false;
}

export class TrustLevelService {
  static async fetchData(): Promise<TrustLevelData> {
    AppLogStore.getInstance().info(TAG_TRUST, 'fetch trust requirements');
    const response = await SimpleHttpClient.get(TRUST_URL, 'text/html,application/xhtml+xml,*/*', null, TRUST_URL);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw new Error(`HTTP ${response.statusCode}`);
    }
    const data: TrustLevelData = TrustLevelService.parseHtml(response.body);
    AppLogStore.getInstance().info(TAG_TRUST, `trust requirements loaded title=${data.title}`);
    return data;
  }

  private static parseHtml(html: string): TrustLevelData {
    const documentHtml: string = html !== undefined && html !== null ? html : '';
    const cardHtml: string = TrustLevelService.extractClassBlock(documentHtml, 'card');
    if (cardHtml.length === 0) {
      throw new Error('未找到信任要求卡片');
    }

    const data: TrustLevelData = new TrustLevelData();
    data.title = TrustLevelService.extractTextByClass(cardHtml, 'card-title');
    data.subtitle = TrustLevelService.extractTextByClass(cardHtml, 'card-subtitle');
    data.badgeText = TrustLevelService.extractTextByClass(cardHtml, 'badge');
    const badgeBlock: string = TrustLevelService.extractClassBlock(cardHtml, 'badge');
    if (badgeBlock.indexOf('badge-success') >= 0) {
      data.badgeType = 'success';
    } else if (badgeBlock.indexOf('badge-danger') >= 0) {
      data.badgeType = 'danger';
    } else {
      data.badgeType = 'warning';
    }

    const ringBlocks: string[] = TrustLevelService.extractBlocksByClass(cardHtml, 'tl3-ring');
    for (let i: number = 0; i < ringBlocks.length; i++) {
      const block: string = ringBlocks[i];
      const ring: TrustLevelRingData = new TrustLevelRingData();
      ring.label = TrustLevelService.extractTextByClass(block, 'tl3-ring-label');
      const circleBlock: string = TrustLevelService.extractClassBlock(block, 'tl3-ring-circle');
      ring.current = TrustLevelService.extractStyleNumber(circleBlock, '--val');
      ring.max = TrustLevelService.extractStyleNumber(circleBlock, '--max');
      ring.isMet = circleBlock.indexOf('met') >= 0;
      data.rings.push(ring);
    }

    const barBlocks: string[] = TrustLevelService.extractBlocksByClass(cardHtml, 'tl3-bar-item');
    for (let i: number = 0; i < barBlocks.length; i++) {
      const block: string = barBlocks[i];
      const bar: TrustLevelBarData = new TrustLevelBarData();
      const fillBlock: string = TrustLevelService.extractClassBlock(block, 'tl3-bar-fill');
      const current: number = TrustLevelService.extractStyleNumber(fillBlock, '--val');
      const max: number = TrustLevelService.extractStyleNumber(fillBlock, '--max');
      bar.label = TrustLevelService.extractTextByClass(block, 'tl3-bar-label');
      bar.current = TrustLevelService.extractTextByClass(block, 'tl3-bar-nums');
      bar.target = max > 0 ? max.toString() : '';
      bar.progress = max > 0 ? Math.max(0, Math.min(1, current / max)) : 0;
      bar.isMet = fillBlock.indexOf('met') >= 0;
      data.bars.push(bar);
    }

    const quotaBlocks: string[] = TrustLevelService.extractBlocksByClass(cardHtml, 'tl3-quota-card');
    for (let i: number = 0; i < quotaBlocks.length; i++) {
      const block: string = quotaBlocks[i];
      const quota: TrustLevelQuotaData = new TrustLevelQuotaData();
      quota.label = TrustLevelService.extractTextByClass(block, 'tl3-quota-label');
      quota.value = TrustLevelService.extractTextByClass(block, 'tl3-quota-nums');
      quota.usedSlots = TrustLevelService.countOccurrences(block, 'tl3-slot used');
      quota.isMet = block.indexOf('unmet') < 0;
      data.quotas.push(quota);
    }

    const vetoBlocks: string[] = TrustLevelService.extractBlocksByClass(cardHtml, 'tl3-veto-item');
    for (let i: number = 0; i < vetoBlocks.length; i++) {
      const block: string = vetoBlocks[i];
      const veto: TrustLevelVetoData = new TrustLevelVetoData();
      const unmet: boolean = block.indexOf('unmet') >= 0;
      const face: string = unmet
        ? TrustLevelService.extractClassBlock(block, 'tl3-veto-back')
        : TrustLevelService.extractClassBlock(block, 'tl3-veto-front');
      veto.label = TrustLevelService.extractTextByClass(face, 'tl3-veto-label');
      veto.desc = TrustLevelService.extractTextByClass(face, 'tl3-veto-desc');
      veto.value = TrustLevelService.extractTextByClass(face, 'tl3-veto-value');
      veto.isMet = !unmet;
      data.vetos.push(veto);
    }

    data.footerHint = TrustLevelService.extractTextByClass(cardHtml, 'text-hint');
    const statusMetBlock: string = TrustLevelService.extractClassBlock(cardHtml, 'status-met');
    const statusUnmetBlock: string = TrustLevelService.extractClassBlock(cardHtml, 'status-unmet');
    if (statusMetBlock.length > 0) {
      data.statusText = TrustLevelService.stripHtml(statusMetBlock);
      data.isStatusMet = true;
    } else if (statusUnmetBlock.length > 0) {
      data.statusText = TrustLevelService.stripHtml(statusUnmetBlock);
      data.isStatusMet = false;
    }
    return data;
  }

  private static extractBlocksByClass(html: string, className: string): string[] {
    const blocks: string[] = [];
    let cursor: number = 0;
    while (cursor < html.length) {
      const start: number = TrustLevelService.findClassTagStart(html, className, cursor);
      if (start < 0) {
        break;
      }
      const block: string = TrustLevelService.extractBalancedDiv(html, start);
      if (block.length === 0) {
        break;
      }
      blocks.push(block);
      cursor = start + block.length;
    }
    return blocks;
  }

  private static extractClassBlock(html: string, className: string): string {
    const start: number = TrustLevelService.findClassTagStart(html, className, 0);
    if (start < 0) {
      return '';
    }
    return TrustLevelService.extractBalancedDiv(html, start);
  }

  private static findClassTagStart(html: string, className: string, offset: number): number {
    const regex: RegExp = new RegExp(`<div[^>]*class=["'][^"']*${className}[^"']*["'][^>]*>`, 'ig');
    regex.lastIndex = offset;
    const match: RegExpExecArray | null = regex.exec(html);
    return match !== null ? match.index : -1;
  }

  private static extractBalancedDiv(html: string, start: number): string {
    let depth: number = 0;
    let cursor: number = start;
    while (cursor < html.length) {
      const nextOpen: number = html.indexOf('<div', cursor);
      const nextClose: number = html.indexOf('</div>', cursor);
      if (nextClose < 0) {
        return html.substring(start);
      }
      if (nextOpen >= 0 && nextOpen < nextClose) {
        depth += 1;
        cursor = nextOpen + 4;
        continue;
      }
      depth -= 1;
      cursor = nextClose + 6;
      if (depth === 0) {
        return html.substring(start, cursor);
      }
    }
    return '';
  }

  private static extractTextByClass(html: string, className: string): string {
    const regex: RegExp = new RegExp(`<[^>]*class=["'][^"']*${className}[^"']*["'][^>]*>([\\s\\S]*?)<\\/[^>]+>`, 'i');
    const match: RegExpExecArray | null = regex.exec(html);
    if (match === null) {
      return '';
    }
    return TrustLevelService.stripHtml(match[1]);
  }

  private static extractStyleNumber(html: string, propertyName: string): number {
    const styleMatch: RegExpExecArray | null = /style=["']([^"']+)["']/i.exec(html);
    if (styleMatch === null) {
      return 0;
    }
    const regex: RegExp = new RegExp(`${propertyName}:\\s*([0-9.]+)`, 'i');
    const match: RegExpExecArray | null = regex.exec(styleMatch[1]);
    if (match === null) {
      return 0;
    }
    return Number(match[1]);
  }

  private static stripHtml(html: string): string {
    const next: string = html
      .replace(/<br\s*\/?>/ig, '\n')
      .replace(/<\/p>/ig, '\n')
      .replace(/<[^>]+>/g, ' ')
      .replace(/&nbsp;/ig, ' ')
      .replace(/&amp;/ig, '&')
      .replace(/&lt;/ig, '<')
      .replace(/&gt;/ig, '>')
      .replace(/\s+/g, ' ');
    return next.trim();
  }

  private static countOccurrences(text: string, pattern: string): number {
    const regex: RegExp = new RegExp(pattern, 'ig');
    const matches: RegExpMatchArray | null = text.match(regex);
    return matches !== null ? matches.length : 0;
  }
}
