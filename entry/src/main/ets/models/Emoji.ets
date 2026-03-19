/**
 * 表情模型
 */
export class Emoji {
  name: string = '';
  url: string = '';
  group: string = '';
  searchAliases: string[] = [];

  constructor() {
  }

  static fromJson(json: Record<string, Object>): Emoji {
    const emoji = new Emoji();

    const nameVal = json['name'];
    emoji.name = nameVal !== undefined && nameVal !== null ? nameVal as string : '';

    const urlVal = json['url'];
    emoji.url = urlVal !== undefined && urlVal !== null ? urlVal as string : '';

    const groupVal = json['group'];
    emoji.group = groupVal !== undefined && groupVal !== null ? groupVal as string : '';

    const aliasesVal = json['search_aliases'];
    if (aliasesVal !== undefined && aliasesVal !== null) {
      const aliasArray = aliasesVal as Object[];
      const parsed: string[] = [];
      for (let i = 0; i < aliasArray.length; i++) {
        parsed.push(aliasArray[i] as string);
      }
      emoji.searchAliases = parsed;
    }

    return emoji;
  }
}
