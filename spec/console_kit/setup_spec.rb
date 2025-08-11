# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ConsoleKit do
  let(:tenants) do
    {
      'acme' => { constants: { shard: 'shard_acme', mongo_db: 'acme_db', partner_code: 'ACME' } },
      'globex' => { constants: { shard: 'shard_globex', mongo_db: 'globex_db', partner_code: 'GBX' } }
    }
  end

  let(:context_class) do
    Class.new do
      class << self
        attr_accessor :tenant_shard, :tenant_mongo_db, :partner_identifier
      end
    end
  end

  before do
    described_class.configure do |config|
      config.tenants = tenants
      config.context_class = context_class
    end

    described_class.instance_variable_set(:@current_tenant, nil)
  end

  describe '.configure' do
    it 'yields itself for config block' do
      yielded = nil
      ConsoleKit.configure { |conf| yielded = conf }
      expect(yielded).to eq(ConsoleKit)
    end
  end

  describe '.tenant_setup_successful?' do
    it 'returns true if tenant is present' do
      described_class.instance_variable_set(:@current_tenant, 'acme')
      expect(described_class.tenant_setup_successful?).to be true
    end

    it 'returns false if no tenant is set' do
      described_class.instance_variable_set(:@current_tenant, nil)
      expect(described_class.tenant_setup_successful?).to be false
    end
  end

  describe '.setup' do
    it 'sets up tenant successfully via TenantConfigurator' do
      allow(ConsoleKit::TenantSelector).to receive(:select).and_return('acme')
      expect(ConsoleKit::TenantConfigurator).to receive(:configure_tenant).and_call_original
      expect(ConsoleKit::Output).to receive(:print_success).with(/Tenant set to: acme/)
      expect(ConsoleKit::Output).to receive(:print_success).with(/Tenant initialized: acme/)
      ConsoleKit.setup
      expect(described_class.current_tenant).to eq('acme')
    end

    it 'sets @current_tenant after setup' do
      allow($stdin).to receive(:tty?).and_return(true)
      allow(ConsoleKit::TenantSelector).to receive(:select).and_return('globex')
      allow(ConsoleKit::TenantConfigurator).to receive(:configure_tenant).and_return(true)
      allow(ConsoleKit::Output).to receive(:print_success)
      described_class.setup
      expect(described_class.current_tenant).to eq('globex')
    end

    it 'does not set @current_tenant if configuration fails' do
      allow(ConsoleKit::TenantSelector).to receive(:select).and_return('acme')
      allow(ConsoleKit::TenantConfigurator).to receive(:configure_tenant).and_return(false)
      expect(ConsoleKit::Output).not_to receive(:print_success)
      described_class.setup
      expect(described_class.current_tenant).to be_nil
    end

    it 'prints error when tenants is nil' do
      described_class.tenants = nil
      expect(ConsoleKit::Output).to receive(:print_error).with(/No tenants configured/)
      described_class.setup
    end

    it 'prints error when tenants are empty' do
      described_class.tenants = {}
      expect(ConsoleKit::Output).to receive(:print_error).with(/No tenants configured/)
      described_class.setup
    end

    it 'prints error if tenant selection returns nil' do
      allow($stdin).to receive(:tty?).and_return(true)
      allow(ConsoleKit::TenantSelector).to receive(:select).and_return(nil)
      expect(ConsoleKit::Output).to receive(:print_error).with(/No tenant selected/)
      described_class.setup
    end

    it 'rescues and prints setup error' do
      allow(ConsoleKit::TenantSelector).to receive(:select).and_return('acme')
      allow(ConsoleKit::TenantConfigurator).to receive(:configure_tenant).and_raise(StandardError.new('Boom'))
      expect(ConsoleKit::Output).to receive(:print_error).with(/Error setting up tenant: Boom/)
      expect(ConsoleKit::Output).to receive(:print_backtrace)
      described_class.setup
    end

    context 'with single tenant & non-interactive mode' do
      before do
        described_class.tenants = { 'solo' => tenants['acme'] }
        allow($stdin).to receive(:tty?).and_return(false)
      end

      it 'auto-picks the only tenant' do
        expect(ConsoleKit::TenantConfigurator).to receive(:configure_tenant).and_call_original
        described_class.setup
        expect(described_class.current_tenant).to eq('solo')
      end
    end

    context 'in non-interactive mode' do
      before { allow($stdin).to receive(:tty?).and_return(false) }

      it 'auto-selects tenant when multiple tenants are available' do
        allow(ConsoleKit::TenantConfigurator).to receive(:configure_tenant).and_call_original
        allow(ConsoleKit::Output).to receive(:print_success)

        described_class.setup
        expect(%w[acme globex]).to include(described_class.current_tenant)
      end
    end

    context 'when tenant key is invalid or empty' do
      it 'prints error if tenant key is nil' do
        allow(ConsoleKit::TenantSelector).to receive(:select).and_return(nil)
        expect(ConsoleKit::Output).to receive(:print_error).with(/No tenant selected/)
        described_class.setup
      end

      it 'prints error if tenant key is an empty string' do
        allow(ConsoleKit::TenantSelector).to receive(:select).and_return('')
        expect(ConsoleKit::Output).to receive(:print_error).with(/No configuration found for tenant/)
        described_class.setup
      end
    end

    context 'when tenant configuration raises errors' do
      it 'handles StandardError and logs it' do
        allow(ConsoleKit::TenantSelector).to receive(:select).and_return('acme')
        allow(ConsoleKit::TenantConfigurator).to receive(:configure_tenant).and_raise(StandardError, 'Boom')
        expect(ConsoleKit::Output).to receive(:print_error).with(/Boom/)
        expect(ConsoleKit::Output).to receive(:print_backtrace)
        described_class.setup
      end

      it 'handles RuntimeError gracefully' do
        allow(ConsoleKit::TenantSelector).to receive(:select).and_return('acme')
        allow(ConsoleKit::TenantConfigurator).to receive(:configure_tenant).and_raise(RuntimeError, 'Unexpected error')
        expect(ConsoleKit::Output).to receive(:print_error).with(/Unexpected error/)
        expect(ConsoleKit::Output).to receive(:print_backtrace)
        described_class.setup
      end
    end

    context 'with only one tenant configured' do
      before do
        described_class.tenants = { 'only_one' => tenants['acme'] }
        allow($stdin).to receive(:tty?).and_return(true)
      end

      it 'auto-selects the only tenant' do
        allow(ConsoleKit::TenantConfigurator).to receive(:configure_tenant).and_call_original
        allow(ConsoleKit::Output).to receive(:print_success)
        described_class.setup
        expect(described_class.current_tenant).to eq('only_one')
      end
    end

    context 'when context_class is nil' do
      it 'does not crash if context_class is not defined' do
        described_class.context_class = nil
        allow(ConsoleKit::TenantSelector).to receive(:select).and_return('acme')
        allow(ConsoleKit::TenantConfigurator).to receive(:configure_tenant).with('acme', tenants, nil).and_return(true)
        allow(ConsoleKit::Output).to receive(:print_success)

        described_class.setup
        expect(described_class.current_tenant).to eq('acme')
      end
    end

    context 'with symbol keys in tenant config' do
      it 'handles symbol keys safely' do
        described_class.tenants = {
          acme: { constants: { shard: 'shard_acme', mongo_db: 'acme_db', partner_code: 'ACME' } }
        }

        allow(ConsoleKit::TenantSelector).to receive(:select).and_return(:acme)
        allow(ConsoleKit::TenantConfigurator).to receive(:configure_tenant).and_call_original
        allow(ConsoleKit::Output).to receive(:print_success)

        described_class.setup
        expect(described_class.current_tenant).to eq(:acme)
      end
    end
  end

  describe '.reset_current_tenant' do
    context 'when tenants are not configured' do
      it 'prints warning and returns false' do
        described_class.tenants = nil
        expect(ConsoleKit::Output).to receive(:print_warning).with(/Cannot reset tenant/)
        expect(described_class.reset_current_tenant).to be false
      end
    end

    context 'when current tenant is set' do
      before do
        described_class.instance_variable_set(:@current_tenant, 'acme')
      end

      it 'clears the current configuration and resets tenant' do
        allow(ConsoleKit::TenantConfigurator).to receive(:clear)
        allow(ConsoleKit::TenantSelector).to receive(:select).and_return('globex')
        allow(ConsoleKit::TenantConfigurator).to receive(:configure_tenant).and_return(true)
        allow(ConsoleKit::Output).to receive(:print_success)
        expect(ConsoleKit::Output).to receive(:print_warning).with(/Resetting tenant: acme/)
        described_class.reset_current_tenant
        expect(described_class.current_tenant).to eq('globex')
      end
    end

    context 'when setup fails after reset' do
      before do
        described_class.instance_variable_set(:@current_tenant, 'acme')
      end

      it 'returns false if no tenant is selected' do
        allow(ConsoleKit::TenantConfigurator).to receive(:clear)
        allow(ConsoleKit::TenantSelector).to receive(:select).and_return(nil)
        allow(ConsoleKit::Output).to receive(:print_error)
        expect(ConsoleKit.reset_current_tenant).to be false
      end
    end
  end
end
