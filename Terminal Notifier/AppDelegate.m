#import "AppDelegate.h"
#import <ScriptingBridge/ScriptingBridge.h>
#import <objc/runtime.h>
#import <UserNotifications/UserNotifications.h>

NSString * const TerminalNotifierBundleID = @"fr.julienxx.oss.terminal-notifier";
NSString * const NotificationCenterUIBundleID = @"com.apple.notificationcenterui";

NSString *_fakeBundleIdentifier = nil;

@implementation NSBundle (FakeBundleIdentifier)

- (NSString *)__bundleIdentifier;
{
  if (self == [NSBundle mainBundle]) {
    return _fakeBundleIdentifier ? _fakeBundleIdentifier : TerminalNotifierBundleID;
  } else {
    return [self __bundleIdentifier];
  }
}

@end

static BOOL
InstallFakeBundleIdentifierHook()
{
  Class class = objc_getClass("NSBundle");
  if (class) {
    method_exchangeImplementations(class_getInstanceMethod(class, @selector(bundleIdentifier)),
                                   class_getInstanceMethod(class, @selector(__bundleIdentifier)));
    return YES;
  }
  return NO;
}

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


@implementation AppDelegate

+(void)initializeUserDefaults
{
  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

  // initialize the dictionary with default values depending on OS level
  NSDictionary *appDefaults;
  appDefaults = @{@"sender": @"com.apple.Terminal"};

  // and set them appropriately
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
         "       -remove ID         Removes a notification with the specified ‘group’ ID.\n" \
         "       -list ID           If the specified ‘group’ ID exists show when it was delivered,\n" \
         "                          or use ‘ALL’ as ID to see all notifications.\n" \
         "                          The output is a tab-separated list.\n"
         "\n" \
         "   Optional:\n" \
         "\n" \
         "       -title VALUE       The notification title. Defaults to ‘Terminal’.\n" \
         "       -subtitle VALUE    The notification subtitle.\n" \
         "       -sound NAME        The name of a sound to play when the notification appears. The names are listed\n" \
         "                          in Sound Preferences. Use 'default' for the default notification sound.\n" \
         "       -group ID          A string which identifies the group the notifications belong to.\n" \
         "                          Old notifications with the same ID will be removed.\n" \
         "       -activate ID       The bundle identifier of the application to activate when the user clicks the notification.\n" \
         "       -sender ID         The bundle identifier of the application that should be shown as the sender, including its icon.\n" \
         "       -appIcon URL       The URL of a image to display instead of the application icon (Mavericks+ only)\n" \
         "       -contentImage URL  The URL of a image to display attached to the notification (Mavericks+ only)\n" \
         "       -open URL          The URL of a resource to open when the user clicks the notification.\n" \
         "       -execute COMMAND   A shell command to perform when the user clicks the notification.\n" \
         "       -ignoreDnD         Send notification even if Do Not Disturb is enabled.\n" \
         "\n" \
         "When the user activates a notification, the results are logged to the system logs.\n" \
         "Use Console.app to view these logs.\n" \
         "\n" \
         "Note that in some circumstances the first character of a message has to be escaped in order to be recognized.\n" \
         "An example of this is when using an open bracket, which has to be escaped like so: ‘\\[’.\n" \
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

- (void)applicationDidFinishLaunching:(NSNotification *)notification;
{
  // Request notification authorization
  UNUserNotificationCenter *center = [UNUserNotificationCenter currentNotificationCenter];
  center.delegate = self;
  [center requestAuthorizationWithOptions:(UNAuthorizationOptionAlert | UNAuthorizationOptionSound)
                        completionHandler:^(BOOL granted, NSError * _Nullable error) {
    if (!granted || error) {
      NSLog(@"Notification authorization denied or error: %@", error);
    }
  }];

  // Check if launched from notification response
  NSDictionary *userInfo = notification.userInfo[NSApplicationLaunchUserNotificationKey];
  if (userInfo) {
    [self handleNotificationResponse:userInfo];
  } else {
    if ([[[NSProcessInfo processInfo] arguments] indexOfObject:@"-help"] != NSNotFound) {
      [self printHelpBanner];
      exit(0);
    }

    if ([[[NSProcessInfo processInfo] arguments] indexOfObject:@"-version"] != NSNotFound) {
      [self printVersion];
      exit(0);
    }

    NSArray *runningProcesses = [[[NSWorkspace sharedWorkspace] runningApplications] valueForKey:@"bundleIdentifier"];
    if ([runningProcesses indexOfObject:NotificationCenterUIBundleID] == NSNotFound) {
      NSLog(@"[!] Unable to post a notification for the current user (%@), as it has no running NotificationCenter instance.", NSUserName());
      exit(1);
    }

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

    if (list) {
      [self listNotificationWithGroupID:list];
      exit(0);
    }

    // Install the fake bundle ID hook so we can fake the sender. This also
    // needs to be done to be able to remove a message.
    if (defaults[@"sender"]) {
      @autoreleasepool {
        if (InstallFakeBundleIdentifierHook()) {
          _fakeBundleIdentifier = defaults[@"sender"];
        }
      }
    }

    if (remove) {
      [self removeNotificationWithGroupID:remove];
      if (message == nil || ([message length] == 0)) {
          exit(0);
      }
    }

    if (message) {
      NSMutableDictionary *options = [NSMutableDictionary dictionary];
      if (defaults[@"activate"]) options[@"bundleID"]         = defaults[@"activate"];
      if (defaults[@"group"])    options[@"groupID"]          = defaults[@"group"];
      if (defaults[@"execute"])  options[@"command"]          = defaults[@"execute"];
      if (defaults[@"appIcon"])  options[@"appIcon"]          = defaults[@"appIcon"];
      if (defaults[@"contentImage"]) options[@"contentImage"] = defaults[@"contentImage"];

      if (defaults[@"open"]) {
        NSURL *url = [NSURL URLWithString:defaults[@"open"]];
        if ((url && url.scheme && url.host) || [url isFileURL]) {
          options[@"open"] = defaults[@"open"];
        }else{
          NSLog(@"'%@' is not a valid URI.", defaults[@"open"]);
          exit(1);
        }
      }

      if([[[NSProcessInfo processInfo] arguments] containsObject:@"-ignoreDnD"] == true) {
        options[@"ignoreDnD"] = @YES;
      }

      [self deliverNotificationWithTitle:defaults[@"title"] ?: @"Terminal"
                                subtitle:subtitle
                                 message:message
                                 options:options
                                   sound:sound];
    }
  }
}

- (NSImage*)getImageFromURL:(NSString *) url;
{
  NSURL *imageURL = [NSURL URLWithString:url];
  if([[imageURL scheme] length] == 0){
    // Prefix 'file://' if no scheme
    imageURL = [NSURL fileURLWithPath:url];
  }
  return [[NSImage alloc] initWithContentsOfURL:imageURL];
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

- (void)deliverNotificationWithTitle:(NSString *)title
                             subtitle:(NSString *)subtitle
                             message:(NSString *)message
                             options:(NSDictionary *)options
                               sound:(NSString *)sound;
{
  // First remove earlier notification with the same group ID.
  if (options[@"groupID"]) [self removeNotificationWithGroupID:options[@"groupID"]];

  // Create notification content
  UNMutableNotificationContent *content = [[UNMutableNotificationContent alloc] init];
  content.title = title;
  if (subtitle) content.subtitle = subtitle;
  content.body = message;
  content.userInfo = options;

  // Handle sound
  if (sound != nil) {
    if ([sound isEqualToString:@"default"]) {
      content.sound = [UNNotificationSound defaultSound];
    } else {
      content.sound = [UNNotificationSound soundNamed:sound];
    }
  }

  // Handle content image (attachment)
  if (options[@"contentImage"]) {
    NSImage *image = [self getImageFromURL:options[@"contentImage"]];
    if (image) {
      // Save image to temp file for attachment
      NSString *tempPath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"notifier-attachment.png"];
      NSData *imageData = [image TIFFRepresentation];
      NSBitmapImageRep *imageRep = [NSBitmapImageRep imageRepWithData:imageData];
      NSData *pngData = [imageRep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
      [pngData writeToFile:tempPath atomically:YES];

      NSURL *attachmentURL = [NSURL fileURLWithPath:tempPath];
      NSError *error = nil;
      UNNotificationAttachment *attachment = [UNNotificationAttachment attachmentWithIdentifier:@"image"
                                                                                             URL:attachmentURL
                                                                                         options:nil
                                                                                           error:&error];
      if (attachment && !error) {
        content.attachments = @[attachment];
      }
    }
  }

  // Set thread identifier (group ID)
  if (options[@"groupID"]) {
    content.threadIdentifier = options[@"groupID"];
  }

  // Handle interruption level for Do Not Disturb bypass (iOS 15+/macOS 12+)
  if (options[@"ignoreDnD"]) {
    if (@available(macOS 12.0, *)) {
      content.interruptionLevel = UNNotificationInterruptionLevelCritical;
    }
  }

  // Create request with unique identifier
  NSString *identifier = options[@"groupID"] ?: [[NSUUID UUID] UUIDString];
  UNNotificationRequest *request = [UNNotificationRequest requestWithIdentifier:identifier
                                                                        content:content
                                                                        trigger:nil]; // nil trigger = deliver immediately

  // Schedule notification
  UNUserNotificationCenter *center = [UNUserNotificationCenter currentNotificationCenter];
  [center addNotificationRequest:request withCompletionHandler:^(NSError * _Nullable error) {
    if (error) {
      NSLog(@"Error delivering notification: %@", error);
      exit(1);
    } else {
      // Exit after successful delivery
      exit(0);
    }
  }];
}

- (void)removeNotificationWithGroupID:(NSString *)groupID;
{
  UNUserNotificationCenter *center = [UNUserNotificationCenter currentNotificationCenter];
  dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);

  [center getDeliveredNotificationsWithCompletionHandler:^(NSArray<UNNotification *> * _Nonnull notifications) {
    NSMutableArray<NSString *> *identifiersToRemove = [NSMutableArray array];

    for (UNNotification *notification in notifications) {
      NSString *notificationGroupID = notification.request.content.threadIdentifier;

      if ([@"ALL" isEqualToString:groupID] || [notificationGroupID isEqualToString:groupID]) {
        NSDate *deliveredAt = notification.date;
        printf("* Removing previously sent notification, which was sent on: %s\n", [[deliveredAt description] UTF8String]);
        [identifiersToRemove addObject:notification.request.identifier];
      }
    }

    if (identifiersToRemove.count > 0) {
      [center removeDeliveredNotificationsWithIdentifiers:identifiersToRemove];
    }

    dispatch_semaphore_signal(semaphore);
  }];

  // Wait for async operation to complete (with timeout)
  dispatch_time_t timeout = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5.0 * NSEC_PER_SEC));
  dispatch_semaphore_wait(semaphore, timeout);
}

