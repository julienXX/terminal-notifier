# frozen_string_literal: true

require 'shellwords'
require 'rbconfig'
require 'English'

# A thin Ruby wrapper around the `terminal-notifier` command-line tool,
# which sends User Notifications to the Notification Center on macOS
# 10.10, or higher.
#
# All public methods are exposed as both instance and module methods, so
# the module can be used directly (e.g. `TerminalNotifier.notify(...)`)
# without needing to `include` or instantiate anything.
module TerminalNotifier
  # Absolute path to the vendored `terminal-notifier` executable that ships
  # inside this gem.
  BIN_PATH = File.expand_path('../vendor/terminal-notifier/terminal-notifier.app/Contents/MacOS/terminal-notifier',
                              __dir__)

  # Raised to indicate the current platform does not support displaying
  # User Notifications. Currently unused by this library directly, but
  # kept as part of the public API for consumers that wish to raise it
  # themselves after checking {TerminalNotifier.available?}.
  class UnsupportedPlatformError < StandardError; end

  # Returns whether or not the current platform is macOS 10.10, or higher.
  #
  # @return [Boolean] `true` if notifications can be displayed on this
  #   machine, `false` otherwise.
  def self.available?
    @available ||= /darwin|mac os/.match?(RbConfig::CONFIG['host_os']) && Gem::Version.new(version) > Gem::Version.new('10.10')
  end

  # The macOS product version, e.g. `"10.15.7"`.
  #
  # @return [String, false] the version string on macOS, or `false` when
  #   not running on macOS.
  def self.version
    @version ||= `uname`.strip == 'Darwin' && `sw_vers -productVersion`.strip
  end

  # Executes the vendored `terminal-notifier` binary with the given
  # options and returns its standard output.
  #
  # @param verbose [Boolean] when `true`, also echoes the command's
  #   output to `STDOUT` as it is produced.
  # @param options [Hash{Symbol,String=>Object}] CLI flags to pass to the
  #   binary, e.g. `{ :message => 'Hello' }` becomes `-message Hello`.
  #   Values are converted with `#to_s`; a leading dash is preserved but
  #   prefixed with a space so it is not mistaken for a separate flag.
  #
  # @return [String] the captured standard output of the command, or an
  #   error message printed to `STDERR` (and an empty return value) when
  #   {available?} is `false`.
  def self.execute(verbose, options)
    if available?
      command = [BIN_PATH, *options.map do |k, v|
        v = v.to_s
        ["-#{k}", "#{' ' if v[0] == '-'}#{Shellwords.escape(v[0, 1])}#{v[1..]}"]
      end.flatten]
      result = +''
      IO.popen(command) do |stdout|
        output = stdout.read
        $stdout.print output if verbose
        result << output
      end
      result
    else
      $stderr.print 'terminal-notifier is only supported on macOS 10.10, or higher.'
    end
  end

  # Cleans up the result of a notification, making it easier to work it
  #
  # The result of a notification is downcased, then groups of 1 or more
  # non-word characters are replaced with an underscore, before being
  # symbolised.
  #
  # If the reply option was given, then instead of going through the
  # above process, the result is returned with no changes as a string.
  #
  # If the always_string param is set to true, a the result is returned
  # with no changes as a string, like above.
  #
  # Examples are:
  #
  # notify_result('Test', {}) #=> :test
  # notify_result('No, sir', {}) #=> :no_sir
  # notify_result('@timeout', {}) #=> :_timeout
  # notify_result('@closeaction', {}) #=> :_closeaction
  # notify_result('I like pie', {reply: true}) #=> 'I like pie'
  # notify_result('I do not like pie', {'reply' => true}) #=> 'I do not like pie'
  # notify_result('@timeout', {'reply' => true}) #=> '@timeout'
  # notify_result('I may like pie', {}) #=> :i_may_like_pie
  #
  # @param result [String] the raw output captured from the command.
  # @param options [Hash] the options that were passed to {notify}.
  # @param always_string [Boolean] force returning `result` unchanged.
  # @return [String, Symbol, Boolean] `result` as-is, a symbolised
  #   version of it, or `false` when `result` is empty.
  def notify_result(result, options, always_string = false)
    if options[:reply] || options['reply'] || always_string
      result
    else
      result.empty? || result.downcase.gsub(/\W+/, '_').to_sym
    end
  end
  module_function :notify_result

  # Sends a User Notification and returns whether or not it was a success.
  #
  # The available options are `:title`, `:group`, `:activate`, `:open`,
  # `:execute`, `:sender`, and `:sound`. For a description of each option see:
  #
  #   https://github.com/julienXX/terminal-notifier/blob/master/README.markdown
  #
  # Examples are:
  #
  #   TerminalNotifier.notify('Hello World')
  #   TerminalNotifier.notify('Hello World', :title => 'Ruby')
  #   TerminalNotifier.notify('Hello World', :group => Process.pid)
  #   TerminalNotifier.notify('Hello World', :activate => 'com.apple.Safari')
  #   TerminalNotifier.notify('Hello World', :open => 'http://twitter.com/julienXX')
  #   TerminalNotifier.notify('Hello World', :execute => 'say "OMG"')
  #   TerminalNotifier.notify('Hello World', :sender => 'com.apple.Safari')
  #   TerminalNotifier.notify('Hello World', :sound => 'default')
  #
  # @param message [String] the notification's body text.
  # @param options [Hash] any of the CLI options described above.
  # @param verbose [Boolean] passed through to {execute}.
  # @param always_string [Boolean] passed through to {notify_result}.
  # @return [String, Symbol, Boolean] the processed result via
  #   {notify_result}, or `false` when the command failed or is
  #   unsupported on this platform.
  def notify(message, options = {}, verbose = false, always_string = false)
    result = TerminalNotifier.execute(verbose, options.merge(message: message))
    $CHILD_STATUS&.success? && notify_result(result, options, always_string)
  end
  module_function :notify

  # Removes a notification that was previously sent with the specified
  # ‘group’ ID, if one exists.
  #
  # If no ‘group’ ID is given, all notifications are removed.
  #
  # @param group [String] the group ID to remove, or `'ALL'` for every
  #   notification.
  # @param verbose [Boolean] passed through to {execute}.
  # @return [Boolean] whether or not the command succeeded.
  def remove(group = 'ALL', verbose = false)
    TerminalNotifier.execute(verbose, remove: group)
    $CHILD_STATUS&.success?
  end
  module_function :remove

  # The fields returned, in order, by `terminal-notifier -list`.
  LIST_FIELDS = %i[group title subtitle message delivered_at].freeze

  # If a ‘group’ ID is given, and a notification for that group exists,
  # returns a hash with details about the notification.
  #
  # If no ‘group’ ID is given, an array of hashes describing all
  # notifications.
  #
  # If no information is available this will return `nil`.
  #
  # @param group [String] the group ID to look up, or `'ALL'` to list
  #   every delivered notification.
  # @param verbose [Boolean] passed through to {execute}.
  # @return [Hash, Array<Hash>, nil] a single notification hash, an array
  #   of notification hashes, or `nil` when nothing was found.
  def list(group = 'ALL', verbose = false)
    output = TerminalNotifier.execute(verbose, list: group)
    return if output.strip.empty?

    require 'time'
    notifications = output.split("\n")[1..].map do |line|
      LIST_FIELDS.zip(line.split("\t")).each_with_object({}) do |(key, value), hash|
        hash[key] = key == :delivered_at ? Time.parse(value) : (value unless value == '(null)')
      end
    end

    group == 'ALL' ? notifications : notifications.first
  end
  module_function :list
end
