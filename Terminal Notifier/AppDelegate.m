#import "AppDelegate.h"
#import <ScriptingBridge/ScriptingBridge.h>

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification;
{
  NSUserNotification *userNotification = notification.userInfo[NSApplicationLaunchUserNotificationKey];
  if (userNotification) {
    [self userActivatedNotification:userNotification];

  } else {
    NSArray *args = [[NSProcessInfo processInfo] arguments];

    if ([args count] < 4 || [args count] > 5) {
      const char *appName = [[args[0] lastPathComponent] UTF8String];
      const char *appVersion = [[[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"] UTF8String];
      printf("%s (%s) is a command-line tool to send OS X User Notifications.\n" \
             "\n" \
             "Usage: %s group-ID title message [bundle-ID]\n" \
             "\n" \
             "     group-ID\tA string which identifies the group the notifications belong to.\n" \
             "             \tOld notifications with the same ID will be removed.\n" \
             "        title\tThe notification title.\n" \
             "      message\tThe notification message.\n" \
             "    bundle-ID\tThe bundle identifier of the application to activate when the user\n" \
             "             \tactivates (clicks) a notification. Defaults to `com.apple.Terminal'.\n" \
             "\n" \
             "When the user activates a notification, the results are logged to the system logs.\n" \
             "Use Console.app to view these logs.\n",
             appName, appVersion, appName);
      exit(1);
    }

    NSString *bundleID = [args count] == 5 ? args[4] : @"com.apple.Terminal";

    [self deliverNotificationForGroupID:args[1]
                                  title:args[2]
                                message:args[3]
        activateAppWithBundleIdentifier:bundleID];
  }
}

- (void)deliverNotificationForGroupID:(NSString *)groupID
                                title:(NSString *)title
                              message:(NSString *)message
      activateAppWithBundleIdentifier:(NSString *)bundleID;
{
  NSUserNotificationCenter *center = [NSUserNotificationCenter defaultUserNotificationCenter];
  NSUserNotification *userNotification = nil;

  // First remove earlier notification with the same group ID.
  for (userNotification in center.deliveredNotifications) {
    if ([userNotification.userInfo[@"groupID"] isEqualToString:groupID]) {
      NSString *deliveredAt = [userNotification.actualDeliveryDate description];
      printf("* Removing previous notification, which was delivered on: %s\n", [deliveredAt UTF8String]);
      [center removeDeliveredNotification:userNotification];
      break;
    }
  }

  // Now create and deliver the new notification
  userNotification = [NSUserNotification new];
  userNotification.title = title;
  userNotification.informativeText = message;
  userNotification.userInfo = @{ @"groupID":groupID, @"bundleID":bundleID };

  center.delegate = self;
  [center scheduleNotification:userNotification];
}

- (void)userActivatedNotification:(NSUserNotification *)userNotification;
{
  [[NSUserNotificationCenter defaultUserNotificationCenter] removeDeliveredNotification:userNotification];

  NSString *groupID = userNotification.userInfo[@"groupID"];
  NSString *bundleID = userNotification.userInfo[@"bundleID"];

  NSLog(@"User activated notification:");
  NSLog(@" group ID: %@", groupID);
  NSLog(@"    title: %@", userNotification.title);
  NSLog(@"  message: %@", userNotification.informativeText);
  NSLog(@"bundle ID: %@", bundleID);

  id app = [SBApplication applicationWithBundleIdentifier:bundleID];
  if (app) {
    [app activate];
    exit(0);

  } else {
    NSLog(@"Unable to find an application with the specified bundle indentifier.");
    exit(1);
  }
}

// TODO is this really needed?
- (BOOL)userNotificationCenter:(NSUserNotificationCenter *)center
     shouldPresentNotification:(NSUserNotification *)userNotification;
{
  return YES;
}

// Once the notification is delivered we can exit.
- (void)userNotificationCenter:(NSUserNotificationCenter *)center
        didDeliverNotification:(NSUserNotification *)userNotification;
{
  printf("* Notification delivered.\n");
  exit(0);
}

@end
