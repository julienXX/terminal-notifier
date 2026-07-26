# frozen_string_literal: true

require 'stringio'
require 'time'

RSpec.describe TerminalNotifier do
  describe '.version' do
    it 'returns the macOS product version when running on Darwin' do
      allow(described_class).to receive(:`).with('uname').and_return("Darwin\n")
      allow(described_class).to receive(:`).with('sw_vers -productVersion').and_return("10.15.7\n")

      expect(described_class.version).to eq('10.15.7')
    end

    it 'returns false when not running on Darwin' do
      allow(described_class).to receive(:`).with('uname').and_return("Linux\n")

      expect(described_class.version).to be(false)
    end

    it 'memoizes a truthy result' do
      allow(described_class).to receive(:`).with('uname').and_return("Darwin\n")
      allow(described_class).to receive(:`).with('sw_vers -productVersion').and_return("10.15.7\n")

      described_class.version
      described_class.version

      expect(described_class).to have_received(:`).with('uname').once
      expect(described_class).to have_received(:`).with('sw_vers -productVersion').once
    end
  end

  describe '.available?' do
    it 'is true on macOS 10.10, or higher' do
      allow(RbConfig::CONFIG).to receive(:[]).with('host_os').and_return('darwin20')
      allow(described_class).to receive(:version).and_return('10.15.7')

      expect(described_class.available?).to be(true)
    end

    it 'is false on macOS older than 10.10' do
      allow(RbConfig::CONFIG).to receive(:[]).with('host_os').and_return('darwin9')
      allow(described_class).to receive(:version).and_return('10.9.5')

      expect(described_class.available?).to be(false)
    end

    it 'is false on non-macOS platforms' do
      allow(RbConfig::CONFIG).to receive(:[]).with('host_os').and_return('linux-gnu')
      allow(described_class).to receive(:version).and_return(false)

      expect(described_class.available?).to be(false)
    end

    it 'memoizes a truthy result' do
      allow(RbConfig::CONFIG).to receive(:[]).with('host_os').and_return('darwin20')
      allow(described_class).to receive(:version).and_return('10.15.7')

      described_class.available?
      described_class.available?

      expect(described_class).to have_received(:version).once
    end
  end

  describe '.execute' do
    context 'when unavailable on this platform' do
      before { allow(described_class).to receive(:available?).and_return(false) }

      it 'prints a warning to STDERR and does not run the binary' do
        expect(IO).not_to receive(:popen)
        expect { described_class.execute(false, {}) }
          .to output('terminal-notifier is only supported on macOS 10.10, or higher.').to_stderr
      end
    end

    context 'when available on this platform' do
      before { allow(described_class).to receive(:available?).and_return(true) }

      it 'executes the tool with the given options and properly escapes the message' do
        command = [described_class::BIN_PATH, '-message', '\[ZOMG] "OH YEAH"']
        allow(IO).to receive(:popen).with(command).and_yield(StringIO.new('output'))

        described_class.execute(false, message: '[ZOMG] "OH YEAH"')

        expect(IO).to have_received(:popen).with(command)
      end

      it 'correctly escapes arguments that start with a dash' do
        command = [described_class::BIN_PATH, '-message', ' -kittens', '-title', ' -rule']
        allow(IO).to receive(:popen).with(command).and_yield(StringIO.new('output'))

        described_class.execute(false, message: '-kittens', title: '-rule')

        expect(IO).to have_received(:popen).with(command)
      end

      it 'returns the result output of the command' do
        allow(IO).to receive(:popen).and_yield(StringIO.new('some output'))

        expect(described_class.execute(false, help: '')).to eq('some output')
      end

      it 'prints the output to STDOUT when verbose' do
        allow(IO).to receive(:popen).and_yield(StringIO.new('some output'))

        expect { described_class.execute(true, help: '') }.to output('some output').to_stdout
      end

      it 'does not print the output to STDOUT when not verbose' do
        allow(IO).to receive(:popen).and_yield(StringIO.new('some output'))

        expect { described_class.execute(false, help: '') }.not_to output.to_stdout
      end
    end
  end

  describe '.notify_result' do
    it 'downcases and underscores the result into a symbol' do
      expect(described_class.notify_result('Test', {})).to eq(:test)
    end

    it 'replaces runs of non-word characters with a single underscore' do
      expect(described_class.notify_result('No, sir', {})).to eq(:no_sir)
      expect(described_class.notify_result('I may like pie', {})).to eq(:i_may_like_pie)
    end

    it 'prefixes symbols for values that start with a non-word character' do
      expect(described_class.notify_result('@timeout', {})).to eq(:_timeout)
      expect(described_class.notify_result('@closeaction', {})).to eq(:_closeaction)
    end

    it 'returns true for an empty result instead of symbolising it' do
      expect(described_class.notify_result('', {})).to be(true)
    end

    it 'returns the raw string when the reply option is a symbol key' do
      expect(described_class.notify_result('I like pie', reply: true)).to eq('I like pie')
    end

    it 'returns the raw string when the reply option is a string key' do
      expect(described_class.notify_result('I do not like pie', 'reply' => true)).to eq('I do not like pie')
    end

    it 'returns the raw string when always_string is set' do
      expect(described_class.notify_result('@timeout', {}, true)).to eq('@timeout')
    end
  end

  describe '.notify' do
    it 'sends a notification with the given options' do
      allow(described_class).to receive(:execute).with(false,
                                                       { message: 'ZOMG', group: 'important stuff' }).and_return('zomg')
      `true`

      described_class.notify('ZOMG', group: 'important stuff')

      expect(described_class).to have_received(:execute).with(false, { message: 'ZOMG', group: 'important stuff' })
    end

    it 'returns the processed result when the command succeeds' do
      allow(described_class).to receive(:execute).and_return('ZOMG')
      `true`

      expect(described_class.notify('ZOMG')).to eq(:zomg)
    end

    it 'returns false when the command fails' do
      allow(described_class).to receive(:execute).and_return('')
      `false`

      expect(described_class.notify('ZOMG')).to be(false)
    end

    it 'returns nil when no child process has been spawned yet ($? is thread-local)' do
      allow(described_class).to receive(:execute).and_return('ZOMG')
      result = nil

      Thread.new { result = described_class.notify('ZOMG') }.join

      expect(result).to be_nil
    end
  end

  describe '.remove' do
    it 'removes a notification with the given group' do
      allow(described_class).to receive(:execute).with(false, remove: 'important stuff')
      `true`

      described_class.remove('important stuff')

      expect(described_class).to have_received(:execute).with(false, remove: 'important stuff')
    end

    it 'by default removes all the notifications' do
      allow(described_class).to receive(:execute).with(false, remove: 'ALL')
      `true`

      described_class.remove

      expect(described_class).to have_received(:execute).with(false, remove: 'ALL')
    end

    it 'returns true when the command succeeds' do
      allow(described_class).to receive(:execute)
      `true`

      expect(described_class.remove).to be(true)
    end

    it 'returns false when the command fails' do
      allow(described_class).to receive(:execute)
      `false`

      expect(described_class.remove).to be(false)
    end

    it 'returns nil when no child process has been spawned yet ($? is thread-local)' do
      allow(described_class).to receive(:execute)
      result = nil

      Thread.new { result = described_class.remove }.join

      expect(result).to be_nil
    end
  end

  describe '.list' do
    it 'returns `nil` if no notification was found to list info for' do
      allow(described_class).to receive(:execute).with(false, list: 'important stuff').and_return('')

      expect(described_class.list('important stuff')).to be_nil
    end

    it 'returns info about a notification posted in a specific group' do
      allow(described_class).to receive(:execute).with(false, list: 'important stuff').and_return(
        "GroupID\tTitle\tSubtitle\tMessage\tDelivered At\n" \
        "important stuff\tTerminal\t(null)\tExecute: rake spec\t2012-08-06 19:45:30 +0000"
      )

      expect(described_class.list('important stuff')).to eq(
        group: 'important stuff',
        title: 'Terminal', subtitle: nil, message: 'Execute: rake spec',
        delivered_at: Time.parse('2012-08-06 19:45:30 +0000')
      )
    end

    it 'by default returns a list of all notifications' do
      allow(described_class).to receive(:execute).with(false, list: 'ALL').and_return(
        "GroupID\tTitle\tSubtitle\tMessage\tDelivered At\n" \
        "important stuff\tTerminal\t(null)\tExecute: rake spec\t2012-08-06 19:45:30 +0000\n" \
        "(null)\t(null)\tSubtle\tBe subtle!\t2012-08-07 19:45:30 +0000"
      )

      expect(described_class.list).to eq(
        [
          {
            group: 'important stuff',
            title: 'Terminal', subtitle: nil, message: 'Execute: rake spec',
            delivered_at: Time.parse('2012-08-06 19:45:30 +0000')
          },
          {
            group: nil,
            title: nil, subtitle: 'Subtle', message: 'Be subtle!',
            delivered_at: Time.parse('2012-08-07 19:45:30 +0000')
          }
        ]
      )
    end
  end
end
