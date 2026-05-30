# spec/console_kit/null_benchmarker_spec.rb
# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ConsoleKit::NullBenchmarker do
  subject(:bm) { described_class.new }

  it 'yields block in wrap' do
    result = bm.wrap('Step') { 99 }
    expect(result).to eq(99)
  end

  it 'returns empty timings' do
    expect(bm.timings).to eq({})
  end

  it 'returns nil for slowest_step' do
    expect(bm.slowest_step).to be_nil
  end

  it 'does not raise on start_memory_tracking' do
    expect { bm.start_memory_tracking }.not_to raise_error
  end

  it 'does not raise on report' do
    expect { bm.report(:any_tenant) }.not_to raise_error
  end
end
