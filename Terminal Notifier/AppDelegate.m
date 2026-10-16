#import "AppDelegate.h"
#import <UserNotifications/UserNotifications.h>

static const int TNExitSuccess        = 0;
static const int TNExitUsage          = 1;
static const int TNExitBadArgument    = 2;
static const int TNExitNotAuthorized  = 3;
static const int TNExitTimeout        = 4;
static const int TNExitDeliveryFailed = 5;
static const int TNExitNoResponse     = 6;

static const NSTimeInterval TNTimeoutSeconds = 10.0;

// TerminalNotifier.notify_result parses these exact spellings.
static NSString * const TNResponseTimeout   = @"@TIMEOUT";
static NSString * const TNResponseClosed    = @"@CLOSED";
static NSString * const TNResponseClicked   = @"@ACTIONCLICKED";
static NSString * const TNCategoryIdentifier = @"fr.julienxx.oss.terminal-notifier.actions";
static NSString * const TNReplyActionIdentifier = @"reply";

// macOS relaunches this bundle with no arguments and delivers the click
// response after applicationDidFinishLaunching returns, so it has to linger.
static const NSTimeInterval TNResponseGraceSeconds = 5.0;

static void TNError(NSString *format, ...)
{
  va_list args;
  va_start(args, format);
  NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
  va_end(args);
  fprintf(stderr, "%s\n", [message UTF8String]);
}

static BOOL TNTimeSensitiveRequested(NSArray<NSString *> *arguments)
{
  return [arguments containsObject:@"-timeSensitive"] ||
         [arguments containsObject:@"-ignoreDnD"];
}