- (void)listNotificationWithGroupID:(NSString *)listGroupID;
{
  UNUserNotificationCenter *center = [UNUserNotificationCenter currentNotificationCenter];
  __block NSArray<UNNotification *> *deliveredNotifications = nil;
  dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);

  // Fetch delivered notifications synchronously
  [center getDeliveredNotificationsWithCompletionHandler:^(NSArray<UNNotification *> * _Nonnull notifications) {
    deliveredNotifications = notifications;
    dispatch_semaphore_signal(semaphore);
  }];

  dispatch_time_t timeout = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5.0 * NSEC_PER_SEC));
  dispatch_semaphore_wait(semaphore, timeout);

  // Process notifications synchronously
  NSMutableArray *lines = [NSMutableArray array];

  for (UNNotification *notification in deliveredNotifications) {
    NSString *groupID = notification.request.content.threadIdentifier;
    NSString *title = notification.request.content.title;
    NSString *subtitle = notification.request.content.subtitle;
    NSString *message = notification.request.content.body;
    NSString *deliveredAt = [notification.date description];

    if ([@"ALL" isEqualToString:listGroupID] || [groupID isEqualToString:listGroupID]) {
      [lines addObject:[NSString stringWithFormat:@"%@\t%@\t%@\t%@\t%@", groupID, title, subtitle, message, deliveredAt]];
    }
  }

  if (lines.count > 0) {
    printf("GroupID\tTitle\tSubtitle\tMessage\tDelivered At\n");
    for (NSString *line in lines) {
      printf("%s\n", [line UTF8String]);
    }
  }
}


