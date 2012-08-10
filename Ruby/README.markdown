# TerminalNotifier

A simple Ruby wrapper around the [`terminal-notifier`][HOMEPAGE] command-line
tool, which allows you to send User Notifications to the Notification Center on
Mac OS X 10.8, or higher.


## Installation

```
$ gem install terminal-notifier
```


## Usage

For full information on all the options, see the tool’s [README][README].

Examples are:

```ruby
TerminalNotifier.notify('Hello World')
TerminalNotifier.notify('Hello World', :title => 'Ruby', :subtitle => 'Programming Language')
TerminalNotifier.notify('Hello World', :activate => 'com.apple.Safari')
TerminalNotifier.notify('Hello World', :open => 'http://twitter.com/alloy')
TerminalNotifier.notify('Hello World', :execute => 'say "OMG"')
TerminalNotifier.notify('Hello World', :group => Process.pid)

TerminalNotifier.remove(Process.pid)

TerminalNotifier.list(Process.pid)
TerminalNotifier.list
```


## License

All the works are available under the MIT license. **Except** for
‘Terminal.icns’, which is a copy of Apple’s Terminal.app icon and as such is
copyright of Apple.

See [LICENSE][LICENSE] for details.

[HOMEPAGE]: https://github.com/alloy/terminal-notifier
[README]: https://github.com/alloy/terminal-notifier/blob/master/README.markdown
[LICENSE]: https://github.com/alloy/terminal-notifier/blob/master/Ruby/LICENSE
