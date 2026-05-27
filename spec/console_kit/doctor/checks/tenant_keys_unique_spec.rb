# spec/console_kit/doctor/checks/tenant_keys_unique_spec.rb
# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ConsoleKit::Doctor::Checks::TenantKeysUnique do
  subject(:check) { described_class.new(config) }

  let(:config) { ConsoleKit.configuration }

  context 'when no tenants configured' do
    it 'returns ok status' do
      expect(check.call.status).to eq(:ok)
    end

    it 'returns no-tenants message' do
      expect(check.call.message).to eq('no tenants to check')
    end
  end

  context 'when tenants have unique keys' do
    before { config.tenants = { a: {}, b: {} } }

    it 'returns ok status' do
      expect(check.call.status).to eq(:ok)
    end

    it 'returns unique message' do
      expect(check.call.message).to eq('tenant keys unique')
    end
  end

  context 'when tenants is :dynamic' do
    before { config.tenants = :dynamic }

    it 'returns ok status' do
      expect(check.call.status).to eq(:ok)
    end

    it 'returns dynamic mode message' do
      expect(check.call.message).to include('not applicable in :dynamic mode')
    end
  end

  context 'when tenant keys are duplicated after stringification' do
    # Ruby Hashes cannot truly have duplicate keys, so we stub #keys to simulate
    # a scenario where :a and "a" would both map to the same string.
    before do
      config.tenants = { a: {} }
      allow(config.tenants).to receive(:keys).and_return(%i[a a])
    end

    it 'returns error status' do
      expect(check.call.status).to eq(:error)
    end

    it 'names the duplicate key in the message' do
      expect(check.call.message).to include('a')
    end
  end
end
