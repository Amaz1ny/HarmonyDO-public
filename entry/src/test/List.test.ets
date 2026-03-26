import localUnitTest from './LocalUnit.test';
import messageBusErrorUtilsTest from './MessageBusErrorUtils.test';
import topicListFabModeUtilsTest from './TopicListFabModeUtils.test';
import inviteLinksPageUtilsTest from './InviteLinksPageUtils.test';

export default function testsuite() {
  localUnitTest();
  messageBusErrorUtilsTest();
  topicListFabModeUtilsTest();
  inviteLinksPageUtilsTest();
}
