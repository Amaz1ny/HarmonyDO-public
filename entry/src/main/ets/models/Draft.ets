import { TimeUtils } from '../common/utils/TimeUtils';
import { UrlUtils } from '../common/utils/UrlUtils';

/**
 * 草稿内容
 */
export class DraftData {
  reply: string | null = null;
  title: string | null = null;
  categoryId: number | null = null;
  tags: string[] | null = null;
  replyToPostNumber: number | null = null;
  action: string | null = null;
  archetypeId: string | null = null;
  recipients: string[] | null = null;

  constructor() {
  }

  static fromJson(json: Record<string, Object>): DraftData {
    const out: DraftData = new DraftData();
    const replyVal = json['reply'];
    out.reply = replyVal !== undefined && replyVal !== null ? replyVal.toString() : null;
    const titleVal = json['title'];
    out.title = titleVal !== undefined && titleVal !== null ? titleVal.toString() : null;
    const categoryIdVal = json['categoryId'];
    out.categoryId = categoryIdVal !== undefined && categoryIdVal !== null ? Number(categoryIdVal.toString()) : null;
    const tagsVal = json['tags'];
    if (tagsVal !== undefined && tagsVal !== null && Array.isArray(tagsVal)) {
      const arr: Object[] = tagsVal as Object[];
      const tags: string[] = [];
      for (let i = 0; i < arr.length; i++) {
        const item: Object = arr[i];
        if (item === null || item === undefined) continue;
        const text: string = item.toString().trim();
        if (text.length > 0) tags.push(text);
      }
      out.tags = tags;
    }
    const replyToVal = json['replyToPostNumber'];
    out.replyToPostNumber = replyToVal !== undefined && replyToVal !== null ? Number(replyToVal.toString()) : null;
    const actionVal = json['action'];
    out.action = actionVal !== undefined && actionVal !== null ? actionVal.toString() : null;
    const archetypeVal = json['archetypeId'];
    out.archetypeId = archetypeVal !== undefined && archetypeVal !== null ? archetypeVal.toString() : null;
    const recipientsVal = json['recipients'];
    if (recipientsVal !== undefined && recipientsVal !== null && Array.isArray(recipientsVal)) {
      const arr: Object[] = recipientsVal as Object[];
      const recipients: string[] = [];
      for (let i = 0; i < arr.length; i++) {
        const item: Object = arr[i];
        if (item === null || item === undefined) continue;
        const text: string = item.toString().trim();
        if (text.length > 0) recipients.push(text);
      }
      out.recipients = recipients;
    }
    return out;
  }

  toJsonString(): string {
    const json: Record<string, Object> = {};
    if (this.reply !== null && (this.reply as string).length > 0) {
      json['reply'] = this.reply as string;
    }
    if (this.title !== null && (this.title as string).length > 0) {
      json['title'] = this.title as string;
    }
    if (this.categoryId !== null) {
      json['categoryId'] = this.categoryId as number;
    }
    if (this.tags !== null && (this.tags as string[]).length > 0) {
      json['tags'] = this.tags as string[];
    }
    if (this.replyToPostNumber !== null && (this.replyToPostNumber as number) > 0) {
      json['replyToPostNumber'] = this.replyToPostNumber as number;
    }
    if (this.action !== null && (this.action as string).length > 0) {
      json['action'] = this.action as string;
    }
    if (this.archetypeId !== null && (this.archetypeId as string).length > 0) {
      json['archetypeId'] = this.archetypeId as string;
    }
    if (this.recipients !== null && (this.recipients as string[]).length > 0) {
      json['recipients'] = this.recipients as string[];
    }
    return JSON.stringify(json);
  }
}

/**
 * 草稿
 */
export class Draft {
  static readonly newTopicKey: string = 'new_topic';
  static readonly newPrivateMessageKey: string = 'new_private_message';

  draftKey: string = '';
  data: DraftData = new DraftData();
  sequence: number = 0;
  title: string | null = null;
  excerpt: string | null = null;
  updatedAt: Date | null = null;
  username: string | null = null;
  avatarTemplate: string | null = null;
  topicId: number | null = null;

  constructor() {
  }

