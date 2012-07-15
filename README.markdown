# terminal-notifier

terminal-notifier is a command-line tool to send OS X User Notifications, which
are available starting Mac OS X 10.8.

It is currently packaged as an application bundle, because `NSUserNotification`
does not work from a ‘Foundation tool’. If you figure out a way to make this
work, please send a pull-request.

This tool is used by [Kicker](https://github.com/alloy/kicker) to show the
status of commands being executed due to filesystem changes.


## Download

Prebuilt binaries, which are code-signed and ready to use, are available from
the [downloads section](https://github.com/alloy/terminal-notifier/downloads).


## Usage

In order to use terminal-notifier, you have to call the binary _inside_ the app
bundle. E.g.:

```
$ ./terminal-notifier.app/Contents/MacOS/terminal-notifier
```

The arguments required are shown by the tool. Here is a copy of the output:

```
Usage: terminal-notifier sender-ID sender-name message [bundle-ID]

    sender-ID   A string which identifies the group the notifications belong to.
                Old notifications with the same ID will be removed.
  sender-name   The name of the application which is used as the notification’s title.
      message   The message that is shown in the notification.
    bundle-ID   The bundle identifier of the application to activate when the user
                activates (clicks) a notification. Defaults to `com.apple.Terminal'.

When the user activates a notification, the results are logged to the system logs.
Use Console.app to view these logs.
```


## License

All the works are available under the MIT license.

**Except** for `Terminal.icns`, which is a copy of Apple’s Terminal.app icon.

Copyright (C) 2012 Eloy Durán <eloy.de.enige@gmail.com>

Permission is hereby granted, free of charge, to any person obtaining a copy of
this software and associated documentation files (the "Software"), to deal in
the Software without restriction, including without limitation the rights to
use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies
of the Software, and to permit persons to whom the Software is furnished to do
so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