// Return a diagnostic when the request cannot be honored. Keep the ordinary
// alert in that case: losing an approval prompt would be worse than delay.
static NSString *TNApplyTimeSensitive(UNMutableNotificationContent *content,
                                     BOOL requested, UNNotificationSetting setting)
{
  if (!requested) return nil;
  if (@available(macOS 12.0, *)) {
    if (setting == UNNotificationSettingEnabled) {
      content.interruptionLevel = UNNotificationInterruptionLevelTimeSensitive;
      return nil;
    }
    if (setting == UNNotificationSettingDisabled) {
      return @"Time Sensitive notifications are disabled in System Settings > Notifications.";
    }
    return @"This build does not support Time Sensitive notifications. Use a provisioned build; ad-hoc signing cannot enable this capability.";
  }
  return @"Time Sensitive notifications require macOS 12 or later.";
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

static NSString *TNSanitizeField(NSString *value)
{
  if (value == nil) return @"";

  NSString *result = value;
  for (NSString *character in @[@"\t", @"\n", @"\r"]) {
    result = [result stringByReplacingOccurrencesOfString:character withString:@" "];
  }
  return result;
}

static BOOL TNParseDuration(NSString *value, NSTimeInterval *seconds)
{
  if (value == nil) return NO;

  NSScanner *scanner = [NSScanner scannerWithString:value];
  double amount = 0;
  if (![scanner scanDouble:&amount]) return NO;

  NSString *unit = [value substringFromIndex:[scanner scanLocation]];
  unit = [unit stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];

  double multiplier;
  if      (unit.length == 0)              multiplier = 1;
  else if ([unit isEqualToString:@"s"])   multiplier = 1;
  else if ([unit isEqualToString:@"m"])   multiplier = 60;
  else if ([unit isEqualToString:@"h"])   multiplier = 60 * 60;
  else if ([unit isEqualToString:@"d"])   multiplier = 60 * 60 * 24;
  else return NO;

  double result = amount * multiplier;
  if (result <= 0) return NO;

  *seconds = result;
  return YES;
}

// A bare clock time yields only hour and minute, so the trigger fires at the
// next match. en_US_POSIX so a 12-hour locale reads these formats the same.
static BOOL TNParseTriggerDate(NSString *value, NSDateComponents **components)
{
  if (value == nil) return NO;

  NSString *trimmed = [value stringByTrimmingCharactersInSet:
                        [NSCharacterSet whitespaceCharacterSet]];

  NSCalendar *calendar = [NSCalendar currentCalendar];
  NSDateFormatter *formatter = [NSDateFormatter new];
  formatter.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
  formatter.timeZone = [NSTimeZone localTimeZone];

  formatter.dateFormat = @"HH:mm";
  NSDate *timeOnly = [formatter dateFromString:trimmed];
  if (timeOnly != nil) {
    *components = [calendar components:(NSCalendarUnitHour | NSCalendarUnitMinute)
                              fromDate:timeOnly];
    return YES;
  }

  for (NSString *format in @[@"yyyy-MM-dd HH:mm", @"yyyy-MM-dd'T'HH:mm"]) {
    formatter.dateFormat = format;
    NSDate *full = [formatter dateFromString:trimmed];
    if (full == nil) continue;

    *components = [calendar components:(NSCalendarUnitYear | NSCalendarUnitMonth |
                                        NSCalendarUnitDay | NSCalendarUnitHour |
                                        NSCalendarUnitMinute)
                              fromDate:full];
    return YES;
  }

  return NO;
}

// nextTriggerDate is on the two concrete trigger classes, not the superclass a
// request hands back, so it needs a type check. nil for an immediate request.
static NSDate *TNNextTriggerDate(UNNotificationTrigger *trigger)
{
  if ([trigger isKindOfClass:[UNCalendarNotificationTrigger class]]) {
    return [(UNCalendarNotificationTrigger *)trigger nextTriggerDate];
  }
  if ([trigger isKindOfClass:[UNTimeIntervalNotificationTrigger class]]) {
    return [(UNTimeIntervalNotificationTrigger *)trigger nextTriggerDate];
  }
  return nil;
}

// Empty fields rather than "(null)", so the output stays parseable.
static NSString *TNListRow(UNNotificationContent *content, NSString *lastColumn)
{
  return [NSString stringWithFormat:@"%@\t%@\t%@\t%@\t%@",
          TNSanitizeField(content.userInfo[@"groupID"]),
          TNSanitizeField(content.title),
          TNSanitizeField(content.subtitle),
          TNSanitizeField(content.body),
          TNSanitizeField(lastColumn)];
}

static NSString *TNAuthorizationStatusName(UNAuthorizationStatus status)
{
  switch (status) {
    case UNAuthorizationStatusNotDetermined: return @"not requested yet";
    case UNAuthorizationStatusDenied:        return @"denied";
    case UNAuthorizationStatusAuthorized:    return @"authorized";
    case UNAuthorizationStatusProvisional:   return @"provisional";
    default:                                 return @"unknown";
  }
}

static NSString *TNSettingName(UNNotificationSetting setting)
{
  switch (setting) {
    case UNNotificationSettingNotSupported: return @"not supported";
    case UNNotificationSettingDisabled:     return @"disabled";
    case UNNotificationSettingEnabled:      return @"enabled";
    default:                                return @"unknown";
  }
}

static NSString *TNAlertStyleName(UNAlertStyle style)
{
  switch (style) {
    case UNAlertStyleNone:   return @"none";
    case UNAlertStyleBanner: return @"banners";
    case UNAlertStyleAlert:  return @"alerts (stay until dismissed)";
    default:                 return @"unknown";
  }
}

static NSString *TNPreviewsName(UNShowPreviewsSetting setting)
{
  switch (setting) {
    case UNShowPreviewsSettingAlways:           return @"always";
    case UNShowPreviewsSettingWhenAuthenticated: return @"when unlocked";
    case UNShowPreviewsSettingNever:            return @"never";
    default:                                    return @"unknown";
  }
}

@interface AppDelegate ()
@property (nonatomic) BOOL launchedFromNotification;
@property (nonatomic) BOOL awaitingAuthorization;
@property (nonatomic) BOOL awaitingResponse;
@property (nonatomic, strong) NSMutableArray *signalSources;
@end

@implementation AppDelegate

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
         "       -diagnose          Report why notifications may not be appearing, and exit.\n" \
         "       -message VALUE     The notification message.\n" \
         "       -remove ID         Removes a notification with the specified ‘group’ ID.\n" \
         "       -list ID           If the specified ‘group’ ID exists show when it was delivered,\n" \
         "                          or use ‘ALL’ as ID to see all notifications, or ‘PENDING’\n" \
         "                          for those scheduled with -in or -at that have not fired yet.\n" \
         "                          The output is a tab-separated list.\n"
         "\n" \
         "   Optional:\n" \
         "\n" \
         "       -title VALUE       The notification title. Defaults to ‘Terminal’.\n" \
         "       -subtitle VALUE    The notification subtitle.\n" \
         "       -sound NAME        The name of a sound to play when the notification appears. The names are listed\n" \
         "                          in /System/Library/Sounds. Use 'default' for the default notification sound.\n" \
         "       -timeSensitive     Request a Time Sensitive alert (macOS 12+ and a provisioned build).\n" \
         "                          Can pass through Focus when allowed; does not override mute.\n" \
         "                          Warns and delivers normally when unsupported or disabled.\n" \
         "       -group ID          A string which identifies the group the notifications belong to.\n" \
         "                          Old notifications with the same ID will be removed.\n" \
         "       -activate ID       The bundle identifier of the application to activate when the user clicks the notification.\n" \
         "       -contentImage PATH The path of an image to attach to the notification. Local files only.\n" \
         "       -open URL          The URL of a resource to open when the user clicks the notification.\n" \
         "       -execute COMMAND   A shell command to perform when the user clicks the notification.\n" \
         "       -action TITLE      Add an action button. Repeat the option, or pass a comma separated\n" \
         "                          list, for several. Waits for a response and prints the chosen title.\n" \
         "       -reply [PROMPT]    Add a text field to the notification. Waits and prints what was typed.\n" \
         "       -timeout SECONDS   How long to wait for a response to -action or -reply. Defaults to\n" \
         "                          waiting indefinitely. Prints @TIMEOUT and exits 6 if it expires.\n" \
         "       -in DURATION       Deliver after a delay instead of now, eg. 30s, 5m, 2h, 1d.\n" \
         "       -at TIME           Deliver at a clock time such as 09:15, meaning the next one, or at\n" \
         "                          a date such as '2026-09-01 02:00'. Cannot be combined with -in.\n" \
         "       -ignoreDnD         Legacy spelling of -timeSensitive, with the same restrictions.\n" \
         "\n" \
         "   Removed:\n" \
         "\n" \
         "       -sender ID         No longer supported. It worked by overriding this tool's own bundle\n" \
         "                          identifier, which the UserNotifications framework does not permit.\n" \
         "       -appIcon URL       No longer supported. macOS has no API to override a notification's icon;\n" \
         "                          the icon always comes from the app bundle. See the README for the\n" \
         "                          custom-bundle workaround.\n" \
         "\n" \
         "With -action or -reply the outcome is printed on stdout: the button title, the text\n" \
         "that was typed, or one of @ACTIONCLICKED, @CLOSED or @TIMEOUT.\n" \
         "\n" \
         "What -open, -execute and -activate did is written to the system log instead. Read it\n" \
         "with Console.app, or:  log show --predicate 'process == \"terminal-notifier\"' --last 5m\n" \
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

- (void)printDiagnostics;
{
  NSBundle *bundle = [NSBundle mainBundle];

  printf("terminal-notifier %s\n",
         [[bundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"] UTF8String]);
  printf("  bundle id           %s\n", [[bundle bundleIdentifier] UTF8String]);
  printf("  bundle path         %s\n", [[bundle bundlePath] UTF8String]);
  printf("  macOS               %s\n",
         [[[NSProcessInfo processInfo] operatingSystemVersionString] UTF8String]);

  BOOL notificationCentreRunning = NO;
  for (NSRunningApplication *app in [[NSWorkspace sharedWorkspace] runningApplications]) {
    if ([app.bundleIdentifier isEqualToString:@"com.apple.notificationcenterui"]) {
      notificationCentreRunning = YES;
      break;
    }
  }
  printf("  NotificationCenter  %s\n", notificationCentreRunning ? "running" : "NOT RUNNING");

  UNUserNotificationCenter *center = [UNUserNotificationCenter currentNotificationCenter];
  [center getNotificationSettingsWithCompletionHandler:^(UNNotificationSettings *settings) {
    dispatch_async(dispatch_get_main_queue(), ^{
      printf("\n");
      printf("  authorization       %s\n", [TNAuthorizationStatusName(settings.authorizationStatus) UTF8String]);
      printf("  alerts              %s\n", [TNSettingName(settings.alertSetting) UTF8String]);
      printf("  alert style         %s\n", [TNAlertStyleName(settings.alertStyle) UTF8String]);
      printf("  sounds              %s\n", [TNSettingName(settings.soundSetting) UTF8String]);
      printf("  notification centre %s\n", [TNSettingName(settings.notificationCenterSetting) UTF8String]);
      printf("  lock screen         %s\n", [TNSettingName(settings.lockScreenSetting) UTF8String]);
      printf("  previews            %s\n", [TNPreviewsName(settings.showPreviewsSetting) UTF8String]);
      printf("  critical alerts     %s\n", [TNSettingName(settings.criticalAlertSetting) UTF8String]);

      if (@available(macOS 12.0, *)) {
        printf("  time sensitive      %s\n", [TNSettingName(settings.timeSensitiveSetting) UTF8String]);
        printf("  scheduled delivery  %s\n", [TNSettingName(settings.scheduledDeliverySetting) UTF8String]);
        if (settings.authorizationStatus == UNAuthorizationStatusAuthorized ||
            settings.authorizationStatus == UNAuthorizationStatusProvisional) {
          NSString *warning = TNApplyTimeSensitive([UNMutableNotificationContent new], YES,
                                                  settings.timeSensitiveSetting);
          if (warning != nil) printf("  time sensitive note %s\n", [warning UTF8String]);
        }
      }

      NSMutableArray<NSString *> *problems = [NSMutableArray array];
      if (settings.authorizationStatus == UNAuthorizationStatusDenied) {
        [problems addObject:[NSString stringWithFormat:
          @"Notifications are turned off. Enable them in System Settings > Notifications,\n"
           "    or reset the permission with:\n"
           "      tccutil reset UserNotification %@\n"
           "    (the app bundle must still be installed for that command to resolve)",
          [bundle bundleIdentifier]]];
      }
      if (settings.authorizationStatus == UNAuthorizationStatusNotDetermined) {
        [problems addObject:@"Permission has never been requested. Send one notification and approve the prompt."];
      }
      if (settings.alertSetting == UNNotificationSettingDisabled) {
        [problems addObject:@"Alerts are disabled, so nothing will be shown on screen."];
      }
      if (settings.alertStyle == UNAlertStyleNone) {
        [problems addObject:@"Alert style is None. Set it to Banners or Alerts in System Settings > Notifications."];
      }
      if (settings.soundSetting == UNNotificationSettingDisabled) {
        [problems addObject:@"Sounds are disabled, so -sound will be silent."];
      }
      if (!notificationCentreRunning) {
        [problems addObject:@"NotificationCenter is not running. Try: killall NotificationCenter"];
      }
      if (@available(macOS 12.0, *)) {
        if (settings.scheduledDeliverySetting == UNNotificationSettingEnabled) {
          [problems addObject:@"Scheduled Summary is on, so notifications may be held back for a digest."];
        }
      }

      printf("\n");
      if (problems.count == 0) {
        printf("No problems found.\n");
      } else {
        printf("Problems found:\n");
        for (NSString *problem in problems) {
          printf("  - %s\n", [problem UTF8String]);
        }
      }

      exit(settings.authorizationStatus == UNAuthorizationStatusAuthorized ||
           settings.authorizationStatus == UNAuthorizationStatusProvisional
             ? TNExitSuccess : TNExitNotAuthorized);
    });
  }];
}

- (void)applicationWillFinishLaunching:(NSNotification *)notification;
{
  // Set before launching finishes, or a click response arrives unhandled.
  [UNUserNotificationCenter currentNotificationCenter].delegate = self;

  [self armWatchdog];
}

// Must not fire while the permission dialog is waiting on a human.
- (void)armWatchdog;
{
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(TNTimeoutSeconds * NSEC_PER_SEC)),
                 dispatch_get_main_queue(), ^{
    if (self.awaitingAuthorization || self.awaitingResponse) {
      [self armWatchdog];
      return;
    }
    TNError(@"Timed out after %.0f seconds waiting for the notification service.", TNTimeoutSeconds);
    TNError(@"This usually means no GUI session is available — for example when running over SSH,");
    TNError(@"or from launchd as root. Notifications can only be posted for a logged-in user.");
    exit(TNExitTimeout);
  });
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification;
{
  NSArray *arguments = [[NSProcessInfo processInfo] arguments];

  if ([arguments containsObject:@"-help"]) {
    [self printHelpBanner];
    exit(TNExitSuccess);
  }

  if ([arguments containsObject:@"-version"]) {
    [self printVersion];
    exit(TNExitSuccess);
  }

  if ([arguments containsObject:@"-diagnose"] || [arguments containsObject:@"--diagnose"]) {
    [self printDiagnostics];
    return; // exits from the completion handler
  }

  if (self.launchedFromNotification) return;

  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

  NSString *subtitle = defaults[@"subtitle"];
  NSString *message  = defaults[@"message"];
  NSString *remove   = defaults[@"remove"];
  NSString *list     = defaults[@"list"];
  NSString *sound    = defaults[@"sound"];
  NSString *title    = defaults[@"title"] ?: @"Terminal";

  // A -message NSUserDefaults could not parse arrives as nil, which looks like
  // no -message at all unless we check argv.
  if (message == nil && [arguments containsObject:@"-message"]) {
    TNError(@"Could not read the -message value.");
    TNError(@"If it begins with a character such as '[', '(', '{' or a quote, escape it:");
    TNError(@"  -message '\\[like this'");
    exit(TNExitBadArgument);
  }

  // If there is no message and data is piped to the application, use that
  // instead.
  if (message == nil && remove == nil && list == nil && !isatty(STDIN_FILENO)) {
    NSData *inputData = [[NSFileHandle fileHandleWithStandardInput] readDataToEndOfFile];
    message = [[NSString alloc] initWithData:inputData encoding:NSUTF8StringEncoding];
    // Drop the trailing newline a pipe carries, or it splits the -list row.
    while ([message hasSuffix:@"\n"] || [message hasSuffix:@"\r"]) {
      message = [message substringToIndex:message.length - 1];
    }
  }

  if (message == nil && remove == nil && list == nil) {
    [self printHelpBanner];
    exit(TNExitUsage);
  }

  if (defaults[@"sender"]) {
    TNError(@"[!] -sender is no longer supported and will be ignored.");
    TNError(@"    It relied on overriding this tool's bundle identifier, which the");
    TNError(@"    UserNotifications framework does not allow.");
  }
  if (defaults[@"appIcon"]) {
    TNError(@"[!] -appIcon is no longer supported and will be ignored.");
    TNError(@"    macOS provides no API to override a notification's icon; it always");
    TNError(@"    comes from the app bundle. See the README for the workaround.");
  }

  if (list) {
    [self listNotificationWithGroupID:list];
    return; // exits from the completion handler
  }

  NSMutableDictionary *options = [NSMutableDictionary dictionary];
  if (defaults[@"activate"])     options[@"bundleID"]     = defaults[@"activate"];
  if (defaults[@"group"])        options[@"groupID"]      = defaults[@"group"];
  if (defaults[@"execute"])      options[@"command"]      = defaults[@"execute"];
  if (defaults[@"contentImage"]) options[@"contentImage"] = defaults[@"contentImage"];

  if (defaults[@"open"]) {
    NSURL *url = [NSURL URLWithString:defaults[@"open"]];
    if (url != nil && url.scheme.length > 0) {
      options[@"open"] = defaults[@"open"];
    } else {
      TNError(@"'%@' is not a valid URL.", defaults[@"open"]);
      TNError(@"It needs a scheme, such as https://example.com or file:///tmp.");
      exit(TNExitBadArgument);
    }
  }

  if (TNTimeSensitiveRequested(arguments)) {
    options[@"timeSensitive"] = @YES;
  }

  NSMutableArray<NSString *> *actionTitles = [NSMutableArray array];
  for (NSUInteger i = 0; i + 1 < arguments.count; i++) {
    if (![arguments[i] isEqualToString:@"-action"]) continue;
    for (NSString *title in [arguments[i + 1] componentsSeparatedByString:@","]) {
      NSString *trimmed = [title stringByTrimmingCharactersInSet:
                             [NSCharacterSet whitespaceCharacterSet]];
      if (trimmed.length > 0) [actionTitles addObject:trimmed];
    }
  }
  if (actionTitles.count > 0) options[@"actions"] = actionTitles;

  // -reply works with or without a placeholder, so it is read from argv.
  if ([arguments containsObject:@"-reply"]) {
    options[@"reply"] = @YES;
    NSString *placeholder = defaults[@"reply"];
    if (placeholder != nil && ![placeholder hasPrefix:@"-"]) {
      options[@"replyPlaceholder"] = placeholder;
    }
  }

  if (defaults[@"timeout"]) {
    NSTimeInterval seconds = [defaults[@"timeout"] doubleValue];
    if (seconds <= 0) {
      TNError(@"-timeout expects a positive number of seconds.");
      exit(TNExitBadArgument);
    }
    options[@"timeout"] = @(seconds);
  }

  // A value beginning with '-' is read as the next flag and arrives as nil,
  // which would deliver the notification now instead of when it was asked for.
  for (NSString *option in @[@"-in", @"-at"]) {
    NSString *key = [option substringFromIndex:1];
    if (defaults[key] == nil && [arguments containsObject:option]) {
      TNError(@"Could not read the %@ value.", option);
      TNError(@"A value starting with '-' is read as the next option. Quote it with a");
      TNError(@"leading space if you meant it literally.");
      exit(TNExitBadArgument);
    }
  }

  if (defaults[@"in"] && defaults[@"at"]) {
    TNError(@"-in and -at cannot be combined. Use one or the other.");
    exit(TNExitBadArgument);
  }

  if (defaults[@"in"] || defaults[@"at"]) {
    // The response can only be printed while this process is still alive.
    if (options[@"actions"] || options[@"reply"]) {
      TNError(@"-action and -reply cannot be scheduled.");
      TNError(@"terminal-notifier has to stay running to report the response, and a");
      TNError(@"scheduled notification fires long after it has exited.");
      exit(TNExitBadArgument);
    }

    UNNotificationTrigger *trigger = nil;

    if (defaults[@"in"]) {
      NSTimeInterval seconds = 0;
      if (!TNParseDuration(defaults[@"in"], &seconds)) {
        TNError(@"'%@' is not a duration.", defaults[@"in"]);
        TNError(@"Expected a positive number of seconds, or one of 30s, 5m, 2h, 1d.");
        exit(TNExitBadArgument);
      }
      trigger = [UNTimeIntervalNotificationTrigger triggerWithTimeInterval:seconds
                                                                   repeats:NO];
    } else {
      NSDateComponents *dateComponents = nil;
      if (!TNParseTriggerDate(defaults[@"at"], &dateComponents)) {
        TNError(@"'%@' is not a time.", defaults[@"at"]);
        TNError(@"Expected a clock time such as 09:15, or a date such as '2026-09-01 02:00'.");
        exit(TNExitBadArgument);
      }
      trigger = [UNCalendarNotificationTrigger triggerWithDateMatchingComponents:dateComponents
                                                                         repeats:NO];

      // A date that has gone by has no next match. A bare clock time always
      // has one, so this only rejects the dated form.
      if (TNNextTriggerDate(trigger) == nil) {
        TNError(@"'%@' has already passed.", defaults[@"at"]);
        exit(TNExitBadArgument);
      }
    }

    options[@"trigger"] = trigger;
  }

  BOOL hasMessage = (message != nil && message.length > 0);

  if (remove) {
    // Removal is asynchronous, so deliver inside the completion handler or
    // `-remove X -message Y -group X` deletes what it just posted.
    [self removeNotificationWithGroupID:remove completionHandler:^{
      if (!hasMessage) exit(TNExitSuccess);
      [self deliverNotificationWithTitle:title
                               subtitle:subtitle
                                message:message
                                options:options
                                  sound:sound];
    }];
    return;
  }

  if (hasMessage) {
    [self deliverNotificationWithTitle:title
                             subtitle:subtitle
                              message:message
                              options:options
                                sound:sound];
  } else if (arguments.count == 1) {
    [self waitForNotificationResponse];
  } else {
    [self printHelpBanner];
    exit(TNExitUsage);
  }
}

- (void)waitForNotificationResponse;
{
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(TNResponseGraceSeconds * NSEC_PER_SEC)),
                 dispatch_get_main_queue(), ^{
    if (self.launchedFromNotification) return; // handled; that path exits itself
    [self printHelpBanner];
    exit(TNExitUsage);
  });
}

- (NSURL *)localFileURLFromString:(NSString *)urlString;
{
  NSURL *url = [NSURL URLWithString:urlString];
  if ([[url scheme] length] == 0) {
    url = [NSURL fileURLWithPath:urlString];
  }
  return url;
}

- (void)withAuthorization:(void (^)(UNNotificationSettings *settings))block;
{
  UNUserNotificationCenter *center = [UNUserNotificationCenter currentNotificationCenter];

  [center getNotificationSettingsWithCompletionHandler:^(UNNotificationSettings *settings) {
    switch (settings.authorizationStatus) {
      case UNAuthorizationStatusAuthorized:
      case UNAuthorizationStatusProvisional: {
        dispatch_async(dispatch_get_main_queue(), ^{ block(settings); });
        break;
      }

      case UNAuthorizationStatusDenied:
        TNError(@"Notifications are turned off for this application.");
        TNError(@"Enable them in System Settings > Notifications, or reset the");
        TNError(@"permission so it can be asked for again:");
        TNError(@"  tccutil reset UserNotification %@", [[NSBundle mainBundle] bundleIdentifier]);
        exit(TNExitNotAuthorized);
        break;

      case UNAuthorizationStatusNotDetermined:
      default: {
        UNAuthorizationOptions opts = UNAuthorizationOptionAlert | UNAuthorizationOptionSound;
        // macOS is about to ask; the watchdog stands down until they answer.
        self.awaitingAuthorization = YES;
        [center requestAuthorizationWithOptions:opts
                              completionHandler:^(BOOL granted, NSError *error) {
          self.awaitingAuthorization = NO;
          if (error) {
            TNError(@"Could not request notification permission: %@", error.localizedDescription);
            exit(TNExitNotAuthorized);
          }
          if (!granted) {
            TNError(@"Permission to send notifications was declined.");
            TNError(@"Grant it in System Settings > Notifications, then try again.");
            exit(TNExitNotAuthorized);
          }
          // Read the settings again after consent, including the app's Time
          // Sensitive setting. Ordinary deliveries still need only one query.
          [center getNotificationSettingsWithCompletionHandler:^(UNNotificationSettings *updated) {
            dispatch_async(dispatch_get_main_queue(), ^{ block(updated); });
          }];
        }];
        break;
      }
    }
  }];
}

- (void)deliverNotificationWithTitle:(NSString *)title
                            subtitle:(NSString *)subtitle
                             message:(NSString *)message
                             options:(NSDictionary *)options
                               sound:(NSString *)sound;
{
  [self withAuthorization:^(UNNotificationSettings *settings) {
    UNUserNotificationCenter *center = [UNUserNotificationCenter currentNotificationCenter];

    UNMutableNotificationContent *content = [UNMutableNotificationContent new];
    content.title = title;
    if (subtitle) content.subtitle = subtitle;
    content.body = message;

    if (sound != nil) {
      content.sound = [sound isEqualToString:@"default"]
        ? [UNNotificationSound defaultSound]
        : [UNNotificationSound soundNamed:sound];
    }

    NSString *groupID = options[@"groupID"];
    if (groupID) content.threadIdentifier = groupID;

    // Buttons only exist as part of a category, registered before the request.
    NSArray<NSString *> *actionTitles = options[@"actions"];
    BOOL wantsReply = [options[@"reply"] boolValue];
    BOOL interactive = (actionTitles.count > 0 || wantsReply);

    if (interactive) {
      NSMutableArray<UNNotificationAction *> *actions = [NSMutableArray array];

      if (wantsReply) {
        NSString *placeholder = options[@"replyPlaceholder"] ?: @"";
        [actions addObject:
          [UNTextInputNotificationAction actionWithIdentifier:TNReplyActionIdentifier
                                                        title:@"Reply"
                                                      options:UNNotificationActionOptionNone
                                         textInputButtonTitle:@"Send"
                                         textInputPlaceholder:placeholder]];
      }

      // The identifier is the index, so the title comes back from userInfo.
      [actionTitles enumerateObjectsUsingBlock:^(NSString *title, NSUInteger i, BOOL *stop) {
        [actions addObject:
          [UNNotificationAction actionWithIdentifier:[NSString stringWithFormat:@"action-%lu", (unsigned long)i]
                                               title:title
                                             options:UNNotificationActionOptionNone]];
      }];

      UNNotificationCategory *category =
        [UNNotificationCategory categoryWithIdentifier:TNCategoryIdentifier
                                              actions:actions
                                    intentIdentifiers:@[]
                                              options:UNNotificationCategoryOptionCustomDismissAction];
      [center setNotificationCategories:[NSSet setWithObject:category]];
      content.categoryIdentifier = TNCategoryIdentifier;
    }

    UNNotificationSetting timeSensitive = UNNotificationSettingNotSupported;
    if (@available(macOS 12.0, *)) timeSensitive = settings.timeSensitiveSetting;
    NSString *warning = TNApplyTimeSensitive(content, [options[@"timeSensitive"] boolValue],
                                            timeSensitive);
    if (warning != nil) TNError(@"%@ Delivering a normal alert.", warning);

    if (options[@"contentImage"]) {
      NSURL *imageURL = [self localFileURLFromString:options[@"contentImage"]];
      if (![imageURL isFileURL]) {
        TNError(@"[!] -contentImage only accepts local file paths.");
      } else if (![[NSFileManager defaultManager] fileExistsAtPath:[imageURL path]]) {
        // Checked up front, or an unreadable path fails the whole delivery.
        TNError(@"[!] Could not attach '%@': no such file.", options[@"contentImage"]);
      } else {
        // UNNotificationAttachment moves the file into the notification store,
        // which would delete the caller's image. Give it a throwaway copy.
        NSFileManager *files = [NSFileManager defaultManager];
        NSString *extension = [imageURL pathExtension];
        NSString *name = [NSString stringWithFormat:@"terminal-notifier-%@%@",
                          [[NSUUID UUID] UUIDString],
                          extension.length > 0 ? [@"." stringByAppendingString:extension] : @""];
        NSURL *copyURL = [NSURL fileURLWithPath:
                           [NSTemporaryDirectory() stringByAppendingPathComponent:name]];

        NSError *copyError = nil;
        if (![files copyItemAtURL:imageURL toURL:copyURL error:&copyError]) {
          TNError(@"[!] Could not attach '%@': %@",
                  options[@"contentImage"], copyError.localizedDescription);
        } else {
          NSError *attachError = nil;
          UNNotificationAttachment *attachment =
            [UNNotificationAttachment attachmentWithIdentifier:@"contentImage"
                                                          URL:copyURL
                                                      options:nil
                                                        error:&attachError];
          if (attachment) {
            content.attachments = @[attachment];
          } else {
            TNError(@"[!] Could not attach '%@': %@",
                    options[@"contentImage"], attachError.localizedDescription);
            // The copy was not consumed, so clean it up ourselves.
            [files removeItemAtURL:copyURL error:NULL];
          }
        }
      }
    }

    NSMutableDictionary *userInfo = [NSMutableDictionary dictionary];
    if (options[@"bundleID"]) userInfo[@"bundleID"] = options[@"bundleID"];
    if (groupID)              userInfo[@"groupID"]  = groupID;
    if (options[@"command"])  userInfo[@"command"]  = options[@"command"];
    if (options[@"open"])     userInfo[@"open"]     = options[@"open"];
    if (actionTitles)         userInfo[@"actions"]  = actionTitles;
    content.userInfo = userInfo;

    // Reusing an identifier replaces an earlier notification, so only with a group.
    NSString *identifier = groupID ?: [[NSUUID UUID] UUIDString];

    if (groupID) {
      [center removeDeliveredNotificationsWithIdentifiers:@[identifier]];
      [center removePendingNotificationRequestsWithIdentifiers:@[identifier]];
    }

    UNNotificationRequest *request =
      [UNNotificationRequest requestWithIdentifier:identifier
                                           content:content
                                           trigger:options[@"trigger"]];

    [center addNotificationRequest:request withCompletionHandler:^(NSError *error) {
      if (error) {
        TNError(@"Failed to deliver notification: %@", error.localizedDescription);
        if ([error.domain isEqualToString:UNErrorDomain] &&
            error.code == UNErrorCodeNotificationsNotAllowed) {
          TNError(@"Run with -diagnose to see why.");
          exit(TNExitNotAuthorized);
        }
        exit(TNExitDeliveryFailed);
      }
      if (interactive) {
        // stdout reaches the caller only while this process lives.
        self.awaitingResponse = YES;
        [self withdrawOnInterrupt:identifier];

        NSNumber *timeout = options[@"timeout"];
        if (timeout != nil) {
          dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                                       (int64_t)(timeout.doubleValue * NSEC_PER_SEC)),
                         dispatch_get_main_queue(), ^{
            // Withdraw it before giving up, or it keeps buttons nothing is
            // listening to. Ask for the centre again rather than capturing it:
            // capturing it here would retain the block that owns this one.
            [[UNUserNotificationCenter currentNotificationCenter]
              removeDeliveredNotificationsWithIdentifiers:@[identifier]];
            // The removal takes no completion handler, so let it land first.
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
              [self reportResponse:TNResponseTimeout andExit:TNExitNoResponse];
            });
          });
        }
        return;
      }

      // On stderr, so stdout keeps meaning the interactive response.
      NSDate *fireDate = TNNextTriggerDate(options[@"trigger"]);
      if (fireDate != nil) {
        fprintf(stderr, "* Notification scheduled for: %s\n",
                [[fireDate description] UTF8String]);
      }

      exit(TNExitSuccess);
    }];
  }];
}

