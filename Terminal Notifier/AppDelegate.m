#import "AppDelegate.h"
#import <ScriptingBridge/ScriptingBridge.h>

@interface NSUserDefaults (Subscript)
@end

@implementation NSUserDefaults (Subscript)
- (id)objectForKeyedSubscript:(id)key;
{
  return [self objectForKey:key];
}
@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification;
{
  NSUserNotification *userNotification = notification.userInfo[NSApplicationLaunchUserNotificationKey];
  if (userNotification) {
    [self userActivatedNotification:userNotification];

  } else {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

    NSString *message = defaults[@"message"];
    if (message == nil) {
      const char *appName = "terminal-notifier"; //[[args[0] lastPathComponent] UTF8String];
      const char *appVersion = [[[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"] UTF8String];
      printf("%s (%s) is a command-line tool to send OS X User Notifications.\n" \
             "\n" \
             "Usage: %s group-ID title message --activate [bundle-ID] --execute [command]\n" \
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

    NSMutableDictionary *options = [NSMutableDictionary dictionary];
    options[@"bundleID"] = defaults[@"activate"] ?: @"com.apple.Terminal";

    if (defaults[@"group"])   options[@"groupID"] = defaults[@"group"];
    if (defaults[@"execute"]) options[@"command"] = defaults[@"execute"];
    if (defaults[@"open"])    options[@"open"]    = defaults[@"open"];

    [self deliverNotificationWithTitle:defaults[@"title"] ?: @"Terminal"
                               message:message
                               options:options];
  }
}

- (void)deliverNotificationWithTitle:(NSString *)title
                             message:(NSString *)message
                             options:(NSDictionary *)options;
{
  NSUserNotificationCenter *center = [NSUserNotificationCenter defaultUserNotificationCenter];
  NSUserNotification *userNotification = nil;

  // First remove earlier notification with the same group ID.
  if (options[@"groupID"]) {
    for (userNotification in center.deliveredNotifications) {
      if ([userNotification.userInfo[@"groupID"] isEqualToString:options[@"groupID"]]) {
        NSString *deliveredAt = [userNotification.actualDeliveryDate description];
        printf("* Removing previous notification, which was delivered on: %s\n", [deliveredAt UTF8String]);
        [center removeDeliveredNotification:userNotification];
        break;
      }
    }
  }

  // Now create and deliver the new notification
  userNotification = [NSUserNotification new];
  userNotification.title = title;
  userNotification.informativeText = message;
  userNotification.userInfo = options;

  center.delegate = self;
  [center scheduleNotification:userNotification];
}

- (void)userActivatedNotification:(NSUserNotification *)userNotification;
{
  [[NSUserNotificationCenter defaultUserNotificationCenter] removeDeliveredNotification:userNotification];

  NSString *groupID  = userNotification.userInfo[@"groupID"];
  NSString *bundleID = userNotification.userInfo[@"bundleID"];
  NSString *command  = userNotification.userInfo[@"command"];
  NSString *open     = userNotification.userInfo[@"open"];

  NSLog(@"User activated notification:");
  NSLog(@" group ID: %@", groupID);
  NSLog(@"    title: %@", userNotification.title);
  NSLog(@"  message: %@", userNotification.informativeText);
  NSLog(@"bundle ID: %@", bundleID);
  NSLog(@"  command: %@", command);
  NSLog(@"     open: %@", open);

  BOOL success = YES;
  // TODO this loses NO if a consecutive call does succeed
  if (bundleID) success = [self activateAppWithBundleID:bundleID];
  if (command)  success = [self executeShellCommand:command];
  if (open)     success = [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:open]];

  exit(success ? 0 : 1);
}

- (BOOL)activateAppWithBundleID:(NSString *)bundleID;
{
  id app = [SBApplication applicationWithBundleIdentifier:bundleID];
  if (app) {
    [app activate];
    return YES;

  } else {
    NSLog(@"Unable to find an application with the specified bundle indentifier.");
    return NO;
  }
}

- (BOOL)executeShellCommand:(NSString *)command;
{
  NSTask *task = [NSTask launchedTaskWithLaunchPath:@"/bin/sh"
                                          arguments:@[@"-c", command]];
  [task waitUntilExit];
  return [task terminationStatus] == 0;
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
