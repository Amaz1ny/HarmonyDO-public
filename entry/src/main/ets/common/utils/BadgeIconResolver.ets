import { Badge } from '../../models/Badge';
import { UrlUtils } from './UrlUtils';

function normalizeBadgeIconName(raw: string | null): string {
  if (raw === null || raw === undefined) {
    return '';
  }
  const source: string = raw.toString().trim().toLowerCase();
  if (source.length === 0) {
    return '';
  }
  const tokens: string[] = source.split(/\s+/);
  let last: string = '';
  for (let i = 0; i < tokens.length; i++) {
    let token: string = tokens[i].trim();
    if (token.length === 0) {
      continue;
    }
    if (
      token === 'fa-solid' || token === 'fa-regular' || token === 'fa-brands' || token === 'fa-light'
      || token === 'fa-thin' || token === 'fa-duotone' || token === 'fas' || token === 'far'
      || token === 'fab' || token === 'fal' || token === 'fat' || token === 'fad' || token === 'fa'
    ) {
      continue;
    }
    if (token.startsWith('fa-')) {
      token = token.substring(3);
    }
    last = token;
  }
  return last;
}

export class BadgeIconResolver {
  static getResolvedImageUrl(badge: Badge): string {
    if (badge.imageUrl === null || (badge.imageUrl as string).trim().length === 0) {
      return '';
    }
    return UrlUtils.resolveUrl(badge.imageUrl as string);
  }

  static getBadgeSymbol(badge: Badge): Resource {
    const source: string = `${badge.name} ${badge.description} ${badge.icon !== null ? badge.icon as string : ''}`.toLowerCase();
    const iconName: string = normalizeBadgeIconName(badge.icon);

    if (
      source.indexOf('表情') >= 0 || source.indexOf('emoji') >= 0 || source.indexOf('smile') >= 0
      || source.indexOf('grin') >= 0 || source.indexOf('laugh') >= 0 || iconName.indexOf('smile') >= 0
      || iconName.indexOf('grin') >= 0
    ) {
      return $r('sys.symbol.face_smiling');
    }
    if (
      source.indexOf('欢迎') >= 0 || source.indexOf('点赞') >= 0 || source.indexOf('赞') >= 0
      || source.indexOf('heart') >= 0 || source.indexOf('love') >= 0 || iconName.indexOf('heart') >= 0
      || iconName.indexOf('thumb') >= 0 || source.indexOf('like') >= 0
    ) {
      return $r('sys.symbol.heart_fill');
    }
    if (
      source.indexOf('基本用户') >= 0 || source.indexOf('用户') >= 0 || source.indexOf('user') >= 0
      || iconName.indexOf('user') >= 0 || iconName.indexOf('person') >= 0
    ) {
      return $r('sys.symbol.person_fill');
    }
    if (
      source.indexOf('话题') >= 0 || source.indexOf('帖子') >= 0 || source.indexOf('topic') >= 0
      || source.indexOf('post') >= 0 || source.indexOf('reply') >= 0 || source.indexOf('discussion') >= 0
      || iconName.indexOf('comment') >= 0 || iconName.indexOf('message') >= 0 || iconName.indexOf('image') >= 0
    ) {
      return $r('sys.symbol.doc_text');
    }
    if (source.indexOf('徽章') >= 0 || source.indexOf('badge') >= 0 || iconName.indexOf('award') >= 0) {
      return $r('sys.symbol.medal');
    }
    return $r('sys.symbol.star');
  }
}
