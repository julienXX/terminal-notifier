module TerminalNotifier
  BIN_PATH = File.expand_path('../../vendor/terminal-notifier/terminal-notifier.app/Contents/MacOS/terminal-notifier', __FILE__)

  # Returns wether or not the current platform is Mac OS X 10.8, or higher.
  def self.available?
    if @available.nil?
      @available = `uname`.strip == 'Darwin' && `sw_vers -productVersion`.strip >= '10.8'
    end
    @available
  end

  def self.silence_stdout
    stdout = STDOUT.clone
    STDOUT.reopen(File.new('/dev/null', 'w'))
    yield
  ensure
    STDOUT.reopen(stdout)
  end

  def self.execute_with_options(options)
    execute(options.map { |k,v| ["-#{k}", v.to_s] }.flatten)
  end

  def self.execute(argv)
    if available?
      system(BIN_PATH, *argv)
    else
      raise "terminal-notifier is only supported on Mac OS X 10.8, or higher."
    end
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
    TerminalNotifier.silence_stdout { TerminalNotifier.verbose_notify(message, options) }
  end
  module_function :notify

  # The same as `verbose`, but sends the output from the tool to STDOUT.
  def verbose_notify(message, options = {})
    TerminalNotifier.execute_with_options(options.merge(:message => message))
  end
  module_function :verbose_notify

  # Removes a notification that was previously sent with the specified
  # ‘group’ ID, if one exists.
  def remove(group)
    TerminalNotifier.silence_stdout { TerminalNotifier.verbose_remove(group) }
  end
  module_function :remove

  # The same as `remove`, but sends the output from the tool to STDOUT.
  def verbose_remove(group)
    TerminalNotifier.execute_with_options(:remove => group)
  end
  module_function :verbose_remove
end
