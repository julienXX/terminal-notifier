# terminal-notifier

terminal-notifier is a command-line tool to send Mac OS X User Notifications,
which are available in Mac OS X 10.8.

It is currently packaged as an application bundle, because `NSUserNotification`
does not work from a ‘Foundation tool’. [radar://11956694](radar://11956694)

This tool will be used by [Kicker](https://github.com/alloy/kicker) to show the
status of commands which are executed due to filesystem changes. (v3.0.0)


## Download

Prebuilt binaries, which are code-signed and ready to use, are available from
the [downloads section](https://github.com/alloy/terminal-notifier/downloads).


## Usage

```
$ ./terminal-notifier.app/Contents/MacOS/terminal-notifier group-ID sender-name message [bundle-ID]
```

In order to use terminal-notifier, you have to call the binary _inside_ the app
bundle.

The first argument specifies the ‘group’ a notification belongs to. For
any ‘group’ only _one_ notification will ever be shown, replacing
previously posted notifications. Examples are: the sender’s process ID to
scope the notifications by a unique process, or the current working directory
to scope notifications by a project.

The second and third arguments describe the notification itself and are its
‘title’ and ‘message’ respectively. For example, to communicate the sender of
a notification to the user, you could specify the sender’s name as the title.

The fourth and last argument is an optional one. It specifies which application
should be activated when the user clicks the notification. By default this will
activate Terminal.app, to launch another application instead specify the
application’s bundle identifier. For example, to launch Safari.app use:
`com.apple.Safari`.


## License

All the works are available under the MIT license. **Except** for
‘Terminal.icns’, which is a copy of Apple’s Terminal.app icon and as such is
copyright of Apple.

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
