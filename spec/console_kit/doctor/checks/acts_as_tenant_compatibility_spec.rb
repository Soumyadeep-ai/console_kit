# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ConsoleKit::Doctor::Checks::ActsAsTenantCompatibility do
  subject(:check) { described_class.new(config) }

  let(:config) { ConsoleKit.configuration }

  it 'returns ok when no tenant uses acts_as_tenant_id' do
    config.tenants = { acme: { constants: { shard: 's1', partner_code: 'acme' } } }
    expect(check.call.status).to eq(:ok)
  end

  it 'returns ok when tenants is nil' do
    config.tenants = nil
    expect(check.call.status).to eq(:ok)
  end

  it 'returns ok when tenants is an Array' do
    config.tenants = %i[acme beta]
    expect(check.call.status).to eq(:ok)
  end

  it 'returns ok when a tenant value is nil' do
    config.tenants = { acme: nil }
    expect(check.call.status).to eq(:ok)
  end

  context 'when acts_as_tenant_id is used' do
    before do
      config.tenants = { acme: { constants: { acts_as_tenant_id: 42, shard: 's1', partner_code: 'acme' } } }
    end

    it 'returns warn when ActsAsTenant gem not loaded' do
      hide_const('ActsAsTenant')
      expect(check.call.status).to eq(:warn)
    end

    it 'returns warn when neither model nor finder configured' do
      expect(check.call.status).to eq(:warn)
    end

    it 'returns ok when acts_as_tenant_model is set' do
      config.acts_as_tenant_model = 'Account'
      expect(check.call.status).to eq(:ok)
    end

    it 'returns ok when acts_as_tenant_finder is set' do
      config.acts_as_tenant_finder = ->(_k, _c) {}
      expect(check.call.status).to eq(:ok)
    end

    it 'includes valid in message when fully configured' do
      config.acts_as_tenant_model = 'Account'
      expect(check.call.message).to include('valid')
    end

    it 'returns warn message when model not configured' do
      expect(check.call.message).to include('not configured')
    end
  end
end
