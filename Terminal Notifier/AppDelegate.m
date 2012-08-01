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

- (void)printHelpBanner;
{
  const char *appName = [[[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleExecutable"] UTF8String];
  const char *appVersion = [[[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"] UTF8String];
  printf("%s (%s) is a command-line tool to send OS X User Notifications.\n" \
         "\n" \
         "Usage: %s -[message|remove] [VALUE|ID] [options]\n" \
         "\n" \
         "   Either of these is required:\n" \
         "\n" \
         "       -message VALUE     The notification message.\n" \
         "       -remove ID         Removes a notification with the specified ‘group’ ID.\n" \
	     "       -list ID           If the specified ‘group’ ID exists: show when it was delivered.\n" \
         "\n" \
         "   Optional:\n" \
         "\n" \
         "       -title VALUE       The notification title. Defaults to ‘Terminal’.\n" \
         "       -subtitle VALUE    The notification subtitle.\n" \
         "       -group ID          A string which identifies the group the notifications belong to.\n" \
         "                          Old notifications with the same ID will be removed.\n" \
         "       -activate ID       The bundle identifier of the application to activate when the user clicks the notification.\n" \
         "       -open URL          The URL of a resource to open when the user clicks the notification.\n" \
         "       -execute COMMAND   A shell command to perform when the user clicks the notification.\n" \
         "\n" \
         "When the user activates a notification, the results are logged to the system logs.\n" \
         "Use Console.app to view these logs.\n",
         appName, appVersion, appName);
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification;
{
  NSUserNotification *userNotification = notification.userInfo[NSApplicationLaunchUserNotificationKey];
  if (userNotification) {
    [self userActivatedNotification:userNotification];

  } else {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

    NSString *subtitle = defaults[@"subtitle"];
    NSString *message  = defaults[@"message"];
    NSString *remove   = defaults[@"remove"];
    NSString *list     = defaults[@"list"];
    if (message == nil && remove == nil && list == nil) {
      [self printHelpBanner];
      exit(1);
    }

    if (remove) {
      [self removeNotificationWithGroupID:remove];
      if (message == nil) exit(0);
    }

    if (message) {
      NSMutableDictionary *options = [NSMutableDictionary dictionary];
      if (defaults[@"activate"]) options[@"bundleID"] = defaults[@"activate"];
      if (defaults[@"group"])    options[@"groupID"]  = defaults[@"group"];
      if (defaults[@"execute"])  options[@"command"]  = defaults[@"execute"];
      if (defaults[@"open"])     options[@"open"]     = defaults[@"open"];

      [self deliverNotificationWithTitle:defaults[@"title"] ?: @"Terminal"
                                 subtitle:subtitle
                                 message:message
                                 options:options];
    }

    if (list) {
      //NSMutableDictionary *options = [NSMutableDictionary dictionary];
      [self listNotificationWithGroupID:list];
      exit(0);
    }
  }
}

- (void)deliverNotificationWithTitle:(NSString *)title
                             subtitle:(NSString *)subtitle
                             message:(NSString *)message
                             options:(NSDictionary *)options;
{
  // First remove earlier notification with the same group ID.
  if (options[@"groupID"]) [self removeNotificationWithGroupID:options[@"groupID"]];

  NSUserNotification *userNotification = [NSUserNotification new];
  userNotification.title = title;
  userNotification.subtitle = subtitle;
  userNotification.informativeText = message;
  userNotification.userInfo = options;

  NSUserNotificationCenter *center = [NSUserNotificationCenter defaultUserNotificationCenter];
  center.delegate = self;
  [center scheduleNotification:userNotification];
}

- (void)removeNotificationWithGroupID:(NSString *)groupID;
{
  NSUserNotificationCenter *center = [NSUserNotificationCenter defaultUserNotificationCenter];
  for (NSUserNotification *userNotification in center.deliveredNotifications) {
    if ( ([userNotification.userInfo[@"groupID"] isEqualToString:groupID]) ||
        ([@"ALL" isEqualToString:groupID])) {
      NSString *deliveredAt = [userNotification.actualDeliveryDate description];
      printf("* Removing previously sent notification, which was sent on: %s\n", [deliveredAt UTF8String]);
      [center removeDeliveredNotification:userNotification];
    }
  }
}

- (void)listNotificationWithGroupID:(NSString *)groupID;
{
  NSUInteger len = 1;
  NSUInteger longestLen = 0;
  NSUInteger i=0;
  NSUserNotificationCenter *center = [NSUserNotificationCenter defaultUserNotificationCenter];
  if ([@"ALL" isEqualToString:groupID]) {
    printf("* Currently active groups:\n");
    for (NSUserNotification *userNotification in center.deliveredNotifications) {
      NSString *deliveredGroupID = userNotification.userInfo[@"groupID"];
      len = [deliveredGroupID length];
      if (len > longestLen) {
        longestLen = len;
      }
    }
    if (longestLen > 0) {
      printf("* Group ID");
      for (i = 8; i < longestLen; i++) {
        printf(" ");
      }
      printf("   ");
      printf("Delivered on\n");
    }
    for (NSUserNotification *userNotification in center.deliveredNotifications) {
      NSString *deliveredGroupID = userNotification.userInfo[@"groupID"];
      NSString *deliveredAt = [userNotification.actualDeliveryDate description];
      printf("* %s", [deliveredGroupID UTF8String]);
      len = [deliveredGroupID length];
      for (i = len; i < longestLen; i++) {
        printf(" ");
      }
      for (i = longestLen; i < 8; i++) {
        printf(" ");
      }
      printf("   ");
      printf("%s\n", [deliveredAt UTF8String]);
    }
  } else {
    for (NSUserNotification *userNotification in center.deliveredNotifications) {
      if ([userNotification.userInfo[@"groupID"] isEqualToString:groupID]) {
        longestLen = 1;
        NSString *deliveredAt = [userNotification.actualDeliveryDate description];
        printf("* The last message for group %s was delivered on: %s\n", [groupID UTF8String], [deliveredAt UTF8String]);
        break;
      }
    }
  }
  if (longestLen == 0) {
    if ([@"ALL" isEqualToString:groupID]) {
      printf("* None\n");
    } else { 
      printf("* No message for the group %s could be found\n", [groupID UTF8String]);
    }
  }
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
  NSLog(@" subtitle: %@", userNotification.subtitle);
  NSLog(@"  message: %@", userNotification.informativeText);
  NSLog(@"bundle ID: %@", bundleID);
  NSLog(@"  command: %@", command);
  NSLog(@"     open: %@", open);

  BOOL success = YES;
  // TODO this loses NO if a consecutive call does succeed
  if (bundleID) success = [self activateAppWithBundleID:bundleID] && success;
  if (command)  success = [self executeShellCommand:command] && success;
  if (open)     success = [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:open]] && success;

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
  NSPipe *pipe = [NSPipe pipe];
  NSFileHandle *fileHandle = [pipe fileHandleForReading];

  NSTask *task = [NSTask new];
  task.launchPath = @"/bin/sh";
  task.arguments = @[@"-c", command];
  task.standardOutput = pipe;
  task.standardError = pipe;
  [task launch];

  NSData *data = nil;
  NSMutableData *accumulatedData = [NSMutableData data];
  while ((data = [fileHandle availableData]) && [data length]) {
    [accumulatedData appendData:data];
  }

  [task waitUntilExit];
  NSLog(@"command output:\n%@", [[NSString alloc] initWithData:accumulatedData encoding:NSUTF8StringEncoding]);
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
