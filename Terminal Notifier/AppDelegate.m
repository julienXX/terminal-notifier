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
         "Usage: %s -[message|list|remove] [VALUE|ID|ID] [options]\n" \
         "\n" \
         "   Either of these is required:\n" \
         "\n" \
         "       -message VALUE     The notification message.\n" \
         "       -remove ID         Removes a notification with the specified ‘group’ ID.\n" \
         "       -list ID           If the specified ‘group’ ID exists show when it was delivered,\n" \
         "                          or use ‘ALL’ as ID to see all notifications.\n" \
         "                          The output is a tab-separated list.\n"
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

    if (list) {
      [self listNotificationWithGroupID:list];
      exit(0);
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
    if ([@"ALL" isEqualToString:groupID] || [userNotification.userInfo[@"groupID"] isEqualToString:groupID]) {
      NSString *deliveredAt = [userNotification.actualDeliveryDate description];
      printf("* Removing previously sent notification, which was sent on: %s\n", [deliveredAt UTF8String]);
      [center removeDeliveredNotification:userNotification];
    }
  }
}

- (void)listNotificationWithGroupID:(NSString *)listGroupID;
{
  NSUserNotificationCenter *center = [NSUserNotificationCenter defaultUserNotificationCenter];

  NSMutableArray *lines = [NSMutableArray array];
  for (NSUserNotification *userNotification in center.deliveredNotifications) {
    NSString *deliveredgroupID = userNotification.userInfo[@"groupID"];
    NSString *title            = userNotification.title;
    NSString *subtitle         = userNotification.subtitle;
    NSString *message          = userNotification.informativeText;
    NSString *deliveredAt      = [userNotification.actualDeliveryDate description];
    if ([@"ALL" isEqualToString:listGroupID] || [deliveredgroupID isEqualToString:listGroupID]) {
      [lines addObject:[NSString stringWithFormat:@"%@\t%@\t%@\t%@\t%@", deliveredgroupID, title, subtitle, message, deliveredAt]];
    }
  }

  if (lines.count > 0) {
    printf("GroupID\tTitle\tSubtitle\tMessage\tDelivered At\n");
    for (NSString *line in lines) {
      printf("%s\n", [line UTF8String]);
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
