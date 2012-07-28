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
    NSUserDefaults *options = [NSUserDefaults standardUserDefaults];

    NSString *message = options[@"message"];
    NSLog(@"MESSAGE: %@", message);

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

    NSString *title    = options[@"title"]    ?: @"Terminal";
    NSString *bundleID = options[@"activate"] ?: @"com.apple.Terminal";
    NSString *groupID  = options[@"group"];
    NSString *command  = options[@"execute"];

    [self deliverNotificationForGroupID:groupID
                                  title:title
                                message:message
        activateAppWithBundleIdentifier:bundleID
                    executeShellCommand:command];
  }
}

- (void)deliverNotificationForGroupID:(NSString *)groupID
                                title:(NSString *)title
                              message:(NSString *)message
      activateAppWithBundleIdentifier:(NSString *)bundleID
                  executeShellCommand:(NSString *)command;
{
  NSUserNotificationCenter *center = [NSUserNotificationCenter defaultUserNotificationCenter];
  NSUserNotification *userNotification = nil;

  // First remove earlier notification with the same group ID.
  if (groupID) {
    for (userNotification in center.deliveredNotifications) {
      if ([userNotification.userInfo[@"groupID"] isEqualToString:groupID]) {
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
  NSMutableDictionary *info = [NSMutableDictionary dictionary];
  if (groupID)  info[@"groupID"]  = groupID;
  if (bundleID) info[@"bundleID"] = bundleID;
  if (command)  info[@"command"]  = command;
  userNotification.userInfo = info;

  center.delegate = self;
  [center scheduleNotification:userNotification];
}

- (void)userActivatedNotification:(NSUserNotification *)userNotification;
{
  [[NSUserNotificationCenter defaultUserNotificationCenter] removeDeliveredNotification:userNotification];

  NSString *groupID  = userNotification.userInfo[@"groupID"];
  NSString *bundleID = userNotification.userInfo[@"bundleID"];
  NSString *command  = userNotification.userInfo[@"command"];

  NSLog(@"User activated notification:");
  NSLog(@" group ID: %@", groupID);
  NSLog(@"    title: %@", userNotification.title);
  NSLog(@"  message: %@", userNotification.informativeText);
  NSLog(@"bundle ID: %@", bundleID);
  NSLog(@"  command: %@", command);

  BOOL success = YES;
  if (bundleID) success = [self activateAppWithBundleID:bundleID];
  if (command)  success = [self executeShellCommand:command];

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
