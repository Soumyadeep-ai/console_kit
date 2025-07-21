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
    end.to output(/line 1.*line 2/).to_stdout
  end
end
