import { hilog } from '@kit.PerformanceAnalysisKit';
import { PreferencesUtil } from './PreferencesUtil';

const TAG: string = 'TopicListPreferences';

export class TopicListPreferences {
  private static readonly KEY_FILTER: string = 'topic_sort_filter';
  private static readonly KEY_ORDER: string = 'topic_sort_order';
  private static readonly KEY_ASCENDING: string = 'topic_sort_ascending';
  private static readonly KEY_PINNED_CATEGORY_IDS: string = 'pinned_category_ids';
  private static readonly KEY_SELECTED_TAGS: string = 'topic_selected_tags';

  private static normalizeTags(tags: string[]): string[] {
    const out: string[] = [];
    const seen: Map<string, boolean> = new Map();

    for (let i = 0; i < tags.length; i++) {
      const raw: string = tags[i];
      const t: string = raw.trim();
      if (t.length === 0) continue;
      if (seen.has(t)) continue;
      seen.set(t, true);
      out.push(t);
    }
    return out;
  }

  static async loadFilter(defaultValue: string = '最新'): Promise<string> {
    await PreferencesUtil.ensureInit();
    return await PreferencesUtil.getString(TopicListPreferences.KEY_FILTER, defaultValue);
  }

  static async saveFilter(value: string): Promise<void> {
    await PreferencesUtil.ensureInit();
    await PreferencesUtil.putString(TopicListPreferences.KEY_FILTER, value);
  }

  static async loadOrder(defaultValue: string = '默认'): Promise<string> {
    await PreferencesUtil.ensureInit();
    return await PreferencesUtil.getString(TopicListPreferences.KEY_ORDER, defaultValue);
  }

  static async saveOrder(value: string): Promise<void> {
    await PreferencesUtil.ensureInit();
    await PreferencesUtil.putString(TopicListPreferences.KEY_ORDER, value);
  }

  static async loadAscending(defaultValue: boolean = false): Promise<boolean> {
    await PreferencesUtil.ensureInit();
    return await PreferencesUtil.getBoolean(TopicListPreferences.KEY_ASCENDING, defaultValue);
  }

  static async saveAscending(value: boolean): Promise<void> {
    await PreferencesUtil.ensureInit();
    await PreferencesUtil.putBoolean(TopicListPreferences.KEY_ASCENDING, value);
  }

  static async loadPinnedCategoryIds(): Promise<number[]> {
    await PreferencesUtil.ensureInit();
    const raw: string = await PreferencesUtil.getString(TopicListPreferences.KEY_PINNED_CATEGORY_IDS, '[]');
    try {
      const parsed: Object = JSON.parse(raw) as Object;
      if (!Array.isArray(parsed)) {
        return [];
      }

      const ids: number[] = [];
      const arr: Object[] = parsed as Object[];
      for (let i = 0; i < arr.length; i++) {
        const value: Object = arr[i];
        const id: number = Number(value.toString());
        if (!isNaN(id) && ids.indexOf(id) < 0) {
          ids.push(id);
        }
      }
      return ids;
    } catch (err) {
      hilog.error(0x0000, TAG, 'Load pinned categories failed: %{public}s', JSON.stringify(err));
      return [];
    }
  }

  static async savePinnedCategoryIds(ids: number[]): Promise<void> {
    await PreferencesUtil.ensureInit();
    await PreferencesUtil.putString(TopicListPreferences.KEY_PINNED_CATEGORY_IDS, JSON.stringify(ids));
  }

  static async loadSelectedTags(): Promise<string[]> {
    await PreferencesUtil.ensureInit();
    const raw: string = await PreferencesUtil.getString(TopicListPreferences.KEY_SELECTED_TAGS, '[]');
    const trimmed: string = raw.trim();
    if (trimmed.length === 0) return [];

    try {
      const parsed: Object = JSON.parse(trimmed) as Object;
      if (!Array.isArray(parsed)) {
        return [];
      }

      const arr: Object[] = parsed as Object[];
      const tags: string[] = [];
      for (let i = 0; i < arr.length; i++) {
        const v: Object = arr[i];
        if (v === null || v === undefined) continue;
        const s: string = v.toString();
        if (s.trim().length === 0) continue;
        tags.push(s);
      }

      return TopicListPreferences.normalizeTags(tags);
    } catch (err) {
      hilog.error(0x0000, TAG, 'Load selectedTags failed: %{public}s', JSON.stringify(err));
      return [];
    }
  }

  static async saveSelectedTags(tags: string[]): Promise<void> {
    await PreferencesUtil.ensureInit();
    const normalized: string[] = TopicListPreferences.normalizeTags(tags);
    await PreferencesUtil.putString(TopicListPreferences.KEY_SELECTED_TAGS, JSON.stringify(normalized));
  }
}