- (void)handleNotificationResponse:(NSDictionary *)userInfo;
{
  NSString *groupID  = userInfo[@"groupID"];
  NSString *bundleID = userInfo[@"bundleID"];
  NSString *command  = userInfo[@"command"];
  NSString *open     = userInfo[@"open"];

  NSLog(@"User activated notification:");
  NSLog(@" group ID: %@", groupID);
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

// UNUserNotificationCenterDelegate methods

// Handle notification when app is in foreground
- (void)userNotificationCenter:(UNUserNotificationCenter *)center
       willPresentNotification:(UNNotification *)notification
         withCompletionHandler:(void (^)(UNNotificationPresentationOptions))completionHandler;
{
  // Present the notification even when app is in foreground
  if (@available(macOS 11.0, *)) {
    completionHandler(UNNotificationPresentationOptionBanner | UNNotificationPresentationOptionSound);
  } else {
    completionHandler(UNNotificationPresentationOptionAlert | UNNotificationPresentationOptionSound);
  }
}

// Handle notification interaction (user clicked on notification)
- (void)userNotificationCenter:(UNUserNotificationCenter *)center
didReceiveNotificationResponse:(UNNotificationResponse *)response
         withCompletionHandler:(void (^)(void))completionHandler;
{
  // Remove the notification
  [center removeDeliveredNotificationsWithIdentifiers:@[response.notification.request.identifier]];

  // Handle the notification action
  NSDictionary *userInfo = response.notification.request.content.userInfo;
  [self handleNotificationResponse:userInfo];

  completionHandler();
}

@end
