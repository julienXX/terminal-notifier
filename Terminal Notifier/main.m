#import "AppDelegate.h"

AppDelegate *appDelegate ;

void SIGTERM_handler(int signum) {
  [appDelegate bye];
  exit(EXIT_FAILURE);
}

int main(int argc, char *argv[])
{
  signal(SIGTERM, SIGTERM_handler);
  signal(SIGINT, SIGTERM_handler);

  NSApplication *application = [NSApplication sharedApplication];
  appDelegate = [AppDelegate new];

  [application setDelegate:appDelegate];
  [application run];

  return EXIT_SUCCESS;
}
