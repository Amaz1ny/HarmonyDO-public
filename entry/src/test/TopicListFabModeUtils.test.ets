import { describe, it, expect } from '@ohos/hypium';
import { resolveTopicListFabRefreshModeByScroll } from '../main/ets/common/utils/TopicListFabModeUtils';

export default function topicListFabModeUtilsTest() {
  describe('topicListFabModeUtilsTest', () => {
    it('switches to refresh mode when scrolling toward top with inner list movement', 0, () => {
      const nextMode = resolveTopicListFabRefreshModeByScroll(false, -12, -6);
      expect(nextMode).assertEqual(true);
    });

    it('switches back to create mode when scrolling deeper into list', 0, () => {
      const nextMode = resolveTopicListFabRefreshModeByScroll(true, 14, 14);
      expect(nextMode).assertEqual(false);
    });

    it('keeps create mode when only header expands without inner list movement', 0, () => {
      const nextMode = resolveTopicListFabRefreshModeByScroll(false, -10, 0);
      expect(nextMode).assertEqual(false);
    });

    it('keeps current mode when scroll offset is near zero', 0, () => {
      const nextMode = resolveTopicListFabRefreshModeByScroll(true, 0, 0);
      expect(nextMode).assertEqual(true);
    });
  });
}
