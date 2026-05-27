# spec/console_kit/doctor/checks/tenants_configured_spec.rb
# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ConsoleKit::Doctor::Checks::TenantsConfigured do
  subject(:check) { described_class.new(config) }

  context 'when tenants configured correctly' do
    let(:config) do
      ConsoleKit.configure do |c|
        c.tenants = { a: {} }
        c.context_class = 'Object'
      end
      ConsoleKit.configuration
    end

    it 'returns ok status' do
      expect(check.call.status).to eq(:ok)
    end
  end

  context 'when tenants not configured' do
    let(:config) { ConsoleKit.configuration }

    it 'returns error status' do
      expect(check.call.status).to eq(:error)
    end
  end

  context 'when tenants is not a Hash' do
    let(:config) do
      c = ConsoleKit.configuration
      c.instance_variable_get(:@data)[:tenants] = [:foo]
      c
    end

    it 'returns error status' do
      expect(check.call.status).to eq(:error)
    end
  end
end
