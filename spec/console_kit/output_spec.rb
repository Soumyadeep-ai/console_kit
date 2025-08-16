# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ConsoleKit::Output do
  before { ConsoleKit.configure { |c| c.pretty_output = pretty_output } }

  let(:pretty_output) { true }

  shared_examples 'ConsoleKit output formatter' do |method, message:, symbol:, color_code: nil|
    def format_expected_line(method, message, symbol)
      return "[ConsoleKit] \n=== #{message} ===" if method == :print_header

      line = '[ConsoleKit] '
      line += "#{symbol} " if symbol
      line + message
    end

    def expect_color(output, code)
      if ConsoleKit.configuration.pretty_output && code
        expect(output).to match(/\e\[#{code}m/)
        expect(output).to match(/\e\[0m/)
      else
        expect(output).not_to match(/\e\[[\d;]+m/)
      end
    end

    it "includes [ConsoleKit] tag in #{method} output" do
      output = OutputHelper.capture_stdout { described_class.send(method, message) }
      expect(output).to include('[ConsoleKit]')
    end

    it "includes symbol in #{method} output if provided" do
      output = OutputHelper.capture_stdout { described_class.send(method, message) }
      expect(output).to include(symbol) if symbol
    end

    it "includes formatted message for #{method}" do
      output = OutputHelper.capture_stdout { described_class.send(method, message) }
      expect(output).to include(format_expected_line(method, message, symbol))
    end

    it "handles ANSI color for #{method}" do
      output = OutputHelper.capture_stdout { described_class.send(method, message) }
      expect_color(output, color_code)
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

    def expect_backtrace_lines(output)
      expect(output).to include('lib/foo.rb:10')
      expect(output).to include('app/bar.rb:20')
    end

    def expect_backtrace_formatting(output)
      if pretty_output
        expect(output).to match(%r{\e\[0;90m\[ConsoleKit\]     lib/foo\.rb:10\e\[0m})
      else
        expect(output).to include('[ConsoleKit]     lib/foo.rb:10')
        expect(output).not_to match(/\e\[/)
      end
    end

    it 'prints backtrace with correct format' do
      output = OutputHelper.capture_stdout { described_class.print_backtrace(exception) }
      expect_backtrace_lines(output)
      expect_backtrace_formatting(output)
    end

    it 'handles nil exception' do
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
      output = OutputHelper.capture_stdout { described_class.send(:print_with, :info, 'Timed', timestamp: true) }
      expect(output).to include('[2025-08-12 15:45:12]')
    end

    it 'includes ConsoleKit tag when timestamp is enabled' do
      output = OutputHelper.capture_stdout { described_class.send(:print_with, :info, 'Timed', timestamp: true) }
      expect(output).to include('[ConsoleKit]')
    end

    it 'includes message when timestamp is enabled' do
      output = OutputHelper.capture_stdout { described_class.send(:print_with, :info, 'Timed', timestamp: true) }
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
    it 'removes ANSI codes from output' do
      output = OutputHelper.capture_stdout { described_class.print_error('Boom') }
      clean = output.gsub(/\e\[[\d;]+m/, '')
      expect(clean).to include('[ConsoleKit] [✗] Boom')
    end
  end
end
