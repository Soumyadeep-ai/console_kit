# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ConsoleKit::Output do
  before { ConsoleKit.configure { |c| c.pretty_output = pretty_output } }

  let(:pretty_output) { true }

  shared_examples 'ConsoleKit output formatter' do |method, message:, symbol:, color_code: nil|
    it "prints #{method} with correct formatting (pretty_output: #{ConsoleKit.configuration.pretty_output})" do
      output = OutputHelper.capture_stdout { described_class.send(method, message) }

      expect(output).to include('[ConsoleKit]')
      expect(output).to include(symbol) if symbol

      if ConsoleKit.configuration.pretty_output && color_code
        expect(output).to match(/\e\[#{color_code}m/)
        expect(output).to match(/\e\[0m/)
      else
        expect(output).not_to match(/\e\[[\d;]+m/)
      end

      expected_line =
        if method == :print_header
          "[ConsoleKit] \n=== #{message} ==="
        else
          line = '[ConsoleKit] '
          line += "#{symbol} " if symbol
          line += message
          line
        end

      expect(output).to include(expected_line)
    end
  end

  describe 'standard outputs' do
    include_examples 'ConsoleKit output formatter', :print_success, message: 'All good', symbol: '[✓]',
                                                                    color_code: '1;32'
    include_examples 'ConsoleKit output formatter', :print_error, message: 'Something broke', symbol: '[✗]',
                                                                  color_code: '1;31'
    include_examples 'ConsoleKit output formatter', :print_warning, message: 'Careful now', symbol: '[!]',
                                                                    color_code: '1;33'
    include_examples 'ConsoleKit output formatter', :print_info, message: 'Heads up', symbol: nil, color_code: nil
    include_examples 'ConsoleKit output formatter', :print_prompt, message: 'Input please', symbol: nil,
                                                                   color_code: '1;36'
    include_examples 'ConsoleKit output formatter', :print_header, message: 'Section Start', symbol: nil,
                                                                   color_code: '1;34'
  end

  describe '#print_backtrace' do
    let(:exception) do
      e = RuntimeError.new('Something bad happened')
      e.set_backtrace(['lib/foo.rb:10', 'app/bar.rb:20'])
      e
    end

    it 'prints each backtrace line' do
      output = OutputHelper.capture_stdout { described_class.print_backtrace(exception) }
      expect(output).to include('lib/foo.rb:10')
      expect(output).to include('app/bar.rb:20')

      if pretty_output
        expect(output).to match(%r{\e\[0;90m\[ConsoleKit\]     lib/foo\.rb:10\e\[0m})
      else
        expect(output).to include('[ConsoleKit]     lib/foo.rb:10')
        expect(output).not_to match(/\e\[/)
      end
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

    it 'includes timestamp if enabled' do
      output = OutputHelper.capture_stdout { described_class.send(:print_with, :info, 'Timed', timestamp: true) }

      expect(output).to include('[2025-08-12 15:45:12]')
      expect(output).to include('[ConsoleKit]')
      expect(output).to include('Timed')
    end
  end

  describe 'pretty_output false' do
    let(:pretty_output) { false }

    include_examples 'ConsoleKit output formatter', :print_success, message: 'Plain OK', symbol: '[✓]',
                                                                    color_code: '1;32'
    include_examples 'ConsoleKit output formatter', :print_error, message: 'Plain error', symbol: '[✗]',
                                                                  color_code: '1;31'
    include_examples 'ConsoleKit output formatter', :print_warning, message: 'Plain warning', symbol: '[!]',
                                                                    color_code: '1;33'
    include_examples 'ConsoleKit output formatter', :print_info, message: 'Plain info', symbol: nil, color_code: nil
    include_examples 'ConsoleKit output formatter', :print_prompt, message: 'No color prompt', symbol: nil,
                                                                   color_code: '1;36'
    include_examples 'ConsoleKit output formatter', :print_header, message: 'No color header', symbol: nil,
                                                                   color_code: '1;34'
  end

  describe 'ANSI output readability' do
    it 'removes ANSI codes correctly from output' do
      output = OutputHelper.capture_stdout { described_class.print_error('Boom') }
      clean = output.gsub(/\e\[[\d;]+m/, '')
      expect(clean).to include('[ConsoleKit] [✗] Boom')
    end
  end
end
