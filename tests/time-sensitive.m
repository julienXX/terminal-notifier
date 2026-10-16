// Exercise real notification content without a GUI session or notification
// permission. No request is posted and no signing identity is needed.
#import "../Terminal Notifier/AppDelegate.m"
#include <assert.h>

int main(void)
{
  @autoreleasepool {
    assert(!TNTimeSensitiveRequested(@[@"terminal-notifier", @"-message", @"ordinary"]));
    assert(TNTimeSensitiveRequested(@[@"terminal-notifier", @"-timeSensitive"]));
    assert(TNTimeSensitiveRequested(@[@"terminal-notifier", @"-ignoreDnD"]));

    if (@available(macOS 12.0, *)) {
      UNMutableNotificationContent *ordinary = [UNMutableNotificationContent new];
      assert(TNApplyTimeSensitive(ordinary, NO, UNNotificationSettingEnabled) == nil);
      assert(ordinary.interruptionLevel == UNNotificationInterruptionLevelActive);

      UNMutableNotificationContent *urgent = [UNMutableNotificationContent new];
      assert(TNApplyTimeSensitive(urgent, YES, UNNotificationSettingEnabled) == nil);
      assert(urgent.interruptionLevel == UNNotificationInterruptionLevelTimeSensitive);
      UNNotificationRequest *request = [UNNotificationRequest requestWithIdentifier:@"approval"
                                                                            content:urgent
                                                                            trigger:nil];
      assert(request.content.interruptionLevel == UNNotificationInterruptionLevelTimeSensitive);

      for (NSNumber *setting in @[@(UNNotificationSettingDisabled), @(UNNotificationSettingNotSupported)]) {
        UNMutableNotificationContent *fallback = [UNMutableNotificationContent new];
        NSString *warning = TNApplyTimeSensitive(fallback, YES, setting.integerValue);
        assert(warning.length > 0);
        assert(fallback.interruptionLevel == UNNotificationInterruptionLevelActive);
        assert(TNApplyTimeSensitive(fallback, NO, setting.integerValue) == nil);
      }
    }
    puts("Time Sensitive content tests passed (no notifications posted).");
  }
  return 0;
}
