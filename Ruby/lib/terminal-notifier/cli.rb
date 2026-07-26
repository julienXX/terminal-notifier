# frozen_string_literal: true

require 'terminal-notifier'

module TerminalNotifier
  # Command line driver for the `terminal-notifier` executable, used by
  # `bin/terminal-notifier`. Kept separate from the executable itself so
  # its argument handling can be exercised directly in tests.
  module CLI
    # Builds the final argument list for the vendored binary — reading a
    # notification message from `stdin` when neither `-message` nor a TTY
    # is present — then `exec`s into it, replacing the current process.
    #
    # @param argv [Array<String>] the arguments to forward, defaults to
    #   the process's own `ARGV`.
    # @param stdin [IO] where to read a piped message from, defaults to
    #   the process's own `STDIN`.
    # @return [void] this method never returns on success; it replaces
    #   the current process image via `Kernel#exec`.
    def self.run(argv = ARGV, stdin = $stdin)
      argv = argv.dup
      argv.push('-message', stdin.read.chomp) if !argv.include?('-message') && !stdin.tty?

      exec(TerminalNotifier::BIN_PATH, *argv)
    end
  end
end
