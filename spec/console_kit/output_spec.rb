# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ConsoleKit::Output do
  it 'prints success message' do
    expect { described_class.print_success('OK') }.to output(/OK/).to_stdout
  end

  it 'prints error message' do
    expect { described_class.print_error('Fail') }.to output(/\[✗\] Fail/).to_stdout
  end

  it 'prints warning message' do
    expect { described_class.print_warning('Careful') }.to output(/\[!\] Careful/).to_stdout
  end

  it 'prints backtrace lines' do
    exception = RuntimeError.new('fail')
    exception.set_backtrace(['line 1', 'line 2'])
    expect do
      described_class.print_backtrace(exception)
    end.to output(/\e\[0;90m\[ConsoleKit\]     line 1\e\[0m\n\e\[0;90m\[ConsoleKit\]     line 2\e\[0m\n/).to_stdout
  end

  it 'prints plain info message' do
    expect { described_class.print_info('Informing') }.to output(/\[ConsoleKit\] Informing/).to_stdout
  end

  it 'prints header with ANSI bold blue' do
    expect do
      described_class.print_header('Section Start')
    end.to output(/\e\[1;34m\[ConsoleKit\] \n=== Section Start ===\e\[0m/).to_stdout
  end

  it 'prints prompt with ANSI cyan' do
    expect do
      described_class.print_prompt('Enter something:')
    end.to output(/\e\[1;36m\[ConsoleKit\] Enter something:\e\[0m/).to_stdout
  end

  it 'prints without color when no color is given' do
    expect { described_class.send(:print_message, 'No color') }.to output("[ConsoleKit] No color\n").to_stdout
  end

  it 'prints multiline backtrace aligned' do
    exception = RuntimeError.new('Oops')
    exception.set_backtrace(['app/models/user.rb:1', 'lib/tasks/debug.rb:42'])
    output = capture_stdout { described_class.print_backtrace(exception) }
    expect(output).to include('    app/models/user.rb')
    expect(output).to include('    lib/tasks/debug.rb')
  end

  it 'outputs readable text without ANSI' do
    output = capture_stdout { described_class.print_error('Broken') }
    no_ansi = output.gsub(/\e\[[\d;]*m/, '')
    expect(no_ansi).to include('[ConsoleKit] [✗] Broken')
  end

  shared_examples 'a ConsoleKit message' do |method, expected_output|
    it "prints with method #{method}" do
      expect { described_class.send(method, 'test') }.to output(/#{expected_output}/).to_stdout
    end
  end

  include_examples 'a ConsoleKit message', :print_success, '✓'
  include_examples 'a ConsoleKit message', :print_error, '✗'
  include_examples 'a ConsoleKit message', :print_warning, '!'

  private

  def capture_stdout
    original_stdout = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = original_stdout
  end
end
