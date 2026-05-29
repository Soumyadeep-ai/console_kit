# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ConsoleKit::Connections::ActsAsTenantConnectionHandler do
  let(:tenant_record) { double('Account', id: 42) } # rubocop:disable RSpec/VerifiedDoubles
  let(:context) do
    double('Context', tenant_acts_as_tenant_id: 42, partner_identifier: 'acme', # rubocop:disable RSpec/VerifiedDoubles
                      tenant_shard: nil, tenant_mongo_db: nil, tenant_redis_db: nil,
                      tenant_elasticsearch_prefix: nil, tenant_apartment_schema: nil)
  end
  let(:handler) { described_class.new(context) }

  before do
    stub_const('Account', Class.new { def self.find_by(*); end })
    allow(Account).to receive(:find_by).and_return(tenant_record)
    allow(ActsAsTenant).to receive(:current_tenant=)
    allow(ConsoleKit::Output).to receive(:print_info)
    ConsoleKit.configure { |c| c.acts_as_tenant_model = 'Account' }
  end

  describe '#connect — direct ID mode' do
    it 'finds record by id' do
      handler.connect
      expect(Account).to have_received(:find_by).with(id: 42)
    end

    it 'sets ActsAsTenant.current_tenant to found record' do
      handler.connect
      expect(ActsAsTenant).to have_received(:current_tenant=).with(tenant_record)
    end

    context 'when tenant_acts_as_tenant_id is nil' do
      let(:context) do
        double('Context', tenant_acts_as_tenant_id: nil, partner_identifier: 'acme', # rubocop:disable RSpec/VerifiedDoubles
                          tenant_shard: nil, tenant_mongo_db: nil, tenant_redis_db: nil,
                          tenant_elasticsearch_prefix: nil, tenant_apartment_schema: nil)
      end

      it 'sets current_tenant to nil' do
        handler.connect
        expect(ActsAsTenant).to have_received(:current_tenant=).with(nil)
      end
    end

    context 'when model not found' do
      before { allow(Account).to receive(:find_by).and_return(nil) }

      it 'sets current_tenant to nil' do
        handler.connect
        expect(ActsAsTenant).to have_received(:current_tenant=).with(nil)
      end
    end

    context 'when acts_as_tenant_model not configured' do
      before { ConsoleKit.configure { |c| c.acts_as_tenant_model = nil } }

      it 'sets current_tenant to nil' do
        handler.connect
        expect(ActsAsTenant).to have_received(:current_tenant=).with(nil)
      end
    end

    context 'when model class cannot be resolved' do
      before { ConsoleKit.configure { |c| c.acts_as_tenant_model = 'NonExistentModel' } }

      it 'sets current_tenant to nil without raising' do
        handler.connect
        expect(ActsAsTenant).to have_received(:current_tenant=).with(nil)
      end
    end
  end

  describe '#connect — custom finder mode' do
    before do
      ConsoleKit.configure { |c| c.acts_as_tenant_finder = ->(_key, _cfg) { tenant_record } }
    end

    it 'calls finder and sets current_tenant' do
      handler.connect
      expect(ActsAsTenant).to have_received(:current_tenant=).with(tenant_record)
    end

    it 'does not call model find_by' do
      handler.connect
      expect(Account).not_to have_received(:find_by)
    end
  end

  describe '#available?' do
    it 'returns true when ActsAsTenant is defined' do
      expect(handler).to be_available
    end

    it 'returns false when ActsAsTenant is not defined' do
      hide_const('ActsAsTenant')
      expect(handler).not_to be_available
    end
  end

  describe '#diagnostics' do
    context 'when tenant is set' do
      let(:current_tenant) { double('Tenant', id: 42, class: double(name: 'Account')) } # rubocop:disable RSpec/VerifiedDoubles

      before do
        allow(ActsAsTenant).to receive(:current_tenant).and_return(current_tenant)
        allow(current_tenant).to receive(:try).with(:id).and_return(42)
        allow(current_tenant).to receive(:present?).and_return(true)
      end

      it 'returns name ActsAsTenant' do
        expect(handler.diagnostics[:name]).to eq('ActsAsTenant')
      end

      it 'returns status :connected' do
        expect(handler.diagnostics[:status]).to eq(:connected)
      end

      it 'returns nil latency_ms' do
        expect(handler.diagnostics[:latency_ms]).to be_nil
      end

      it 'includes tenant_id in details' do
        expect(handler.diagnostics[:details]).to include(:tenant_id)
      end

      it 'includes tenant_class in details' do
        expect(handler.diagnostics[:details]).to include(:tenant_class)
      end
    end

    context 'when current_tenant is nil' do
      before { allow(ActsAsTenant).to receive(:current_tenant).and_return(nil) }

      it 'returns status :error' do
        expect(handler.diagnostics[:status]).to eq(:error)
      end
    end

    context 'when ActsAsTenant not defined' do
      before { hide_const('ActsAsTenant') }

      it 'returns status :unavailable' do
        expect(handler.diagnostics[:status]).to eq(:unavailable)
      end

      it 'returns empty details' do
        expect(handler.diagnostics[:details]).to eq({})
      end
    end

    context 'when diagnostics raises' do
      before { allow(ActsAsTenant).to receive(:current_tenant).and_raise(StandardError, 'tenant error') }

      it 'returns status :error' do
        expect(handler.diagnostics[:status]).to eq(:error)
      end

      it 'includes error message in details' do
        expect(handler.diagnostics[:details][:error]).to include('tenant error')
      end
    end
  end
end