- (void)removeNotificationWithGroupID:(NSString *)groupID
                    completionHandler:(void (^)(void))completionHandler;
{
  UNUserNotificationCenter *center = [UNUserNotificationCenter currentNotificationCenter];

  // Two stores, two queries. The callback must not run until both are swept,
  // or `-remove X -message Y -group X` deletes what it just posted.
  dispatch_group_t group = dispatch_group_create();

  dispatch_group_enter(group);
  [center getDeliveredNotificationsWithCompletionHandler:^(NSArray<UNNotification *> *notifications) {
    NSMutableArray<NSString *> *identifiers = [NSMutableArray array];

    for (UNNotification *notification in notifications) {
      NSString *deliveredGroupID = notification.request.content.userInfo[@"groupID"];
      if ([@"ALL" isEqualToString:groupID] || [deliveredGroupID isEqualToString:groupID]) {
        fprintf(stderr, "* Removing previously sent notification, which was sent on: %s\n",
                [[notification.date description] UTF8String]);
        [identifiers addObject:notification.request.identifier];
      }
    }

    if (identifiers.count > 0) {
      [center removeDeliveredNotificationsWithIdentifiers:identifiers];
    }
    dispatch_group_leave(group);
  }];

  dispatch_group_enter(group);
  [center getPendingNotificationRequestsWithCompletionHandler:^(NSArray<UNNotificationRequest *> *requests) {
    NSMutableArray<NSString *> *identifiers = [NSMutableArray array];

    for (UNNotificationRequest *request in requests) {
      NSString *pendingGroupID = request.content.userInfo[@"groupID"];
      if ([@"ALL" isEqualToString:groupID] || [pendingGroupID isEqualToString:groupID]) {
        NSDate *fireDate = TNNextTriggerDate(request.trigger);
        fprintf(stderr, "* Cancelling scheduled notification, which was due on: %s\n",
                [[(fireDate ?: [NSDate date]) description] UTF8String]);
        [identifiers addObject:request.identifier];
      }
    }

    if (identifiers.count > 0) {
      [center removePendingNotificationRequestsWithIdentifiers:identifiers];
    }
    dispatch_group_leave(group);
  }];

  dispatch_group_notify(group, dispatch_get_main_queue(), ^{
    if (completionHandler) completionHandler();
  });
}

