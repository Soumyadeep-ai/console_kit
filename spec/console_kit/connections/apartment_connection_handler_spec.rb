# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ConsoleKit::Connections::ApartmentConnectionHandler do
  let(:context) { double('Context', tenant_apartment_schema: 'acme', partner_identifier: 'acme') } # rubocop:disable RSpec/VerifiedDoubles
  let(:handler) { described_class.new(context) }

  before do
    allow(Apartment::Tenant).to receive(:switch!)
    allow(Apartment::Tenant).to receive(:current).and_return('acme')
    allow(ConsoleKit::Output).to receive(:print_info)
  end

  describe '#connect' do
    it 'calls Apartment::Tenant.switch! with the schema' do
      handler.connect
      expect(Apartment::Tenant).to have_received(:switch!).with('acme')
    end

    context 'when tenant_apartment_schema is nil' do
      let(:context) { double('Context', tenant_apartment_schema: nil, partner_identifier: 'beta') } # rubocop:disable RSpec/VerifiedDoubles

      it 'falls back to partner_identifier' do
        handler.connect
        expect(Apartment::Tenant).to have_received(:switch!).with('beta')
      end
    end

    context 'when tenant_apartment_schema is blank string' do
      let(:context) { double('Context', tenant_apartment_schema: '', partner_identifier: 'gamma') } # rubocop:disable RSpec/VerifiedDoubles

      it 'falls back to partner_identifier' do
        handler.connect
        expect(Apartment::Tenant).to have_received(:switch!).with('gamma')
      end
    end
  end

  describe '#available?' do
    it 'returns true when Apartment is defined' do
      expect(handler).to be_available
    end

    it 'returns false when Apartment is not defined' do
      hide_const('Apartment')
      expect(handler).not_to be_available
    end
  end

  describe '#diagnostics' do
    context 'when Apartment is available and schema matches' do
      it 'returns name Apartment' do
        expect(handler.diagnostics[:name]).to eq('Apartment')
      end

      it 'returns status :connected' do
        expect(handler.diagnostics[:status]).to eq(:connected)
      end

      it 'returns nil latency_ms' do
        expect(handler.diagnostics[:latency_ms]).to be_nil
      end

      it 'includes schema in details' do
        expect(handler.diagnostics[:details]).to include(:schema)
      end
    end

    context 'when schema does not match current' do
      before { allow(Apartment::Tenant).to receive(:current).and_return('other') }

      it 'returns status :error' do
        expect(handler.diagnostics[:status]).to eq(:error)
      end
    end

    context 'when Apartment is not defined' do
      before { hide_const('Apartment') }

      it 'returns status :unavailable' do
        expect(handler.diagnostics[:status]).to eq(:unavailable)
      end

      it 'returns empty details' do
        expect(handler.diagnostics[:details]).to eq({})
      end
    end

    context 'when diagnostics raises' do
      before { allow(Apartment::Tenant).to receive(:current).and_raise(StandardError, 'db down') }

      it 'returns status :error' do
        expect(handler.diagnostics[:status]).to eq(:error)
      end

      it 'includes error message in details' do
        expect(handler.diagnostics[:details][:error]).to include('db down')
      end
    end
  end
end
