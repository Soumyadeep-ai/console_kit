# spec/console_kit/doctor/checks/required_constants_present_spec.rb
# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ConsoleKit::Doctor::Checks::RequiredConstantsPresent do
  subject(:check) { described_class.new(config) }

  let(:config) { ConsoleKit.configuration }

  context 'when no tenants configured' do
    it 'returns ok status' do
      expect(check.call.status).to eq(:ok)
    end

    it 'returns no-tenants message' do
      expect(check.call.message).to eq('no tenants to validate')
    end
  end

  context 'when all required constants are present' do
    before do
      config.required_tenant_keys = [:shard]
      config.tenants = {
        alpha: { constants: { shard: 'shard_a' } }
      }
    end

    it 'returns ok status' do
      expect(check.call.status).to eq(:ok)
    end

    it 'returns all present message' do
      expect(check.call.message).to eq('all required constants present')
    end
  end

  context 'when a required constant is missing' do
    before do
      config.required_tenant_keys = [:shard]
      config.tenants = {
        alpha: { constants: {} }
      }
    end

    it 'returns warn status' do
      expect(check.call.status).to eq(:warn)
    end

    it 'names the missing key in the message' do
      expect(check.call.message).to include('shard')
    end
  end

  context 'when tenant_config is nil' do
    before do
      config.required_tenant_keys = [:shard]
      config.tenants = { alpha: nil }
    end

    it 'returns warn status' do
      expect(check.call.status).to eq(:warn)
    end
  end

  context 'when tenants is an Array (not a Hash)' do
    before do
      config.tenants = %i[tenant_a tenant_b]
      config.tenant_resolver = ->(key) { key }
    end

    it 'skips the check and returns ok' do
      expect(check.call.status).to eq(:ok)
    end

    it 'returns skipped message' do
      expect(check.call.message).to include('not a Hash')
    end
  end
end
