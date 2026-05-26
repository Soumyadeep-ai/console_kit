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

  it 'does not raise on unsupported Ruby versions' do
    allow(Fiber.current).to receive(:respond_to?).with(:[]).and_return(false)
    described_class.instance_variable_set(:@fiber_capable, nil)
    expect { described_class[:test_key] = 'x' }.not_to raise_error
    described_class.instance_variable_set(:@fiber_capable, nil)
  end
end
