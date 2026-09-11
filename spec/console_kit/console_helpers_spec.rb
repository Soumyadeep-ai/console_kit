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

    # A configuration reload can drop a tenant while the state store still
    # points at it. Reporting on that tenant must degrade, not raise.
    context 'when the current tenant is no longer in the configuration' do
      before do
        allow(ConsoleKit::Setup).to receive(:current_tenant).and_return('ghost')
        allow(ConsoleKit.configuration).to receive(:tenants).and_return('acme' => { constants: {} })
      end

      it 'still names the tenant it was asked about' do
        helper.tenant_info
        expect(ConsoleKit::Output).to have_received(:print_header).with('Tenant: ghost')
      end

      it 'prints no details rather than raising on the missing entry' do
        helper.tenant_info
        expect(ConsoleKit::Output).not_to have_received(:print_info)
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
    before { allow(ConsoleKit::Connections::Dashboard).to receive(:display) }

    it 'delegates to ConsoleKit::Connections::Dashboard.display' do
      helper.dashboard
      expect(ConsoleKit::Connections::Dashboard).to have_received(:display)
    end

    it 'asks for the cheap basic level when called with no arguments' do
      helper.dashboard
      expect(ConsoleKit::Connections::Dashboard).to have_received(:display).with(level: :basic)
    end

    it 'passes an explicit level through' do
      helper.dashboard(level: :full)
      expect(ConsoleKit::Connections::Dashboard).to have_received(:display).with(level: :full)
    end

    it 'returns itself so the console prints nothing noisy' do
      expect(helper.dashboard).to be(helper)
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

    context 'when nothing has been configured yet' do
      before { allow(ConsoleKit.configuration).to receive(:tenants).and_return(nil) }

      it 'returns an empty list rather than raising' do
        expect(helper.tenants).to eq([])
      end
    end
  end
end