- (void)listNotificationWithGroupID:(NSString *)listGroupID;
{
  if ([@"PENDING" isEqualToString:listGroupID]) {
    [self listPendingNotifications];
    return;
  }

  UNUserNotificationCenter *center = [UNUserNotificationCenter currentNotificationCenter];

  [center getDeliveredNotificationsWithCompletionHandler:^(NSArray<UNNotification *> *notifications) {
    NSMutableArray<NSString *> *lines = [NSMutableArray array];

    for (UNNotification *notification in notifications) {
      UNNotificationContent *content = notification.request.content;
      NSString *deliveredGroupID = content.userInfo[@"groupID"];

      if (![@"ALL" isEqualToString:listGroupID] && ![deliveredGroupID isEqualToString:listGroupID]) {
        continue;
      }

      [lines addObject:TNListRow(content, [notification.date description])];
    }

    [self printListRows:lines lastColumn:@"Delivered At"];
  }];
}

- (void)listPendingNotifications;
{
  UNUserNotificationCenter *center = [UNUserNotificationCenter currentNotificationCenter];

  [center getPendingNotificationRequestsWithCompletionHandler:^(NSArray<UNNotificationRequest *> *requests) {
    // The centre returns these in no useful order.
    NSArray<UNNotificationRequest *> *sorted =
      [requests sortedArrayUsingComparator:^NSComparisonResult(UNNotificationRequest *a,
                                                               UNNotificationRequest *b) {
        NSDate *left  = TNNextTriggerDate(a.trigger) ?: [NSDate distantFuture];
        NSDate *right = TNNextTriggerDate(b.trigger) ?: [NSDate distantFuture];
        return [left compare:right];
      }];

    NSMutableArray<NSString *> *lines = [NSMutableArray array];
    for (UNNotificationRequest *request in sorted) {
      NSDate *fireDate = TNNextTriggerDate(request.trigger);
      [lines addObject:TNListRow(request.content, fireDate ? [fireDate description] : @"")];
    }

    [self printListRows:lines lastColumn:@"Scheduled For"];
  }];
}

