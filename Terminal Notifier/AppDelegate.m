#import "AppDelegate.h"
#import <ScriptingBridge/ScriptingBridge.h>
#import <UserNotifications/UserNotifications.h>

@implementation NSUserDefaults (SubscriptAndUnescape)
- (id)objectForKeyedSubscript:(id)key;
{
  id obj = [self objectForKey:key];
  if ([obj isKindOfClass:[NSString class]] && [(NSString *)obj hasPrefix:@"\\"]) {
    obj = [(NSString *)obj substringFromIndex:1];
  }
  return obj;
}
@end

@interface AppDelegate ()
@property (nonatomic) BOOL launchedFromNotification;
@end

@implementation AppDelegate

+(void)initializeUserDefaults
{
  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
  NSDictionary *appDefaults = @{@"sender": @"com.apple.Terminal"};
  [defaults registerDefaults:appDefaults];
}

- (void)printHelpBanner;
{
  const char *appName = [[[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleExecutable"] UTF8String];
  const char *appVersion = [[[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"] UTF8String];
  printf("%s (%s) is a command-line tool to send macOS User Notifications.\n" \
         "\n" \
         "Usage: %s -[message|list|remove] [VALUE|ID|ID] [options]\n" \
         "\n" \
         "   Either of these is required (unless message data is piped to the tool):\n" \
         "\n" \
         "       -help              Display this help banner.\n" \
         "       -version           Display terminal-notifier version.\n" \
         "       -message VALUE     The notification message.\n" \
         "       -remove ID         Removes a notification with the specified 'group' ID.\n" \
         "       -list ID           If the specified 'group' ID exists show when it was delivered,\n" \
         "                          or use 'ALL' as ID to see all notifications.\n" \
         "                          The output is a tab-separated list.\n"
         "\n" \
         "   Optional:\n" \
         "\n" \
         "       -title VALUE       The notification title. Defaults to 'Terminal'.\n" \
         "       -subtitle VALUE    The notification subtitle.\n" \
         "       -sound NAME        The name of a sound to play when the notification appears. The names are listed\n" \
         "                          in /System/Library/Sounds. Use 'default' for the default notification sound.\n" \
         "       -group ID          A string which identifies the group the notifications belong to.\n" \
         "                          Old notifications with the same ID will be removed.\n" \
         "       -activate ID       The bundle identifier of the application to activate when the user clicks the notification.\n" \
         "       -contentImage URL  The URL of a local image to display attached to the notification.\n" \
         "       -open URL          The URL of a resource to open when the user clicks the notification.\n" \
         "       -execute COMMAND   A shell command to perform when the user clicks the notification.\n" \
         "       -ignoreDnD         Send notification even if Do Not Disturb is enabled (macOS 12+ only).\n" \
         "\n" \
         "When the user activates a notification, the results are logged to the system logs.\n" \
         "Use Console.app to view these logs.\n" \
         "\n" \
         "Note that in some circumstances the first character of a message has to be escaped in order to be recognized.\n" \
         "An example of this is when using an open bracket, which has to be escaped like so: '\\['.\n" \
         "\n" \
         "For more information see https://github.com/julienXX/terminal-notifier.\n",
         appName, appVersion, appName);
}

- (void)printVersion;
{
  const char *appName = [[[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleExecutable"] UTF8String];
  const char *appVersion = [[[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"] UTF8String];
  printf("%s %s.\n", appName, appVersion);
}

- (void)applicationWillFinishLaunching:(NSNotification *)notification;
{
  // Set delegate early so didReceiveNotificationResponse fires before
  // applicationDidFinishLaunching when launched via a notification click.
  [UNUserNotificationCenter currentNotificationCenter].delegate = self;
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification;
{
  if ([[[NSProcessInfo processInfo] arguments] indexOfObject:@"-help"] != NSNotFound) {
    [self printHelpBanner];
    exit(0);
  }

  if ([[[NSProcessInfo processInfo] arguments] indexOfObject:@"-version"] != NSNotFound) {
    [self printVersion];
    exit(0);
  }

  // If the app was launched by the user clicking a notification, the delegate
  // method already handled everything and called exit().  We should not reach
  // here in that case, but guard defensively.
  if (self.launchedFromNotification) return;

  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

  NSString *subtitle = defaults[@"subtitle"];
  NSString *message  = defaults[@"message"];
  NSString *remove   = defaults[@"remove"];
  NSString *list     = defaults[@"list"];
  NSString *sound    = defaults[@"sound"];

  // If there is no message and data is piped to the application, use that
  // instead.
  if (message == nil && !isatty(STDIN_FILENO)) {
    NSData *inputData = [NSData dataWithData:[[NSFileHandle fileHandleWithStandardInput] readDataToEndOfFile]];
    message = [[NSString alloc] initWithData:inputData encoding:NSUTF8StringEncoding];
  }

  if (message == nil && remove == nil && list == nil) {
    [self printHelpBanner];
    exit(1);
  }

  if (defaults[@"sender"]) {
    NSLog(@"[!] -sender is not supported with UNUserNotificationCenter and will be ignored.");
  }

  if (list) {
    [self listNotificationWithGroupID:list];
    return; // exits inside the completion handler
  }

  if (remove) {
    [self removeNotificationWithGroupID:remove completionHandler:^{
      if (message == nil || message.length == 0) exit(0);
    }];
    if (message == nil || message.length == 0) return;
  }

  if (message) {
    NSMutableDictionary *options = [NSMutableDictionary dictionary];
    if (defaults[@"activate"])     options[@"bundleID"]      = defaults[@"activate"];
    if (defaults[@"group"])        options[@"groupID"]        = defaults[@"group"];
    if (defaults[@"execute"])      options[@"command"]        = defaults[@"execute"];
    if (defaults[@"contentImage"]) options[@"contentImage"]  = defaults[@"contentImage"];

    if (defaults[@"appIcon"]) {
      NSLog(@"[!] -appIcon is not supported with UNUserNotificationCenter and will be ignored.");
    }

    if (defaults[@"open"]) {
      NSURL *url = [NSURL URLWithString:defaults[@"open"]];
      if ((url && url.scheme && url.host) || [url isFileURL]) {
        options[@"open"] = defaults[@"open"];
      } else {
        NSLog(@"'%@' is not a valid URI.", defaults[@"open"]);
        exit(1);
      }
    }

    if ([[[NSProcessInfo processInfo] arguments] containsObject:@"-ignoreDnD"]) {
      options[@"ignoreDnD"] = @YES;
    }

    [self deliverNotificationWithTitle:defaults[@"title"] ?: @"Terminal"
                              subtitle:subtitle
                               message:message
                               options:options
                                 sound:sound];
  }
}

- (NSURL *)localFileURLFromString:(NSString *)urlString;
{
  NSURL *url = [NSURL URLWithString:urlString];
  if ([[url scheme] length] == 0) {
    url = [NSURL fileURLWithPath:urlString];
  }
  return url;
}

/**
 * Decode fragment identifier
 *
 * @see http://tools.ietf.org/html/rfc3986#section-2.1
 * @see http://en.wikipedia.org/wiki/URI_scheme
 */
- (NSString*)decodeFragmentInURL:(NSString *) encodedURL fragment:(NSString *) framgent
{
    NSString *beforeStr = [@"%23" stringByAppendingString:framgent];
    NSString *afterStr = [@"#" stringByAppendingString:framgent];
    NSString *decodedURL = [encodedURL stringByReplacingOccurrencesOfString:beforeStr withString:afterStr];
    return decodedURL;
}

- (void)requestAuthorizationAndThen:(void (^)(void))block;
{
  UNUserNotificationCenter *center = [UNUserNotificationCenter currentNotificationCenter];
  UNAuthorizationOptions opts = UNAuthorizationOptionAlert | UNAuthorizationOptionSound;
  [center requestAuthorizationWithOptions:opts completionHandler:^(BOOL granted, NSError *error) {
    if (!granted) {
      NSLog(@"[!] Permission to send notifications was denied.");
      exit(1);
    }
    dispatch_async(dispatch_get_main_queue(), ^{ block(); });
  }];
}

- (void)deliverNotificationWithTitle:(NSString *)title
                             subtitle:(NSString *)subtitle
                              message:(NSString *)message
                              options:(NSDictionary *)options
                                sound:(NSString *)sound;
{
  [self requestAuthorizationAndThen:^{
    UNMutableNotificationContent *content = [UNMutableNotificationContent new];
    content.title = title;
    if (subtitle) content.subtitle = subtitle;
    content.body = message;

    if (sound != nil) {
      if ([sound isEqualToString:@"default"]) {
        content.sound = [UNNotificationSound defaultSound];
      } else {
        content.sound = [UNNotificationSound soundNamed:sound];
      }
    }

    if (options[@"ignoreDnD"]) {
      if (@available(macOS 12, *)) {
        content.interruptionLevel = UNNotificationInterruptionLevelTimeSensitive;
      }
    }

    if (options[@"contentImage"]) {
      NSURL *imageURL = [self localFileURLFromString:options[@"contentImage"]];
      if ([imageURL isFileURL]) {
        NSError *attachError = nil;
        UNNotificationAttachment *attachment =
          [UNNotificationAttachment attachmentWithIdentifier:@"contentImage"
                                                        URL:imageURL
                                                    options:nil
                                                      error:&attachError];
        if (attachment) {
          content.attachments = @[attachment];
        } else {
          NSLog(@"[!] Could not create attachment for contentImage: %@", attachError.localizedDescription);
        }
      } else {
        NSLog(@"[!] -contentImage only supports local file paths with UNUserNotificationCenter.");
      }
    }

    // Store metadata needed by the click handler.
    NSMutableDictionary *userInfo = [NSMutableDictionary dictionary];
    if (options[@"bundleID"])  userInfo[@"bundleID"] = options[@"bundleID"];
    if (options[@"groupID"])   userInfo[@"groupID"]  = options[@"groupID"];
    if (options[@"command"])   userInfo[@"command"]  = options[@"command"];
    if (options[@"open"])      userInfo[@"open"]     = options[@"open"];
    content.userInfo = userInfo;

    NSString *identifier = options[@"groupID"] ?: @"terminal-notifier-default";

    // Remove any prior notification with the same identifier before scheduling.
    if (options[@"groupID"]) {
      UNUserNotificationCenter *center = [UNUserNotificationCenter currentNotificationCenter];
      [center removeDeliveredNotificationsWithIdentifiers:@[identifier]];
      [center removePendingNotificationRequestsWithIdentifiers:@[identifier]];
    }

    UNNotificationRequest *request =
      [UNNotificationRequest requestWithIdentifier:identifier
                                           content:content
                                           trigger:nil];

    [[UNUserNotificationCenter currentNotificationCenter]
      addNotificationRequest:request
       withCompletionHandler:^(NSError *error) {
      if (error) {
        NSLog(@"[!] Failed to deliver notification: %@", error.localizedDescription);
        exit(1);
      }
      // Give the system daemon time to process and play the notification sound
      // before we exit. willPresentNotification is not called for LSUIElement
      // apps, so the daemon handles presentation entirely on its own.
      dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
                     dispatch_get_main_queue(), ^{ exit(0); });
    }];
  }];
}

- (void)removeNotificationWithGroupID:(NSString *)groupID
                     completionHandler:(void (^)(void))completionHandler;
{
  UNUserNotificationCenter *center = [UNUserNotificationCenter currentNotificationCenter];
  [center getDeliveredNotificationsWithCompletionHandler:^(NSArray<UNNotification *> *notifications) {
    NSMutableArray<NSString *> *identifiers = [NSMutableArray array];
    for (UNNotification *notification in notifications) {
      NSString *deliveredGroupID = notification.request.content.userInfo[@"groupID"];
      if ([@"ALL" isEqualToString:groupID] || [deliveredGroupID isEqualToString:groupID]) {
        NSString *deliveredAt = [notification.date description];
        printf("* Removing previously sent notification, which was sent on: %s\n", [deliveredAt UTF8String]);
        [identifiers addObject:notification.request.identifier];
      }
    }
    if (identifiers.count > 0) {
      [center removeDeliveredNotificationsWithIdentifiers:identifiers];
    }
    dispatch_async(dispatch_get_main_queue(), ^{
      if (completionHandler) completionHandler();
    });
  }];
}

- (void)listNotificationWithGroupID:(NSString *)listGroupID;
{
  UNUserNotificationCenter *center = [UNUserNotificationCenter currentNotificationCenter];
  [center getDeliveredNotificationsWithCompletionHandler:^(NSArray<UNNotification *> *notifications) {
    NSMutableArray<NSString *> *lines = [NSMutableArray array];
    for (UNNotification *notification in notifications) {
      NSDictionary *userInfo       = notification.request.content.userInfo;
      NSString *deliveredGroupID   = userInfo[@"groupID"];
      NSString *notifTitle         = notification.request.content.title;
      NSString *notifSubtitle      = notification.request.content.subtitle;
      NSString *notifMessage       = notification.request.content.body;
      NSString *deliveredAt        = [notification.date description];
      if ([@"ALL" isEqualToString:listGroupID] || [deliveredGroupID isEqualToString:listGroupID]) {
        [lines addObject:[NSString stringWithFormat:@"%@\t%@\t%@\t%@\t%@",
                          deliveredGroupID, notifTitle, notifSubtitle, notifMessage, deliveredAt]];
      }
    }
    dispatch_async(dispatch_get_main_queue(), ^{
      if (lines.count > 0) {
        printf("GroupID\tTitle\tSubtitle\tMessage\tDelivered At\n");
        for (NSString *line in lines) {
          printf("%s\n", [line UTF8String]);
        }
      }
      exit(0);
    });
  }];
}

- (void)userActivatedNotification:(UNNotificationResponse *)response;
{
  self.launchedFromNotification = YES;

  NSDictionary *userInfo = response.notification.request.content.userInfo;
  NSString *groupID  = userInfo[@"groupID"];
  NSString *bundleID = userInfo[@"bundleID"];
  NSString *command  = userInfo[@"command"];
  NSString *open     = userInfo[@"open"];

  [[UNUserNotificationCenter currentNotificationCenter]
    removeDeliveredNotificationsWithIdentifiers:@[response.notification.request.identifier]];

  NSLog(@"User activated notification:");
  NSLog(@" group ID: %@", groupID);
  NSLog(@"    title: %@", response.notification.request.content.title);
  NSLog(@" subtitle: %@", response.notification.request.content.subtitle);
  NSLog(@"  message: %@", response.notification.request.content.body);
  NSLog(@"bundle ID: %@", bundleID);
  NSLog(@"  command: %@", command);
  NSLog(@"     open: %@", open);

  BOOL success = YES;
  if (bundleID) success &= [self activateAppWithBundleID:bundleID];
  if (command)  success &= [self executeShellCommand:command];
  if (open)     success &= [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:open]];

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

// MARK: - UNUserNotificationCenterDelegate

- (void)userNotificationCenter:(UNUserNotificationCenter *)center
       willPresentNotification:(UNNotification *)notification
         withCompletionHandler:(void (^)(UNNotificationPresentationOptions))completionHandler;
{
  // The app is always "foreground" during delivery; without this the system
  // would suppress the banner.
  UNNotificationPresentationOptions opts;
  if (@available(macOS 11, *)) {
    opts = UNNotificationPresentationOptionBanner
         | UNNotificationPresentationOptionSound
         | UNNotificationPresentationOptionList;
  } else {
    opts = UNNotificationPresentationOptionAlert
         | UNNotificationPresentationOptionSound;
  }
  completionHandler(opts);
}

- (void)userNotificationCenter:(UNUserNotificationCenter *)center
didReceiveNotificationResponse:(UNNotificationResponse *)response
         withCompletionHandler:(void (^)(void))completionHandler;
{
  [self userActivatedNotification:response];
  completionHandler();
}

@end
