/**
 * 通用布局常量（vp）
 *
 * 说明：这些值用于主页面底部“悬浮胶囊 TabBar”及其避让空间，集中管理避免多处硬编码。
 */

export const FLOATING_TAB_BAR_HEIGHT_VP: number = 56;
export const FLOATING_TAB_BAR_RADIUS_VP: number = 28;
export const FLOATING_TAB_BAR_MARGIN_H_VP: number = 20;
export const FLOATING_TAB_BAR_MARGIN_BOTTOM_VP: number = 10;
export const FLOATING_TAB_BAR_OFFSET_UP_VP: number = 8;

// API 23 HdsTabsFloatingStyle.barWidth 官方分档宽度：使用固定 vp，避免百分比宽度在真机上触发贴边/越界。
export const FLOATING_TAB_BAR_WIDTH_SMALL_VP: number = 280;
export const FLOATING_TAB_BAR_WIDTH_MEDIUM_VP: number = 320;
export const FLOATING_TAB_BAR_WIDTH_LARGE_VP: number = 400;
export const FLOATING_TAB_BAR_OPACITY: number = 0.72;

// 列表/页面底部额外留白：用于确保最后一项不被悬浮 TabBar 覆盖，并保留轻微呼吸感
export const FLOATING_TAB_BAR_CONTENT_EXTRA_PADDING_VP: number = 12;

