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

  def stub_successful_setup(tenant)
    allow(ConsoleKit::TenantSelector).to receive(:select).and_return(tenant)
    allow(ConsoleKit::TenantConfigurator).to receive(:configure_tenant).with(tenant, anything,
                                                                             anything).and_return(true)
  end

  shared_examples 'a successful tenant setup' do |tenant|
    it "sets current_tenant to #{tenant}" do
      stub_successful_setup(tenant)
      described_class.setup
      expect(described_class.current_tenant).to eq(tenant)
    end
  end

  before do
    described_class.configure do |config|
      config.tenants = tenants
      config.context_class = context_class
    end
    described_class.instance_variable_set(:@current_tenant, nil)
    allow(ConsoleKit::Output).to receive(:print_success)
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
    include_examples 'a successful tenant setup', 'acme'

    context 'when setup succeeds' do
      it 'sets @current_tenant' do
        stub_successful_setup('globex')
        described_class.setup
        expect(described_class.current_tenant).to eq('globex')
      end
    end

    context 'when configuration fails' do
      it 'does not set @current_tenant' do
        allow(ConsoleKit::TenantSelector).to receive(:select).and_return('acme')
        allow(ConsoleKit::TenantConfigurator).to receive(:configure_tenant).and_return(false)
        described_class.setup
        expect(described_class.current_tenant).to be_nil
      end
    end

    context 'when no tenants are configured' do
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
    end

    context 'when tenant selection fails' do
      before { allow($stdin).to receive(:tty?).and_return(true) }

      it 'prints error if tenant selection returns nil' do
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

    context 'when configuration raises an exception' do
      it 'handles StandardError and prints backtrace' do
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

    context 'auto-selection behavior' do
      context 'with single tenant' do
        before { described_class.tenants = { 'only_one' => tenants['acme'] } }

        it 'auto-picks the only tenant in interactive mode' do
          allow($stdin).to receive(:tty?).and_return(true)
          expect(ConsoleKit::TenantConfigurator).to receive(:configure_tenant).and_call_original
          described_class.setup
          expect(described_class.current_tenant).to eq('only_one')
        end

        it 'auto-picks the only tenant in non-interactive mode' do
          allow($stdin).to receive(:tty?).and_return(false)
          expect(ConsoleKit::TenantConfigurator).to receive(:configure_tenant).and_call_original
          described_class.setup
          expect(described_class.current_tenant).to eq('only_one')
        end
      end

      context 'with multiple tenants and non-interactive mode' do
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
        described_class.context_class = nil
        stub_successful_setup('acme')
        described_class.setup
        expect(described_class.current_tenant).to eq('acme')
      end

      it 'supports symbol keys in tenant config' do
        described_class.tenants = { acme: { constants: { shard: 'shard_acme', mongo_db: 'acme_db',
                                                         partner_code: 'ACME' } } }
        allow(ConsoleKit::TenantSelector).to receive(:select).and_return(:acme)
        allow(ConsoleKit::TenantConfigurator).to receive(:configure_tenant).with(:acme, anything,
                                                                                 anything).and_return(true)

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
      before { described_class.instance_variable_set(:@current_tenant, 'acme') }

      it 'clears configuration and resets tenant' do
        allow(ConsoleKit::TenantConfigurator).to receive(:clear)
        stub_successful_setup('globex')
        expect(ConsoleKit::Output).to receive(:print_warning).with(/Resetting tenant: acme/)
        described_class.reset_current_tenant
        expect(described_class.current_tenant).to eq('globex')
      end
    end

    context 'when setup fails after reset' do
      before { described_class.instance_variable_set(:@current_tenant, 'acme') }

      it 'returns false if no tenant is selected' do
        allow(ConsoleKit::TenantConfigurator).to receive(:clear)
        allow(ConsoleKit::TenantSelector).to receive(:select).and_return(nil)
        allow(ConsoleKit::Output).to receive(:print_error)
        expect(described_class.reset_current_tenant).to be false
      end
    end
  end
end
