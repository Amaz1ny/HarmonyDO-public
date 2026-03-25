/**
 * 分类数据模型
 */
export class Category {
  id: number = 0;
  name: string = '';
  color: string = '000000';
  textColor: string = 'FFFFFF';
  slug: string = '';
  description: string | null = null;
  parentCategoryId: number | null = null;
  uploadedLogo: string | null = null;
  readRestricted: boolean = false;
  icon: string | null = null;
  permission: number | null = null;
  notificationLevel: number | null = null;

  constructor() {
  }

  /**
   * 是否允许在此分类创建话题
   */
  get canCreateTopic(): boolean {
    return this.permission !== null && this.permission <= 1;
  }

  /**
   * 获取颜色值（带 # 前缀）
   */
  get colorValue(): string {
    return `#${this.color}`;
  }

  /**
   * 获取文字颜色值（带 # 前缀）
   */
  get textColorValue(): string {
    return `#${this.textColor}`;
  }

  /**
   * 从 JSON 解析
   */
  static fromJson(json: Record<string, Object>): Category {
    const category = new Category();

    const idVal = json['id'];
    category.id = idVal !== undefined && idVal !== null ? Number(idVal.toString()) : 0;

    const nameVal = json['name'];
    category.name = nameVal !== undefined && nameVal !== null ? nameVal as string : '';

    const colorVal = json['color'];
    category.color = colorVal !== undefined && colorVal !== null ? colorVal as string : '000000';

    const textColorVal = json['text_color'];
    category.textColor = textColorVal !== undefined && textColorVal !== null ? textColorVal as string : 'FFFFFF';

    const slugVal = json['slug'];
    category.slug = slugVal !== undefined && slugVal !== null ? slugVal as string : '';

    const descVal = json['description'];
    category.description = descVal !== undefined && descVal !== null ? descVal as string : null;

    const parentVal = json['parent_category_id'];
    category.parentCategoryId = parentVal !== undefined && parentVal !== null
      ? Number(parentVal.toString()) : null;

    // uploaded_logo: { url: string }
    const uploadedLogoVal = json['uploaded_logo'];
    if (uploadedLogoVal !== undefined && uploadedLogoVal !== null) {
      if (typeof uploadedLogoVal === 'string') {
        category.uploadedLogo = uploadedLogoVal as string;
      } else {
        const uploadedLogoObj: Record<string, Object> = uploadedLogoVal as Record<string, Object>;
        const urlVal = uploadedLogoObj['url'];
        category.uploadedLogo = urlVal !== undefined && urlVal !== null ? urlVal as string : null;
      }
    }

    const iconVal = json['icon'];
    category.icon = iconVal !== undefined && iconVal !== null ? iconVal as string : null;

    const readVal = json['read_restricted'];
    category.readRestricted = readVal !== undefined && readVal !== null ? readVal as boolean : false;

    const permVal = json['permission'];
    category.permission = permVal !== undefined && permVal !== null ? permVal as number : null;

    const notifVal = json['notification_level'];
    category.notificationLevel = notifVal !== undefined && notifVal !== null ? notifVal as number : null;

    return category;
  }
}

/**
 * 站点信息响应
 */
export class SiteResponse {
  static readonly DEFAULT_MIN_POST_LENGTH: number = 20;
  static readonly DEFAULT_MIN_FIRST_POST_LENGTH: number = 20;
  static readonly DEFAULT_MIN_TOPIC_TITLE_LENGTH: number = 15;

  categories: Category[] = [];
  minPostLength: number = SiteResponse.DEFAULT_MIN_POST_LENGTH;
  minFirstPostLength: number = SiteResponse.DEFAULT_MIN_FIRST_POST_LENGTH;
  minTopicTitleLength: number = SiteResponse.DEFAULT_MIN_TOPIC_TITLE_LENGTH;

  constructor() {
  }

