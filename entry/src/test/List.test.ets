import localUnitTest from './LocalUnit.test';
import messageBusErrorUtilsTest from './MessageBusErrorUtils.test';
import topicListFabModeUtilsTest from './TopicListFabModeUtils.test';
import inviteLinksPageUtilsTest from './InviteLinksPageUtils.test';
import openSourceInfoContractTest from './OpenSourceInfoContract.test';
import appLogServiceTest from './AppLogService.test';
import appLogsRoutingTest from './AppLogsRouting.test';
import featureSettingsRoutingTest from './FeatureSettingsRouting.test';
import featureSettingsServiceTest from './FeatureSettingsService.test';

export default function testsuite() {
  localUnitTest();
  messageBusErrorUtilsTest();
  topicListFabModeUtilsTest();
  inviteLinksPageUtilsTest();
  openSourceInfoContractTest();
  appLogServiceTest();
  appLogsRoutingTest();
  featureSettingsRoutingTest();
  featureSettingsServiceTest();
}
