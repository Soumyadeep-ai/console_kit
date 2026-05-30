# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ConsoleKit::Output do
  before { ConsoleKit.configure { |c| c.pretty_output = pretty_output } }

  let(:pretty_output) { true }

  def capture_stdout
    original_stdout = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = original_stdout
  end

  shared_examples 'ConsoleKit output formatter' do |method, message:, symbol:, color_code: nil|
    it "includes [ConsoleKit] prefix for #{method}" do
      output = capture_stdout { described_class.send(method, message) }
      expect(output).to include('[ConsoleKit]')
    end

    it "includes symbol for #{method}" do
      output = capture_stdout { described_class.send(method, message) }
      expect(output).to include(symbol) if symbol
    end

    it "includes ANSI color code for #{method}" do
      next unless ConsoleKit.configuration.pretty_output && color_code

      output = capture_stdout { described_class.send(method, message) }
      expect(output).to match(/\e\[#{color_code}m/)
    end

    it "has no ANSI codes when pretty_output off or no code for #{method}" do
      next if ConsoleKit.configuration.pretty_output && color_code

      output = capture_stdout { described_class.send(method, message) }
      expect(output).not_to match(/\e\[[\d;]+m/)
    end

    it "includes the message text for #{method}" do
      output = capture_stdout { described_class.send(method, message) }
      expect(output).to include(message)
    end
  end

  describe 'standard outputs' do
    it_behaves_like 'ConsoleKit output formatter', :print_success, message: 'All good', symbol: '[✓]',
                                                                   color_code: '1;32'
    it_behaves_like 'ConsoleKit output formatter', :print_error, message: 'Something broke', symbol: '[✗]',
                                                                 color_code: '1;31'
    it_behaves_like 'ConsoleKit output formatter', :print_warning, message: 'Careful now', symbol: '[!]',
                                                                   color_code: '1;33'
    it_behaves_like 'ConsoleKit output formatter', :print_info, message: 'Heads up', symbol: nil, color_code: nil
    it_behaves_like 'ConsoleKit output formatter', :print_prompt, message: 'Input please', symbol: nil,
                                                                  color_code: '1;36'
    it_behaves_like 'ConsoleKit output formatter', :print_header, message: 'Section Start', symbol: nil,
                                                                  color_code: '1;34'
  end

  describe '#print_backtrace' do
    let(:exception) do
      e = RuntimeError.new('Something bad happened')
      e.set_backtrace(['lib/foo.rb:10', 'app/bar.rb:20'])
      e
    end

    it 'includes first backtrace line' do
      output = capture_stdout { described_class.print_backtrace(exception) }
      expect(output).to include('lib/foo.rb:10')
    end

    it 'includes second backtrace line' do
      output = capture_stdout { described_class.print_backtrace(exception) }
      expect(output).to include('app/bar.rb:20')
    end

    it 'formats with color when pretty_output enabled' do
      output = capture_stdout { described_class.print_backtrace(exception) }
      expect(output).to match(%r{\e\[0;90m\[ConsoleKit\]     lib/foo\.rb:10\e\[0m})
    end

    it 'handles nil exception gracefully' do
      expect { described_class.print_backtrace(nil) }.not_to output.to_stdout
    end

    it 'handles exception with nil backtrace' do
      e = RuntimeError.new('no trace')
      e.set_backtrace(nil)
      expect { described_class.print_backtrace(e) }.not_to output.to_stdout
    end
  end

  describe 'timestamp support' do
    let(:now) { Time.new(2025, 8, 12, 15, 45, 12) }

    before { allow(Time).to receive(:current).and_return(now) }

    it 'includes timestamp when enabled' do
      output = capture_stdout { described_class.send(:print_with, :info, 'Timed', timestamp: true) }
      expect(output).to include('[2025-08-12 15:45:12]')
    end

    it 'includes ConsoleKit prefix with timestamp' do
      output = capture_stdout { described_class.send(:print_with, :info, 'Timed', timestamp: true) }
      expect(output).to include('[ConsoleKit]')
    end

    it 'includes message text with timestamp' do
      output = capture_stdout { described_class.send(:print_with, :info, 'Timed', timestamp: true) }
      expect(output).to include('Timed')
    end
  end

  describe 'pretty_output false' do
    let(:pretty_output) { false }

    it_behaves_like 'ConsoleKit output formatter', :print_success, message: 'Plain OK', symbol: '[✓]',
                                                                   color_code: '1;32'
    it_behaves_like 'ConsoleKit output formatter', :print_error, message: 'Plain error', symbol: '[✗]',
                                                                 color_code: '1;31'
    it_behaves_like 'ConsoleKit output formatter', :print_warning, message: 'Plain warning', symbol: '[!]',
                                                                   color_code: '1;33'
    it_behaves_like 'ConsoleKit output formatter', :print_info, message: 'Plain info', symbol: nil, color_code: nil
    it_behaves_like 'ConsoleKit output formatter', :print_prompt, message: 'No color prompt', symbol: nil,
                                                                  color_code: '1;36'
    it_behaves_like 'ConsoleKit output formatter', :print_header, message: 'No color header', symbol: nil,
                                                                  color_code: '1;34'
  end

  describe 'ANSI output readability' do
    it 'removes ANSI codes correctly from output' do
      output = capture_stdout { described_class.print_error('Boom') }
      clean = output.gsub(/\e\[[\d;]+m/, '')
      expect(clean).to include('[ConsoleKit] [✗] Boom')
    end
  end

  describe '.sanitize_display' do
    it 'strips CSI ANSI escape sequences' do
      expect(described_class.sanitize_display("\e[31mred\e[0m")).to eq('red')
    end

    it 'strips OSC terminal control sequences' do
      expect(described_class.sanitize_display("\e]0;title\a")).to eq('')
    end

    it 'strips control characters including newline and carriage return' do
      expect(described_class.sanitize_display("foo\r\nbar")).to eq('foobar')
    end

    it 'strips null bytes' do
      expect(described_class.sanitize_display("foo\x00bar")).to eq('foobar')
    end

    it 'leaves normal text unchanged' do
      expect(described_class.sanitize_display('acme-tenant_1')).to eq('acme-tenant_1')
    end

    it 'calls to_s on non-string input' do
      expect(described_class.sanitize_display(:symbol_value)).to eq('symbol_value')
    end
  end

  describe '.print_banner' do
    it 'outputs bordered lines to stdout' do
      expect { described_class.print_banner(lines: ['LINE ONE'], style: :danger) }
        .to output(/LINE ONE/).to_stdout
    end

    it 'includes box border characters' do
      expect { described_class.print_banner(lines: ['X'], style: :warn) }
        .to output(/[╔╚║]/).to_stdout
    end

    it 'strips ANSI escapes from banner lines' do
      expect { described_class.print_banner(lines: ["\e[31mDANGER\e[0m"], style: :danger) }
        .to output(/DANGER/).to_stdout
    end

    it 'suppresses banner output when silent' do
      output = capture_stdout do
        described_class.silence { described_class.print_banner(lines: ['X']) }
      end
      expect(output).to be_empty
    end

    it 'omits ANSI color codes in banner when pretty_output is false' do
      ConsoleKit.configure { |c| c.pretty_output = false }
      output = capture_stdout { described_class.print_banner(lines: ['X'], style: :danger) }
      expect(output).not_to match(/\e\[/)
    end
  end

  describe '.silent' do
    it 'returns nil by default' do
      expect(described_class.silent).to be_nil
    end

    it 'returns true after silent= true' do
      described_class.silent = true
      expect(described_class.silent).to be(true)
    end
  end

  describe '.silent=' do
    it 'sets the thread-local silent flag' do
      described_class.silent = true
      expect(Thread.current[:console_kit_silent]).to be(true)
    end

    it 'can be set back to false' do
      described_class.silent = false
      expect(described_class.silent).to be(false)
    end
  end

  describe '.silence' do
    def attempt_ignoring_error
      yield
    rescue StandardError
      nil
    end

    it 'suppresses output within the block' do
      output = capture_stdout do
        described_class.silence { described_class.print_info('should not appear') }
      end
      expect(output).to be_empty
    end

    it 'restores silent to previous value after block' do
      described_class.silent = false
      described_class.silence { nil }
      expect(described_class.silent).to be(false)
    end

    it 'restores silent even if block raises' do
      described_class.silent = nil
      attempt_ignoring_error { described_class.silence { raise 'boom' } }
      expect(described_class.silent).to be_nil
    end
  end

  describe '.print_list' do
    let(:list_output) { capture_stdout { described_class.print_list(%w[apple banana]) } }

    it 'prints the first item' do
      expect(list_output).to include('apple')
    end

    it 'prints the second item' do
      expect(list_output).to include('banana')
    end

    it 'prints a header when provided' do
      output = capture_stdout { described_class.print_list(%w[x], header: 'My Header') }
      expect(output).to include('My Header')
    end

    it 'suppresses output when silent' do
      output = capture_stdout do
        described_class.silence { described_class.print_list(%w[item]) }
      end
      expect(output).to be_empty
    end
  end

  describe '.print_raw' do
    it 'outputs the text' do
      output = capture_stdout { described_class.print_raw('raw text here') }
      expect(output).to include('raw text here')
    end

    it 'suppresses output when silent' do
      output = capture_stdout do
        described_class.silence { described_class.print_raw('suppressed') }
      end
      expect(output).to be_empty
    end
  end

  describe '.print_backtrace when silent' do
    let(:exception) do
      e = RuntimeError.new('oops')
      e.set_backtrace(['lib/foo.rb:1'])
      e
    end

    it 'suppresses backtrace output when silent' do
      output = capture_stdout do
        described_class.silence { described_class.print_backtrace(exception) }
      end
      expect(output).to be_empty
    end
  end

  describe 'print_* methods when silent' do
    it 'suppresses print_error when silent' do
      output = capture_stdout do
        described_class.silence { described_class.print_error('error msg') }
      end
      expect(output).to be_empty
    end

    it 'suppresses print_success when silent' do
      output = capture_stdout do
        described_class.silence { described_class.print_success('ok') }
      end
      expect(output).to be_empty
    end
  end

  describe '#print_with newline: false' do
    it 'uses print instead of puts when newline: false' do
      output = capture_stdout { described_class.send(:print_with, :info, 'inline', newline: false) }
      expect(output).not_to end_with("\n")
    end

    it 'uses puts when newline: true' do
      output = capture_stdout { described_class.send(:print_with, :info, 'line', newline: true) }
      expect(output).to end_with("\n")
    end
  end

  describe '#print_with non-hash options (legacy)' do
    it 'treats non-hash options as timestamp value' do
      now = Time.new(2025, 1, 1, 12, 0, 0)
      allow(Time).to receive(:current).and_return(now)
      output = capture_stdout { described_class.send(:print_with, :info, 'msg', true) }
      expect(output).to include('[2025-01-01 12:00:00]')
    end
  end
end
