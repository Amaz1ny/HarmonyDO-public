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

export default function appLogsRoutingTest() {
  describe('appLogsRoutingTest', () => {
    it('has app logs route constant and helper', 0, () => {
      expect(RouteConstants.PAGE_APP_LOGS).assertEqual('AppLogs');

      const stack = new FakePathStack() as unknown as NavPathStack;
      RouterManager.init(stack);
      RouterManager.pushAppLogs();
      expect((stack as unknown as FakePathStack).lastName).assertEqual('AppLogs');
    });
  });
}