  static fromJson(json: Record<string, Object>): Draft {
    const out: Draft = new Draft();
    const keyVal = json['draft_key'];
    out.draftKey = keyVal !== undefined && keyVal !== null ? keyVal.toString() : '';
    const seqVal = json['draft_sequence'];
    if (seqVal !== undefined && seqVal !== null) {
      out.sequence = Number(seqVal.toString());
    } else {
      const seqVal2 = json['sequence'];
      out.sequence = seqVal2 !== undefined && seqVal2 !== null ? Number(seqVal2.toString()) : 0;
    }

    const dataVal = json['data'];
    if (dataVal !== undefined && dataVal !== null) {
      if (typeof dataVal === 'string') {
        try {
          const parsed: Object = JSON.parse(dataVal.toString()) as Object;
          if (parsed !== null && parsed !== undefined && typeof parsed === 'object') {
            out.data = DraftData.fromJson(parsed as Record<string, Object>);
          }
        } catch (_) {
        }
      } else if (typeof dataVal === 'object') {
        out.data = DraftData.fromJson(dataVal as Record<string, Object>);
      }
    }

    const titleVal = json['title'];
    out.title = titleVal !== undefined && titleVal !== null ? titleVal.toString() : null;

    const excerptVal = json['excerpt'];
    out.excerpt = excerptVal !== undefined && excerptVal !== null ? excerptVal.toString() : null;

    const updatedAtVal = json['updated_at'];
    if (updatedAtVal !== undefined && updatedAtVal !== null) {
      out.updatedAt = TimeUtils.parseUtcTime(updatedAtVal.toString());
    } else {
      const createdAtVal = json['created_at'];
      out.updatedAt = createdAtVal !== undefined && createdAtVal !== null
        ? TimeUtils.parseUtcTime(createdAtVal.toString()) : null;
    }

    const usernameVal = json['username'];
    out.username = usernameVal !== undefined && usernameVal !== null ? usernameVal.toString() : null;

    const avatarVal = json['avatar_template'];
    out.avatarTemplate = avatarVal !== undefined && avatarVal !== null ? avatarVal.toString() : null;

    const topicIdVal = json['topic_id'];
    if (topicIdVal !== undefined && topicIdVal !== null) {
      out.topicId = Number(topicIdVal.toString());
    } else if (out.draftKey.startsWith('topic_')) {
      const replySuffixIndex: number = out.draftKey.indexOf('_post_');
      const rawTopicId: string = replySuffixIndex >= 0
        ? out.draftKey.substring(6, replySuffixIndex)
        : out.draftKey.substring(6);
      const parsedTopicId: number = Number(rawTopicId);
      out.topicId = isNaN(parsedTopicId) ? null : parsedTopicId;
    }

    return out;
  }

  get hasContent(): boolean {
    const reply: string = this.data.reply !== null ? (this.data.reply as string).trim() : '';
    const title: string = this.data.title !== null ? (this.data.title as string).trim() : '';
    return reply.length > 0 || title.length > 0;
  }

  get displayTitle(): string {
    if (this.title !== null && (this.title as string).trim().length > 0) {
      return (this.title as string).trim();
    }
    if (this.data.title !== null && (this.data.title as string).trim().length > 0) {
      return (this.data.title as string).trim();
    }
    if (this.draftKey.startsWith('topic_')) {
      const topicId: number | null = this.topicId;
      return topicId !== null ? `话题 #${topicId}` : '话题回复草稿';
    }
    if (this.draftKey === Draft.newPrivateMessageKey) {
      return '新的私信';
    }
    if (this.draftKey === Draft.newTopicKey) {
      return '新的话题';
    }
    return '无标题草稿';
  }

  get isPostReply(): boolean {
    return this.draftKey.indexOf('_post_') >= 0;
  }

  get replyToPostNumberFromKey(): number | null {
    if (!this.isPostReply) {
      return null;
    }
    const start: number = this.draftKey.lastIndexOf('_post_');
    if (start < 0) {
      return null;
    }
    const raw: string = this.draftKey.substring(start + 6);
    const parsed: number = Number(raw);
    return isNaN(parsed) ? null : parsed;
  }

  getAvatarUrl(size: number = 96): string {
    if (this.avatarTemplate === null || (this.avatarTemplate as string).trim().length === 0) {
      return '';
    }
    return UrlUtils.resolveUrl((this.avatarTemplate as string).replace('{size}', size.toString()));
  }

  static topicReplyKey(topicId: number): string {
    return `topic_${topicId}`;
  }

  static postReplyKey(topicId: number, postNumber: number): string {
    return `topic_${topicId}_post_${postNumber}`;
  }

  static replyKey(topicId: number, replyToPostNumber: number = 0): string {
    if (replyToPostNumber > 0) {
      return Draft.postReplyKey(topicId, replyToPostNumber);
    }
    return Draft.topicReplyKey(topicId);
  }
}

export class DraftListResponse {
  drafts: Draft[] = [];
  hasMore: boolean = false;

  constructor() {
  }

  static fromJson(json: Record<string, Object>): DraftListResponse {
    const response = new DraftListResponse();

    const draftsVal = json['drafts'];
    if (draftsVal !== undefined && draftsVal !== null && Array.isArray(draftsVal)) {
      const arr: Object[] = draftsVal as Object[];
      const list: Draft[] = [];
      for (let i = 0; i < arr.length; i++) {
        list.push(Draft.fromJson(arr[i] as Record<string, Object>));
      }
      response.drafts = list;
    }

    const hasMoreVal = json['has_more'];
    response.hasMore = hasMoreVal !== undefined && hasMoreVal !== null ? hasMoreVal as boolean : false;

    return response;
  }
}
