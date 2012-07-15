#import "AppDelegate.h"

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
    [self userNotificationCenter:nil didActivateNotification:userNotification];

  } else {
    NSArray *args = [[NSProcessInfo processInfo] arguments];
    NSLog(@"ARGS: %@", args);

    if ([args count] < 4 || [args count] > 5) {
      printf("Usage: %s [sender PID] [sender name] [message] [activate app with bundle identifier]\n",
             [[args[0] lastPathComponent] UTF8String]);
      exit(1);
    }

    [self deliverNotificationForProcess:args[1] name:args[2] message:args[3]];
  }
}

- (void)deliverNotificationForProcess:(NSString *)senderPID
                                 name:(NSString *)senderName
                              message:(NSString *)message;
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
  userNotification.userInfo = @{ @"senderPID":senderPID };

  center.delegate = self;
  [center scheduleNotification:userNotification];
}

// TODO is this needed?
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

// This is actually never called by NSUserNotification, but from
// applicationDidFinishLaunching: if the app was started because
// the user activated the notification.
- (void)userNotificationCenter:(NSUserNotificationCenter *)center
       didActivateNotification:(NSUserNotification *)userNotification;
{
  NSLog(@"App launched because user activated notification: %@", userNotification);
  NSLog(@"User info: %@", userNotification.userInfo);
  exit(0);
}

@end
