import { Post } from './Post';

export class NestedNode {
  post: Post = new Post();
  children: NestedNode[] = [];
  directReplyCount: number = 0;
  totalDescendantCount: number = 0;
  isDeletedPlaceholder: boolean = false;

  constructor() {
  }

  get hasMoreChildren(): boolean {
    return this.directReplyCount > this.children.length;
  }

  static fromJson(json: Record<string, Object>): NestedNode {
    const out: NestedNode = new NestedNode();
    out.post = Post.fromJson(json);

    const childrenVal = json['children'];
    if (childrenVal !== undefined && childrenVal !== null && Array.isArray(childrenVal)) {
      const arr: Object[] = childrenVal as Object[];
      const children: NestedNode[] = [];
      for (let i = 0; i < arr.length; i++) {
        const item: Object = arr[i];
        if (item === null || item === undefined || typeof item !== 'object') {
          continue;
        }
        children.push(NestedNode.fromJson(item as Record<string, Object>));
      }
      out.children = children;
    }

    const directVal = json['direct_reply_count'];
    out.directReplyCount = directVal !== undefined && directVal !== null ? Number(directVal.toString()) : 0;
    if (isNaN(out.directReplyCount) || out.directReplyCount < 0) {
      out.directReplyCount = 0;
    }

    const totalVal = json['total_descendant_count'];
    out.totalDescendantCount = totalVal !== undefined && totalVal !== null ? Number(totalVal.toString()) : 0;
    if (isNaN(out.totalDescendantCount) || out.totalDescendantCount < 0) {
      out.totalDescendantCount = 0;
    }

    const deletedVal = json['deleted_post_placeholder'];
    out.isDeletedPlaceholder = deletedVal !== undefined && deletedVal !== null ? deletedVal as boolean : false;
    return out;
  }
}

export class NestedRootsResponse {
  topicJson: Record<string, Object> | null = null;
  opPost: Post | null = null;
  sort: string = 'old';
  roots: NestedNode[] = [];
  hasMoreRoots: boolean = false;
  page: number = 0;
  pinnedPostNumber: number = 0;

  constructor() {
  }

  static fromJson(json: Record<string, Object>): NestedRootsResponse {
    const out: NestedRootsResponse = new NestedRootsResponse();

    const topicVal = json['topic'];
    if (topicVal !== undefined && topicVal !== null && typeof topicVal === 'object') {
      out.topicJson = topicVal as Record<string, Object>;
    }

    const opVal = json['op_post'];
    if (opVal !== undefined && opVal !== null && typeof opVal === 'object') {
      out.opPost = Post.fromJson(opVal as Record<string, Object>);
    }

    const sortVal = json['sort'];
    out.sort = sortVal !== undefined && sortVal !== null ? sortVal.toString() : 'old';

    const rootsVal = json['roots'];
    if (rootsVal !== undefined && rootsVal !== null && Array.isArray(rootsVal)) {
      const arr: Object[] = rootsVal as Object[];
      const roots: NestedNode[] = [];
      for (let i = 0; i < arr.length; i++) {
        const item: Object = arr[i];
        if (item === null || item === undefined || typeof item !== 'object') {
          continue;
        }
        roots.push(NestedNode.fromJson(item as Record<string, Object>));
      }
      out.roots = roots;
    }

    const hasMoreVal = json['has_more_roots'];
    out.hasMoreRoots = hasMoreVal !== undefined && hasMoreVal !== null ? hasMoreVal as boolean : false;

    const pageVal = json['page'];
    out.page = pageVal !== undefined && pageVal !== null ? Number(pageVal.toString()) : 0;
    if (isNaN(out.page) || out.page < 0) {
      out.page = 0;
    }

    const pinnedVal = json['pinned_post_number'];
    out.pinnedPostNumber = pinnedVal !== undefined && pinnedVal !== null ? Number(pinnedVal.toString()) : 0;
    if (isNaN(out.pinnedPostNumber) || out.pinnedPostNumber < 0) {
      out.pinnedPostNumber = 0;
    }

    return out;
  }
}

export class NestedChildrenResponse {
  children: NestedNode[] = [];
  hasMore: boolean = false;
  page: number = 0;

  constructor() {
  }

  static fromJson(json: Record<string, Object>): NestedChildrenResponse {
    const out: NestedChildrenResponse = new NestedChildrenResponse();

    const childrenVal = json['children'];
    if (childrenVal !== undefined && childrenVal !== null && Array.isArray(childrenVal)) {
      const arr: Object[] = childrenVal as Object[];
      const children: NestedNode[] = [];
      for (let i = 0; i < arr.length; i++) {
        const item: Object = arr[i];
        if (item === null || item === undefined || typeof item !== 'object') {
          continue;
        }
        children.push(NestedNode.fromJson(item as Record<string, Object>));
      }
      out.children = children;
    }

    const hasMoreVal = json['has_more'];
    out.hasMore = hasMoreVal !== undefined && hasMoreVal !== null ? hasMoreVal as boolean : false;

    const pageVal = json['page'];
    out.page = pageVal !== undefined && pageVal !== null ? Number(pageVal.toString()) : 0;
    if (isNaN(out.page) || out.page < 0) {
      out.page = 0;
    }

    return out;
  }
}
