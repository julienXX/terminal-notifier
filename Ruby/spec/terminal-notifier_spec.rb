require 'rubygems'
require 'bacon'
require 'mocha'
require 'mocha-on-bacon'

Bacon.summary_at_exit

$:.unshift File.expand_path('../../lib', __FILE__)
require 'terminal-notifier'

describe "TerminalNotifier" do
  it "converts options to args" do
    TerminalNotifier.expects(:execute).with(['-message', 'ZOMG'])
    TerminalNotifier.execute_with_options(:message => 'ZOMG')
  end

  it "executes the tool with the given arguments" do
    TerminalNotifier.expects(:system).with(TerminalNotifier::BIN_PATH, '-message', 'ZOMG')
    TerminalNotifier.execute(['-message', 'ZOMG'])
  end

  it "sends a notification" do
    TerminalNotifier.expects(:execute_with_options).with(:message => 'ZOMG', :group => 'important stuff')
    TerminalNotifier.notify('ZOMG', :group => 'important stuff')
  end

  it "removes a notification" do
    TerminalNotifier.expects(:execute_with_options).with(:remove => 'important stuff')
    TerminalNotifier.remove('important stuff')
  end
end