- (void)printListRows:(NSArray<NSString *> *)lines lastColumn:(NSString *)heading;
{
  dispatch_async(dispatch_get_main_queue(), ^{
    if (lines.count > 0) {
      printf("GroupID\tTitle\tSubtitle\tMessage\t%s\n", [heading UTF8String]);
      for (NSString *line in lines) {
        printf("%s\n", [line UTF8String]);
      }
    }
    exit(TNExitSuccess);
  });
}

- (void)withdrawOnInterrupt:(NSString *)identifier;
{
  self.signalSources = [NSMutableArray array];

  for (NSNumber *number in @[@(SIGINT), @(SIGTERM), @(SIGHUP)]) {
    int signalNumber = number.intValue;
    // The dispatch source only fires if the default disposition is suppressed.
    signal(signalNumber, SIG_IGN);

    dispatch_source_t source = dispatch_source_create(
        DISPATCH_SOURCE_TYPE_SIGNAL, signalNumber, 0, dispatch_get_main_queue());
    dispatch_source_set_event_handler(source, ^{
      [[UNUserNotificationCenter currentNotificationCenter]
        removeDeliveredNotificationsWithIdentifiers:@[identifier]];
      // Let the removal reach the notification service before we go.
      dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)),
                     dispatch_get_main_queue(), ^{ exit(TNExitNoResponse); });
    });
    dispatch_resume(source);
    [self.signalSources addObject:source];
  }
}

