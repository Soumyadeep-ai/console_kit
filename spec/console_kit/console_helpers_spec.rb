# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ConsoleKit::ConsoleHelpers do
  let(:helper) { Object.new.extend(described_class) }

  before do
    allow(ConsoleKit::Output).to receive(:print_header)
    allow(ConsoleKit::Output).to receive(:print_info)
    allow(ConsoleKit::Output).to receive(:print_warning)
    allow(ConsoleKit::Output).to receive(:print_list)
  end

  describe '#switch_tenant' do
    it 'delegates to ConsoleKit.reset_current_tenant' do
      allow(ConsoleKit).to receive(:reset_current_tenant)
      helper.switch_tenant
      expect(ConsoleKit).to have_received(:reset_current_tenant)
    end
  end

  describe '#tenant_info' do
    context 'when a tenant is configured' do
      before do
        allow(ConsoleKit::Setup).to receive(:current_tenant).and_return('acme')
        allow(ConsoleKit.configuration).to receive(:tenants).and_return(
          'acme' => { constants: { partner_code: 'ACME', shard: 'shard_1', mongo_db: 'acme_db' } }
        )
      end

      it 'prints the tenant header' do
        helper.tenant_info
        expect(ConsoleKit::Output).to have_received(:print_header).with('Tenant: acme')
      end

      it 'prints the partner code' do
        helper.tenant_info
        expect(ConsoleKit::Output).to have_received(:print_info).with(/Partner.*ACME/)
      end

      it 'does not print fields with nil values' do
        helper.tenant_info
        expect(ConsoleKit::Output).not_to have_received(:print_info).with(/ES Prefix/)
      end

      it 'prints fields with falsey non-nil values like 0' do
        allow(ConsoleKit.configuration).to receive(:tenants).and_return(
          'acme' => { constants: { partner_code: 'ACME', shard: 'shard_1', redis_db: 0 } }
        )
        helper.tenant_info
        expect(ConsoleKit::Output).to have_received(:print_info).with(/Redis DB.*0/)
      end

      it 'returns nil' do
        expect(helper.tenant_info).to be_nil
      end
    end

    context 'when no tenant is configured' do
      before do
        allow(ConsoleKit::Setup).to receive(:current_tenant).and_return(nil)
      end

      it 'prints a warning' do
        helper.tenant_info
        expect(ConsoleKit::Output).to have_received(:print_warning).with(/No tenant/)
      end
    end
  end

  describe '#dashboard' do
    it 'delegates to ConsoleKit::Connections::Dashboard.display' do
      allow(ConsoleKit::Connections::Dashboard).to receive(:display)
      helper.dashboard
      expect(ConsoleKit::Connections::Dashboard).to have_received(:display)
    end
  end

  describe '#tenants' do
    before do
      allow(ConsoleKit.configuration).to receive(:tenants).and_return(
        'acme' => {}, 'globex' => {}
      )
    end

    it 'prints the list of tenant names' do
      helper.tenants
      expect(ConsoleKit::Output).to have_received(:print_list).with(%w[acme globex], header: 'Available Tenants')
    end

    it 'returns the tenant names' do
      expect(helper.tenants).to eq(%w[acme globex])
    end
  end
end
