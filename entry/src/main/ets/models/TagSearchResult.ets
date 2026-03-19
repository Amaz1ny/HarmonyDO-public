/**
 * 标签搜索结果（对应 Discourse: /tags/filter/search）
 */

export class TagInfo {
  name: string = '';
  text: string = '';
  count: number = 0;

  constructor() {
  }

  static fromJson(json: Record<string, Object>): TagInfo {
    const t: TagInfo = new TagInfo();
    const nameVal = json['name'];
    t.name = nameVal !== undefined && nameVal !== null ? nameVal.toString() : '';
    const textVal = json['text'];
    t.text = textVal !== undefined && textVal !== null ? textVal.toString() : t.name;
    const countVal = json['count'];
    const parsed: number = countVal !== undefined && countVal !== null ? Number(countVal.toString()) : 0;
    t.count = isNaN(parsed) ? 0 : parsed;
    return t;
  }
}

export class RequiredTagGroup {
  name: string = '';
  minCount: number = 1;

  constructor() {
  }

  static fromJson(json: Record<string, Object>): RequiredTagGroup {
    const g: RequiredTagGroup = new RequiredTagGroup();
    const nameVal = json['name'];
    g.name = nameVal !== undefined && nameVal !== null ? nameVal.toString() : '';
    const minVal = json['min_count'];
    const parsed: number = minVal !== undefined && minVal !== null ? Number(minVal.toString()) : 1;
    g.minCount = isNaN(parsed) ? 1 : parsed;
    return g;
  }
}

export class TagSearchResult {
  results: TagInfo[] = [];
  requiredTagGroup: RequiredTagGroup | null = null;

  constructor() {
  }

  static fromJson(json: Record<string, Object>): TagSearchResult {
    const r: TagSearchResult = new TagSearchResult();
    const resultsVal = json['results'];
    if (resultsVal !== undefined && resultsVal !== null && Array.isArray(resultsVal)) {
      const arr: Object[] = resultsVal as Object[];
      const list: TagInfo[] = [];
      for (let i = 0; i < arr.length; i++) {
        const item: Object = arr[i];
        if (item === null || item === undefined || typeof item !== 'object') continue;
        list.push(TagInfo.fromJson(item as Record<string, Object>));
      }
      r.results = list;
    }

    const groupVal = json['required_tag_group'];
    if (groupVal !== undefined && groupVal !== null && typeof groupVal === 'object' && !Array.isArray(groupVal)) {
      r.requiredTagGroup = RequiredTagGroup.fromJson(groupVal as Record<string, Object>);
    }
    return r;
  }
}