- (void)reportResponse:(NSString *)text andExit:(int)status;
{
  printf("%s\n", [text UTF8String]);
  fflush(stdout);
  exit(status);
}

// Maps a response onto a single line of stdout. Returns NO when the
// notification was not interactive, so the caller runs the click action.
- (BOOL)reportInteractiveResponse:(UNNotificationResponse *)response;
{
  NSString *actionIdentifier = response.actionIdentifier;

  if ([response isKindOfClass:[UNTextInputNotificationResponse class]]) {
    [self reportResponse:[(UNTextInputNotificationResponse *)response userText]
                 andExit:TNExitSuccess];
    return YES;
  }

  if ([actionIdentifier isEqualToString:UNNotificationDismissActionIdentifier]) {
    [self reportResponse:TNResponseClosed andExit:TNExitSuccess];
    return YES;
  }

  if ([actionIdentifier hasPrefix:@"action-"]) {
    NSArray<NSString *> *titles = response.notification.request.content.userInfo[@"actions"];
    NSUInteger index = (NSUInteger)[[actionIdentifier substringFromIndex:7] integerValue];
    NSString *title = (index < titles.count) ? titles[index] : actionIdentifier;
    [self reportResponse:title andExit:TNExitSuccess];
    return YES;
  }

  // The body was clicked; only reportable when the notification was interactive.
  if ([actionIdentifier isEqualToString:UNNotificationDefaultActionIdentifier] &&
      self.awaitingResponse) {
    NSDictionary *userInfo = response.notification.request.content.userInfo;
    BOOL hasClickAction = userInfo[@"bundleID"] || userInfo[@"command"] || userInfo[@"open"];
    if (!hasClickAction) {
      [self reportResponse:TNResponseClicked andExit:TNExitSuccess];
      return YES;
    }
  }

  return NO;
}

