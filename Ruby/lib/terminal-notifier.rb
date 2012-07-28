module TerminalNotifier
  BIN_PATH = File.expand_path('../../vendor/terminal-notifier/terminal-notifier.app/Contents/MacOS/terminal-notifier', __FILE__)

  # Returns wether or not the current platform is Mac OS X 10.8, or higher.
  def self.available?
    if @available.nil?
      @available = `uname`.strip == 'Darwin' && `sw_vers -productVersion`.strip >= '10.8'
    end
    @available
  end

  # Executes the `terminal-notifier` tool through Kernel::system while
  # redirecting output to `/dev/null`.
  def self.silent_execute(options)
    stdout = STDOUT.clone
    STDOUT.reopen(File.new('/dev/null', 'w'))
    system(BIN_PATH, *options)
  ensure
    STDOUT.reopen(stdout)
  end

  # Sends a User Notification and returns wether or not it was a success.
  #
  # The available options are `:title`, `:group`, `:activate`, `:open`, and
  # `:execute`. For a description of each option see:
  #
  #   https://github.com/alloy/terminal-notifier/blob/master/README.markdown
  #
  # Examples are:
  #
  #   TerminalNotifier.notify('Hello World')
  #   TerminalNotifier.notify('Hello World', :title => 'Ruby')
  #   TerminalNotifier.notify('Hello World', :group => Process.pid)
  #   TerminalNotifier.notify('Hello World', :activate => 'com.apple.Safari')
  #   TerminalNotifier.notify('Hello World', :open => 'http://twitter.com/alloy')
  #   TerminalNotifier.notify('Hello World', :execute => 'say "OMG"')
  #
  # Raises if not supported on the current platform.
  def notify(message, options = {})
    if TerminalNotifier.available?
      TerminalNotifier.silent_execute(options.merge(:message => message).map { |k,v| ["-#{k}", v.to_s] }.flatten)
    else
      raise "terminal-notifier is only supported on Mac OS X 10.8, or higher."
    end
  end
  module_function :notify
end
