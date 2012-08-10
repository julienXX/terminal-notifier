require 'rubygems'
require 'bacon'
require 'mocha'
require 'mocha-on-bacon'

Bacon.summary_at_exit

$:.unshift File.expand_path('../../lib', __FILE__)
require 'terminal-notifier'

describe "TerminalNotifier" do
  it "executes the tool with the given options" do
    command = [TerminalNotifier::BIN_PATH, '-message', 'ZOMG']
    if RUBY_VERSION < '1.9'
      require 'shellwords'
      command = Shellwords.shelljoin(command)
    end
    IO.expects(:popen).with(command).yields(StringIO.new('output'))
    TerminalNotifier.execute(false, :message => 'ZOMG')
  end

  it "returns the result output of the command" do
    TerminalNotifier.execute(false, 'help' => '').should == `'#{TerminalNotifier::BIN_PATH}' -help`
  end

  it "sends a notification" do
    TerminalNotifier.expects(:execute).with(false, :message => 'ZOMG', :group => 'important stuff')
    TerminalNotifier.notify('ZOMG', :group => 'important stuff')
  end

  it "removes a notification" do
    TerminalNotifier.expects(:execute).with(false, :remove => 'important stuff')
    TerminalNotifier.remove('important stuff')
  end

  it "by default removes all the notifications" do
    TerminalNotifier.expects(:execute).with(false, :remove => 'ALL')
    TerminalNotifier.remove
  end

  it "returns `nil` if no notification was found to list info for" do
    TerminalNotifier.expects(:execute).with(false, :list => 'important stuff').returns('')
    TerminalNotifier.list('important stuff').should == nil
  end

  it "returns info about a notification posted in a specific group" do
    TerminalNotifier.expects(:execute).with(false, :list => 'important stuff').
      returns("GroupID\tTitle\tSubtitle\tMessage\tDelivered At\n" \
              "important stuff\tTerminal\t(null)\tExecute: rake spec\t2012-08-06 19:45:30 +0000")
    TerminalNotifier.list('important stuff').should == {
      :group => 'important stuff',
      :title => 'Terminal', :subtitle => nil, :message => 'Execute: rake spec',
      :delivered_at => Time.parse('2012-08-06 19:45:30 +0000')
    }
  end

  it "by default returns a list of all notification" do
    TerminalNotifier.expects(:execute).with(false, :list => 'ALL').
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
