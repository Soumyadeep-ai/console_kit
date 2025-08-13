# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ConsoleKit::Setup do
  let(:tenants) do
    {
      'acme' => { constants: { shard: 'shard_acme', mongo_db: 'acme_db', partner_code: 'ACME' } },
      'globex' => { constants: { shard: 'shard_globex', mongo_db: 'globex_db', partner_code: 'GBX' } }
    }
  end

  let(:context_class) do
    Class.new do
      class << self
        %i[tenant_shard tenant_mongo_db partner_identifier].each do |attr|
          define_method(attr) { instance_variable_get("@#{attr}") }
          define_method("#{attr}=") { |val| instance_variable_set("@#{attr}", val) }
        end
      end
    end
  end

  def stub_successful_setup(tenant)
    allow(ConsoleKit::TenantSelector).to receive(:select).and_return(tenant)
    allow(ConsoleKit::TenantConfigurator).to receive(:configure_tenant).with(tenant, anything,
                                                                             anything).and_return(true)
  end

  shared_examples 'a successful tenant setup' do |tenant|
    it "sets current_tenant to #{tenant}" do
      stub_successful_setup(tenant)
      ConsoleKit::Setup.setup
      expect(ConsoleKit::Setup.current_tenant).to eq(tenant)
    end
  end

  before do
    ConsoleKit.configure do |config|
      config.tenants = tenants
      config.context_class = context_class
    end
    ConsoleKit::Setup.instance_variable_set(:@current_tenant, nil)
    allow(ConsoleKit::Output).to receive(:print_success)
  end

  describe '.tenant_setup_successful?' do
    it 'returns true if current_tenant is set' do
      ConsoleKit::Setup.instance_variable_set(:@current_tenant, 'acme')
      expect(described_class.tenant_setup_successful?).to be true
    end

    it 'returns false if current_tenant is nil' do
      ConsoleKit::Setup.instance_variable_set(:@current_tenant, nil)
      expect(described_class.tenant_setup_successful?).to be false
    end
  end

  describe '.setup' do
    include_examples 'a successful tenant setup', 'acme'

    context 'with successful tenant setup' do
      it 'sets current_tenant correctly' do
        stub_successful_setup('acme')
        described_class.setup
        expect(described_class.current_tenant).to eq('acme')
      end
    end

    context 'when configuration fails' do
      it 'does not set current_tenant' do
        allow(ConsoleKit::TenantSelector).to receive(:select).and_return('acme')
        allow(ConsoleKit::TenantConfigurator).to receive(:configure_tenant).and_return(false)
        described_class.setup
        expect(described_class.current_tenant).to be_nil
      end
    end

    context 'when no tenants are configured' do
      it 'prints an error when tenants are nil' do
        ConsoleKit.configure { |c| c.tenants = nil }
        expect(ConsoleKit::Output).to receive(:print_error).with(/No tenants configured/)
        described_class.setup
      end

      it 'prints an error when tenants are empty' do
        ConsoleKit.configure { |c| c.tenants = {} }
        expect(ConsoleKit::Output).to receive(:print_error).with(/No tenants configured/)
        described_class.setup
      end
    end

    context 'when tenant selection fails' do
      before { allow($stdin).to receive(:tty?).and_return(true) }

      it 'prints error if tenant selection returns nil' do
        allow(ConsoleKit::TenantSelector).to receive(:select).and_return(nil)
        expect(ConsoleKit::Output).to receive(:print_error).with(/No tenant selected/)
        described_class.setup
      end

      it 'prints error if tenant selection returns empty string' do
        allow(ConsoleKit::TenantSelector).to receive(:select).and_return('')
        expect(ConsoleKit::Output).to receive(:print_error).with(/No configuration found for tenant:/)
        described_class.setup
      end
    end

    context 'when configure_tenant raises an error' do
      it 'prints the error and backtrace for StandardError' do
        allow(ConsoleKit::TenantSelector).to receive(:select).and_return('acme')
        allow(ConsoleKit::TenantConfigurator).to receive(:configure_tenant).and_raise(StandardError, 'Boom')
        expect(ConsoleKit::Output).to receive(:print_error).with(/Boom/)
        expect(ConsoleKit::Output).to receive(:print_backtrace)
        described_class.setup
      end

      it 'prints the error and backtrace for RuntimeError' do
        allow(ConsoleKit::TenantSelector).to receive(:select).and_return('acme')
        allow(ConsoleKit::TenantConfigurator).to receive(:configure_tenant).and_raise(RuntimeError, 'Unexpected error')
        expect(ConsoleKit::Output).to receive(:print_error).with(/Unexpected error/)
        expect(ConsoleKit::Output).to receive(:print_backtrace)
        described_class.setup
      end
    end

    context 'auto-selection behavior' do
      context 'with single tenant' do
        before { ConsoleKit.configure { |c| c.tenants = { 'only_one' => tenants['acme'] } } }

        it 'auto-selects the only tenant in interactive mode' do
          allow($stdin).to receive(:tty?).and_return(true)
          expect(ConsoleKit::TenantConfigurator).to receive(:configure_tenant).and_call_original
          described_class.setup
          expect(described_class.current_tenant).to eq('only_one')
        end

        it 'auto-selects the only tenant in non-interactive mode' do
          allow($stdin).to receive(:tty?).and_return(false)
          expect(ConsoleKit::TenantConfigurator).to receive(:configure_tenant).and_call_original
          described_class.setup
          expect(described_class.current_tenant).to eq('only_one')
        end
      end

      context 'with multiple tenants in non-interactive mode' do
        before { allow($stdin).to receive(:tty?).and_return(false) }

        it 'auto-selects the first tenant' do
          expect(ConsoleKit::TenantConfigurator).to receive(:configure_tenant).and_call_original
          described_class.setup
          expect(described_class.current_tenant).to eq('acme')
        end
      end
    end

    context 'edge cases' do
      it 'handles nil context_class gracefully' do
        ConsoleKit.configure { |c| c.context_class = nil }
        stub_successful_setup('acme')
        described_class.setup
        expect(described_class.current_tenant).to eq('acme')
      end

      it 'supports symbol keys in tenant config' do
        ConsoleKit.configure do |c|
          c.tenants = { acme: { constants: { shard: 'shard_acme', mongo_db: 'acme_db', partner_code: 'ACME' } } }
        end

        allow(ConsoleKit::TenantSelector).to receive(:select).and_return(:acme)
        allow(ConsoleKit::TenantConfigurator).to receive(:configure_tenant).with(:acme, anything,
                                                                                 anything).and_return(true)

        described_class.setup
        expect(described_class.current_tenant).to eq(:acme)
      end
    end
  end

  describe '.reset_current_tenant' do
    context 'when no tenants are configured' do
      it 'prints a warning and returns false' do
        ConsoleKit.configure { |c| c.tenants = nil }
        expect(ConsoleKit::Output).to receive(:print_warning).with(/Cannot reset tenant/)
        expect(described_class.reset_current_tenant).to be false
      end
    end

    context 'when a tenant is already set' do
      before { ConsoleKit::Setup.instance_variable_set(:@current_tenant, 'acme') }

      it 'clears and reconfigures a new tenant' do
        allow($stdin).to receive(:tty?).and_return(true)
        allow(ConsoleKit::TenantSelector).to receive(:select).and_return('globex')
        allow(ConsoleKit::TenantConfigurator).to receive(:clear)
        allow(ConsoleKit::TenantConfigurator).to receive(:configure_tenant).with('globex', anything,
                                                                                 anything).and_return(true)
        expect(ConsoleKit::Output).to receive(:print_warning).with(/Resetting tenant: acme/)
        ConsoleKit::Setup.reset_current_tenant
        expect(ConsoleKit::Setup.current_tenant).to eq('globex')
      end
    end

    context 'when setup fails during reset' do
      before { ConsoleKit::Setup.instance_variable_set(:@current_tenant, 'acme') }

      it 'returns false if tenant selection returns nil' do
        allow(ConsoleKit::TenantConfigurator).to receive(:clear)
        allow(ConsoleKit::TenantSelector).to receive(:select).and_return(nil)
        allow(ConsoleKit::TenantConfigurator).to receive(:configure_tenant).and_return(false)
        allow(ConsoleKit::Output).to receive(:print_error)
        expect(described_class.reset_current_tenant).to be false
      end
    end
  end
end
