# coding: utf-8
require 'shellwords'
require 'rbconfig'

module TerminalNotifier
  BIN_PATH = File.expand_path('../../vendor/terminal-notifier', __FILE__)

  class UnsupportedPlatformError < StandardError; end
  # Returns wether or not the current platform is Mac OS X 10.10, or higher.
  def self.available?
    @available ||= (/darwin|mac os/ =~ RbConfig::CONFIG['host_os']) && Gem::Version.new(version) > Gem::Version.new('10.10')
  end

  def self.version
    @version ||= `uname`.strip == 'Darwin' && `sw_vers -productVersion`.strip
  end

  def self.execute(verbose, options)
    if available?
      command = [BIN_PATH, *options.map { |k,v| v = v.to_s; ["-#{k}", "#{v[0] == "-" ? " " : ""}#{Shellwords.escape(v[0,1])}#{v[1..-1]}"] }.flatten]
      command = Shellwords.join(command) if RUBY_VERSION < '1.9'
      result = ''
      IO.popen(command) do |stdout|
        output = stdout.read
        STDOUT.print output if verbose
        result << output
      end
      result
    else
      STDERR.print "terminal-notifier is only supported on Mac OS X 10.10, or higher."
    end
  end

  # Sends a User Notification and returns whether or not it was a success.
  #
  # The available options are `:title`, `:group`, `:activate`, `:open`,
  # `:execute`, `:sender`, and `:sound`. For a description of each option see:
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
  #   TerminalNotifier.notify('Hello World', :sender => 'com.apple.Safari')
  #   TerminalNotifier.notify('Hello World', :sound => 'default')
  #
  # Raises if not supported on the current platform.
  def notify(message, options = {}, verbose = false)
    TerminalNotifier.execute(verbose, options.merge(:message => message))
    $? && $?.success?
  end
  module_function :notify

  # Removes a notification that was previously sent with the specified
  # ‘group’ ID, if one exists.
  #
  # If no ‘group’ ID is given, all notifications are removed.
  def remove(group = 'ALL', verbose = false)
    TerminalNotifier.execute(verbose, :remove => group)
    $? && $?.success?
  end
  module_function :remove

  LIST_FIELDS = [:group, :title, :subtitle, :message, :delivered_at].freeze

  # If a ‘group’ ID is given, and a notification for that group exists,
  # returns a hash with details about the notification.
  #
  # If no ‘group’ ID is given, an array of hashes describing all
  # notifications.
  #
  # If no information is available this will return `nil`.
  def list(group = 'ALL', verbose = false)
    output = TerminalNotifier.execute(verbose, :list => group)
    return if output.strip.empty?

    require 'time'
    notifications = output.split("\n")[1..-1].map do |line|
      LIST_FIELDS.zip(line.split("\t")).inject({}) do |hash, (key, value)|
        hash[key] = key == :delivered_at ? Time.parse(value) : (value unless value == '(null)')
        hash
      end
    end

    group == 'ALL' ? notifications : notifications.first
  end
  module_function :list
end
