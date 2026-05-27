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
end
