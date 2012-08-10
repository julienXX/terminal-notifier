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

  # If a ‘group’ ID is given, and a notification for that group exists,
  # returns a hash with details about the notification.
  #
  # If no ‘group’ ID is given, an array of hashes describing all
  # notifications.
  #
  # If no information is available this will return `nil`.
  def list(group = :all)
    TerminalNotifier.silence_stdout { TerminalNotifier.verbose_list(group) }
  end
  module_function :list

  LIST_FIELDS = [:group, :title, :subtitle, :message, :delivered_at].freeze

  # The same as `list`, but sends the output from the tool to STDOUT.
  def verbose_list(group = :all)
    output = TerminalNotifier.execute_with_options(:list => (group == :all ? 'ALL' : group))
    return if output.strip.empty?

    notifications = output.split("\n")[1..-1].map do |line|
      LIST_FIELDS.zip(line.split("\t")).inject({}) do |hash, (key, value)|
        hash[key] = key == :delivered_at ? Time.parse(value) : (value unless value == '(null)')
        hash
      end
    end

    group == :all ? notifications : notifications.first
  end
  module_function :verbose_list
end