- (void)userActivatedNotification:(UNNotificationResponse *)response;
{
  if ([self reportInteractiveResponse:response]) return;

  self.launchedFromNotification = YES;

  UNNotificationContent *content = response.notification.request.content;
  NSDictionary *userInfo = content.userInfo;

  NSString *groupID  = userInfo[@"groupID"];
  NSString *bundleID = userInfo[@"bundleID"];
  NSString *command  = userInfo[@"command"];
  NSString *open     = userInfo[@"open"];

  [[UNUserNotificationCenter currentNotificationCenter]
    removeDeliveredNotificationsWithIdentifiers:@[response.notification.request.identifier]];

  NSLog(@"User activated notification:");
  NSLog(@" group ID: %@", groupID);
  NSLog(@"    title: %@", content.title);
  NSLog(@" subtitle: %@", content.subtitle);
  NSLog(@"  message: %@", content.body);
  NSLog(@"bundle ID: %@", bundleID);
  NSLog(@"  command: %@", command);
  NSLog(@"     open: %@", open);

  BOOL success = YES;
  if (bundleID) success &= [self activateAppWithBundleID:bundleID];
  if (command)  success &= [self executeShellCommand:command];
  if (open)     success &= [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:open]];

  exit(success ? TNExitSuccess : TNExitDeliveryFailed);
}