  getReplyMinLength(): number {
    return SiteResponse.normalizeMinLength(this.minPostLength, SiteResponse.DEFAULT_MIN_POST_LENGTH);
  }

  getTopicBodyMinLength(): number {
    const fallback: number = this.getReplyMinLength();
    return SiteResponse.normalizeMinLength(this.minFirstPostLength, fallback);
  }

  getTopicTitleMinLength(): number {
    return SiteResponse.normalizeMinLength(this.minTopicTitleLength, SiteResponse.DEFAULT_MIN_TOPIC_TITLE_LENGTH);
  }

  private static normalizeMinLength(value: number, fallback: number): number {
    if (isNaN(value) || value <= 0) {
      return fallback;
    }
    return Math.floor(value);
  }

  private static parseSettingNumber(value: Object | null, fallback: number): number {
    if (value === undefined || value === null) {
      return fallback;
    }
    if (typeof value === 'number') {
      return SiteResponse.normalizeMinLength(value as number, fallback);
    }
    if (typeof value === 'string') {
      const parsed: number = Number((value as string).trim());
      return SiteResponse.normalizeMinLength(parsed, fallback);
    }
    if (typeof value === 'object') {
      const obj: Record<string, Object> = value as Record<string, Object>;
      const currentVal = obj['value'];
      if (currentVal !== undefined && currentVal !== null) {
        return SiteResponse.parseSettingNumber(currentVal, fallback);
      }
      const defaultVal = obj['default'];
      if (defaultVal !== undefined && defaultVal !== null) {
        return SiteResponse.parseSettingNumber(defaultVal, fallback);
      }
    }
    return fallback;
  }

  private static readSettingNumber(candidates: Record<string, Object>[], key: string, fallback: number): number {
    for (let i: number = 0; i < candidates.length; i++) {
      const rawValue = candidates[i][key];
      if (rawValue === undefined || rawValue === null) {
        continue;
      }
      return SiteResponse.parseSettingNumber(rawValue, fallback);
    }
    return fallback;
  }

  static fromJson(json: Record<string, Object>): SiteResponse {
    const response = new SiteResponse();
    const categoriesVal = json['categories'];
    if (categoriesVal !== undefined && categoriesVal !== null) {
      const categoriesArray = categoriesVal as Object[];
      const parsed: Category[] = [];
      for (let i = 0; i < categoriesArray.length; i++) {
        const catJson = categoriesArray[i] as Record<string, Object>;
        parsed.push(Category.fromJson(catJson));
      }
      response.categories = parsed;
    }

    const settingCandidates: Record<string, Object>[] = [];
    const clientSettingsVal = json['client_settings'];
    if (clientSettingsVal !== undefined && clientSettingsVal !== null && typeof clientSettingsVal === 'object') {
      settingCandidates.push(clientSettingsVal as Record<string, Object>);
    }
    const siteSettingsVal = json['site_settings'];
    if (siteSettingsVal !== undefined && siteSettingsVal !== null && typeof siteSettingsVal === 'object') {
      settingCandidates.push(siteSettingsVal as Record<string, Object>);
    }
    const siteSettingsCamelVal = json['siteSettings'];
    if (siteSettingsCamelVal !== undefined && siteSettingsCamelVal !== null && typeof siteSettingsCamelVal === 'object') {
      settingCandidates.push(siteSettingsCamelVal as Record<string, Object>);
    }

    response.minPostLength = SiteResponse.readSettingNumber(
      settingCandidates,
      'min_post_length',
      SiteResponse.DEFAULT_MIN_POST_LENGTH
    );
    response.minFirstPostLength = SiteResponse.readSettingNumber(
      settingCandidates,
      'min_first_post_length',
      response.getReplyMinLength()
    );
    response.minTopicTitleLength = SiteResponse.readSettingNumber(
      settingCandidates,
      'min_topic_title_length',
      SiteResponse.DEFAULT_MIN_TOPIC_TITLE_LENGTH
    );
    return response;
  }
}
