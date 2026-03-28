import { describe, it, expect } from '@ohos/hypium';
import { RouterManager, RouteConstants } from '../main/ets/common/utils/RouterManager';

class FakePathStack {
  public lastName: string = '';

  pushPath(arg: { name: string; param?: Object }): void {
    this.lastName = arg.name;
  }

  pop(): void {
  }

  replacePath(_: { name: string; param?: Object }): void {
  }

  clear(): void {
  }
}

export default function featureSettingsRoutingTest() {
  describe('featureSettingsRoutingTest', () => {
    it('has feature settings route constant and helper', 0, () => {
      expect(RouteConstants.PAGE_FEATURE_SETTINGS).assertEqual('FeatureSettings');

      const stack = new FakePathStack() as unknown as NavPathStack;
      RouterManager.init(stack);
      RouterManager.pushFeatureSettings();

      expect((stack as unknown as FakePathStack).lastName).assertEqual('FeatureSettings');
    });
  });
}