- (BOOL)activateAppWithBundleID:(NSString *)bundleID;
{
  // Not ScriptingBridge: Apple events need an Automation TCC grant
  // terminal-notifier never asks for.
  NSArray<NSRunningApplication *> *running =
    [NSRunningApplication runningApplicationsWithBundleIdentifier:bundleID];

  if (running.count > 0) {
    return [running.firstObject activateWithOptions:NSApplicationActivateIgnoringOtherApps];
  }

  NSWorkspace *workspace = [NSWorkspace sharedWorkspace];
  NSURL *appURL = [workspace URLForApplicationWithBundleIdentifier:bundleID];
  if (appURL == nil) {
    TNError(@"Unable to find an application with bundle identifier '%@'.", bundleID);
    return NO;
  }

  if (@available(macOS 11.0, *)) {
    NSWorkspaceOpenConfiguration *configuration = [NSWorkspaceOpenConfiguration configuration];
    configuration.activates = YES;
    [workspace openApplicationAtURL:appURL configuration:configuration completionHandler:nil];
    return YES;
  }
  return [workspace launchApplication:[appURL path]];
}

- (BOOL)executeShellCommand:(NSString *)command;
{
  NSPipe *pipe = [NSPipe pipe];

  NSTask *task = [NSTask new];
  task.executableURL = [NSURL fileURLWithPath:@"/bin/sh"];
  task.arguments = @[@"-c", command];
  task.standardOutput = pipe;
  task.standardError = pipe;

  NSError *launchError = nil;
  if (![task launchAndReturnError:&launchError]) {
    TNError(@"Failed to run command: %@", launchError.localizedDescription);
    return NO;
  }

  // Drain the pipe fully before waiting, or a chatty command deadlocks.
  NSData *output = [[pipe fileHandleForReading] readDataToEndOfFile];
  [task waitUntilExit];

  NSString *outputString = [[NSString alloc] initWithData:output encoding:NSUTF8StringEncoding];
  NSLog(@"command output: %@", outputString);

  return [task terminationStatus] == 0;
}

#pragma mark - UNUserNotificationCenterDelegate

- (void)userNotificationCenter:(UNUserNotificationCenter *)center
       willPresentNotification:(UNNotification *)notification
         withCompletionHandler:(void (^)(UNNotificationPresentationOptions))completionHandler;
{
  UNNotificationPresentationOptions options;
  if (@available(macOS 11.0, *)) {
    options = UNNotificationPresentationOptionBanner
            | UNNotificationPresentationOptionList
            | UNNotificationPresentationOptionSound;
  } else {
    options = UNNotificationPresentationOptionAlert
            | UNNotificationPresentationOptionSound;
  }
  completionHandler(options);
}

- (void)userNotificationCenter:(UNUserNotificationCenter *)center
didReceiveNotificationResponse:(UNNotificationResponse *)response
         withCompletionHandler:(void (^)(void))completionHandler;
{
  completionHandler();
  [self userActivatedNotification:response];
}

@end
