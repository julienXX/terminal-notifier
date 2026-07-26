# frozen_string_literal: true

require 'stringio'

RSpec.describe TerminalNotifier::CLI do
  describe '.run' do
    it 'execs the vendored binary with the given argv unchanged when -message is present' do
      allow(described_class).to receive(:exec)
      stdin = instance_double(IO, tty?: false)

      described_class.run(['-message', 'hi'], stdin)

      expect(described_class).to have_received(:exec).with(TerminalNotifier::BIN_PATH, '-message', 'hi')
    end

    it 'execs the vendored binary with the given argv unchanged when stdin is a tty' do
      allow(described_class).to receive(:exec)
      stdin = instance_double(IO, tty?: true)

      described_class.run(['-title', 'Ruby'], stdin)

      expect(described_class).to have_received(:exec).with(TerminalNotifier::BIN_PATH, '-title', 'Ruby')
    end

    it 'reads a message from stdin when -message is absent and stdin is piped' do
      allow(described_class).to receive(:exec)
      stdin = StringIO.new("Hello World\n")

      described_class.run(['-title', 'Ruby'], stdin)

      expect(described_class).to have_received(:exec).with(TerminalNotifier::BIN_PATH, '-title', 'Ruby', '-message',
                                                           'Hello World')
    end
  end
end

RSpec.describe 'bin/terminal-notifier' do
  let(:bin_path) { File.expand_path('../bin/terminal-notifier', __dir__) }

  around do |example|
    original_program_name = $PROGRAM_NAME
    $PROGRAM_NAME = bin_path
    example.run
  ensure
    $PROGRAM_NAME = original_program_name
  end

  it 'delegates to TerminalNotifier::CLI.run when executed directly' do
    allow(TerminalNotifier::CLI).to receive(:run)

    load bin_path

    expect(TerminalNotifier::CLI).to have_received(:run)
  end

  it 'does not invoke TerminalNotifier::CLI.run when merely required' do
    allow(TerminalNotifier::CLI).to receive(:run)
    $PROGRAM_NAME = 'rspec'

    load bin_path

    expect(TerminalNotifier::CLI).not_to have_received(:run)
  end
end
