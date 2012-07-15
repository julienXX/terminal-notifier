#import "AppDelegate.h"

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification;
{
  NSArray *args = [[NSProcessInfo processInfo] arguments];
  NSLog(@"ARGS: %@", args);

  if ([args count] < 3 || [args count] > 4) {
    printf("Usage: %s [sender name] [message] [activate app with bundle identifier]\n", [[args[0] lastPathComponent] UTF8String]);
    exit(1);
  }

  NSString *senderName = args[1];
  NSString *message = args[2];

  NSLog(@"SENDER: %@", senderName);
  NSLog(@"MESSAGE: %@", message);

  NSUserNotificationCenter *center = [NSUserNotificationCenter defaultUserNotificationCenter];
  center.delegate = self;

  NSUserNotification *userNotification = [[NSUserNotification alloc] init];
  userNotification.title = senderName;
  userNotification.informativeText = message;
  [center scheduleNotification:userNotification];

  NSLog(@"%@", [center scheduledNotifications]);
}

// TODO is this needed?
- (BOOL)userNotificationCenter:(NSUserNotificationCenter *)center shouldPresentNotification:(NSUserNotification *)userNotification;
{
  return YES;
}

// Once the notification is delivered we can exit.
- (void)userNotificationCenter:(NSUserNotificationCenter *)center didDeliverNotification:(NSUserNotification *)userNotification;
{
  exit(0);
}

@end
