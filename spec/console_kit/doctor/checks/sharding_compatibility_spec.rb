# spec/console_kit/doctor/checks/sharding_compatibility_spec.rb
# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ConsoleKit::Doctor::Checks::ShardingCompatibility do
  subject(:check) { described_class.new(config) }

  let(:config) { ConsoleKit.configuration }

  it 'returns ok when sharding disabled' do
    config.use_rails_sharding = false
    expect(check.call.status).to eq(:ok)
  end

  it 'returns error when sharding enabled but Rails < 6.1' do
    config.use_rails_sharding = true
    stub_const('Rails::VERSION::STRING', '6.0.0')
    expect(check.call.status).to eq(:error)
  end

  it 'returns ok when sharding enabled and Rails >= 6.1' do
    config.use_rails_sharding = true
    stub_const('Rails::VERSION::STRING', '6.1.0')
    expect(check.call.status).to eq(:ok)
  end

  it 'returns error when sharding enabled but Rails not defined' do
    config.use_rails_sharding = true
    hide_const('Rails::VERSION::STRING')
    expect(check.call.status).to eq(:error)
  end
end
