# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ConsoleKit::FiberStorage do
  after { described_class[:test_key] = nil }

  it 'stores and retrieves a value' do
    described_class[:test_key] = 'hello'
    expect(described_class[:test_key]).to eq('hello')
  end

  it 'returns nil for unset key' do
    expect(described_class[:test_key]).to be_nil
  end

  it 'stores values per fiber' do
    result = nil
    Fiber.new { result = described_class[:test_key] }.resume
    expect(result).to be_nil
  end

  it 'falls back to Thread.current when Fiber does not support []' do
    allow(Fiber.current).to receive(:respond_to?).with(:[]).and_return(false)
    described_class.instance_variable_set(:@fiber_capable, nil)
    expect { described_class[:test_key] = 'x' }.not_to raise_error
    described_class.instance_variable_set(:@fiber_capable, nil)
  end

  it 'uses Fiber.current storage when fiber is capable' do
    described_class.instance_variable_set(:@fiber_capable, true)
    storage_obj = described_class.send(:storage)
    described_class.instance_variable_set(:@fiber_capable, nil)
    expect(storage_obj).to eq(Fiber.current)
  end

  it 'returns false when detect_fiber_capability raises StandardError' do
    described_class.instance_variable_set(:@fiber_capable, nil)
    allow(Fiber.current).to receive(:respond_to?).with(:[]).and_raise(StandardError, 'fiber error')
    # After resetting cache, the detection will run and catch the error
    result = described_class.send(:detect_fiber_capability)
    expect(result).to be false
    described_class.instance_variable_set(:@fiber_capable, nil)
  end
end
