#import "AppDelegate.h"
#import <ScriptingBridge/ScriptingBridge.h>

@implementation AppDelegate

// TODO See if we can get rid of the MainMenu nib completely, but for now just never show the window.
- (void)applicationWillFinishLaunching:(NSNotification *)notification;
{
  [self.window close];
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification;
{
  NSUserNotification *userNotification = notification.userInfo[NSApplicationLaunchUserNotificationKey];
  if (userNotification) {
    [self userActivatedNotification:userNotification];

  } else {
    NSArray *args = [[NSProcessInfo processInfo] arguments];

    if ([args count] < 4 || [args count] > 5) {
      printf("Usage: %s [sender PID] [sender name] [message] [activate app with bundle identifier]\n",
             [[args[0] lastPathComponent] UTF8String]);
      exit(1);
    }

    NSString *bundleID = [args count] == 5 ? args[4] : @"com.apple.Terminal";

    [self deliverNotificationForProcess:args[1]
                                   name:args[2]
                                message:args[3]
        activateAppWithBundleIdentifier:bundleID];
  }
}

- (void)deliverNotificationForProcess:(NSString *)senderPID
                                 name:(NSString *)senderName
                              message:(NSString *)message
      activateAppWithBundleIdentifier:(NSString *)bundleID;
{
  NSUserNotificationCenter *center = [NSUserNotificationCenter defaultUserNotificationCenter];
  NSUserNotification *userNotification = nil;

  // First remove earlier notifications from same process.
  for (userNotification in center.deliveredNotifications) {
    if ([userNotification.userInfo[@"senderPID"] isEqualToString:senderPID]) {
      [center removeDeliveredNotification:userNotification];
    }
  }

  // Now create and deliver the new notification
  userNotification = [NSUserNotification new];
  userNotification.title = senderName;
  userNotification.informativeText = message;
  userNotification.userInfo = @{ @"senderPID":senderPID, @"bundleID":bundleID };
  NSLog(@"Deliver notification: %@", userNotification);

  center.delegate = self;
  [center scheduleNotification:userNotification];
}

- (void)userActivatedNotification:(NSUserNotification *)userNotification;
{
  NSString *bundleID = userNotification.userInfo[@"bundleID"];
  id app = [SBApplication applicationWithBundleIdentifier:bundleID];
  NSLog(@"Activating app with bundle identifier `%@': %@", bundleID, app);
  [app activate];
  exit(0);
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
  exit(0);
}

@end
