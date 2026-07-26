# frozen_string_literal: true

require 'simplecov'

SimpleCov.start do
  enable_coverage :branch
  add_filter '/spec/'
  # bin/terminal-notifier is a 2-line dispatch shim (see lib/terminal-notifier/cli.rb
  # for the actual, fully-covered logic); Ruby's Coverage module does not accumulate
  # branch/line hits across repeated in-process `load`s of the same script, which
  # makes exercising both the "run as main" and "merely loaded" guards unmeasurable
  # from a single spec run, so it is excluded here rather than chasing a false signal.
  add_filter '/bin/'
  minimum_coverage line: 100, branch: 100
end

$LOAD_PATH.unshift File.expand_path('../lib', __dir__)
require 'terminal-notifier'
require 'terminal-notifier/cli'

RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.example_status_persistence_file_path = '.rspec_status'
  config.disable_monkey_patching!
  config.default_formatter = 'doc' if config.files_to_run.one?
  config.order = :random

  Kernel.srand config.seed

  config.before do
    TerminalNotifier.instance_variable_set(:@available, nil)
    TerminalNotifier.instance_variable_set(:@version, nil)
  end
end
