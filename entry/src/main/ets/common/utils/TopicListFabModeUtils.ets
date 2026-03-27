export function resolveTopicListFabRefreshModeByScroll(
  currentRefreshMode: boolean,
  offset: number,
  remain: number
): boolean {
  // 对齐 FluxDO：FAB 模式由滚动方向直接驱动。
  // - 朝顶部方向滚动（offset < 0 且真实列表继续回滚）=> 切到刷新模式
  // - 深入列表方向滚动（offset > 0）=> 恢复创建模式
  // - 其余场景保持当前状态，避免把下拉刷新/顶部过拉和 FAB 切换耦合
  if (offset < -0.01 && remain < -0.01) {
    return true;
  }

  if (offset > 0.01) {
    return false;
  }

  return currentRefreshMode;
}
