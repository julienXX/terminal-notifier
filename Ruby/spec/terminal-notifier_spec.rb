require 'time'
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

  it "returns `nil` if no notification was found to list info for" do
    TerminalNotifier.expects(:execute_with_options).with(:list => 'important stuff').returns('')
    TerminalNotifier.list('important stuff').should == nil
  end

  it "returns info about a notification posted in a specific group" do
    TerminalNotifier.expects(:execute_with_options).with(:list => 'important stuff').
      returns("GroupID\tTitle\tSubtitle\tMessage\tDelivered At\n" \
              "important stuff\tTerminal\t(null)\tExecute: rake spec\t2012-08-06 19:45:30 +0000")
    TerminalNotifier.list('important stuff').should == {
      :group => 'important stuff',
      :title => 'Terminal', :subtitle => nil, :message => 'Execute: rake spec',
      :delivered_at => Time.parse('2012-08-06 19:45:30 +0000')
    }
  end

  it "by default returns a list of all notification" do
    TerminalNotifier.expects(:execute_with_options).with(:list => 'ALL').
      returns("GroupID\tTitle\tSubtitle\tMessage\tDelivered At\n" \
              "important stuff\tTerminal\t(null)\tExecute: rake spec\t2012-08-06 19:45:30 +0000\n" \
              "(null)\t(null)\tSubtle\tBe subtle!\t2012-08-07 19:45:30 +0000")
    TerminalNotifier.list.should == [
      {
        :group => 'important stuff',
        :title => 'Terminal', :subtitle => nil, :message => 'Execute: rake spec',
        :delivered_at => Time.parse('2012-08-06 19:45:30 +0000')
      },
      {
        :group => nil,
        :title => nil, :subtitle => 'Subtle', :message => 'Be subtle!',
        :delivered_at => Time.parse('2012-08-07 19:45:30 +0000')
      }
    ]
  end
end
