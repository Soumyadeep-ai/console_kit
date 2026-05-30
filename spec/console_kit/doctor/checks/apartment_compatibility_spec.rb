# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ConsoleKit::Doctor::Checks::ApartmentCompatibility do
  subject(:check) { described_class.new(config) }

  let(:config) { ConsoleKit.configuration }

  it 'returns ok when no tenant uses apartment_schema' do
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

  context 'when apartment_schema is used' do
    before do
      config.tenants = { acme: { constants: { apartment_schema: 'acme', shard: 's1', partner_code: 'acme' } } }
    end

    it 'returns warn when Apartment not loaded but schema is configured' do
      hide_const('Apartment')
      expect(check.call.status).to eq(:warn)
    end

    it 'includes helpful message when Apartment not loaded' do
      hide_const('Apartment')
      expect(check.call.message).to include('not loaded')
    end

    it 'returns ok when loaded and version sufficient' do
      spec_double = double(version: Gem::Version.new('2.0.0'))
      allow(Gem).to receive(:loaded_specs).and_return({ 'apartment' => spec_double })
      expect(check.call.status).to eq(:ok)
    end

    it 'includes version in message when ok' do
      spec_double = double(version: Gem::Version.new('2.0.0'))
      allow(Gem).to receive(:loaded_specs).and_return({ 'apartment' => spec_double })
      expect(check.call.message).to include('2.0.0')
    end

    it 'returns error when version below 1.0' do
      spec_double = double(version: Gem::Version.new('0.9.0'))
      allow(Gem).to receive(:loaded_specs).and_return({ 'apartment' => spec_double })
      expect(check.call.status).to eq(:error)
    end

    it 'returns error when gem not in loaded_specs' do
      allow(Gem).to receive(:loaded_specs).and_return({})
      expect(check.call.status).to eq(:error)
    end

    it 'returns error when version comparison raises' do
      allow(Gem).to receive(:loaded_specs).and_return({ 'apartment' => double(version: Gem::Version.new('2.0.0')) })
      allow(Gem::Version).to receive(:new).and_call_original
      allow(Gem::Version).to receive(:new).with('2.0.0').and_raise(StandardError, 'version error')
      expect(check.call.status).to eq(:error)
    end
  end
end
