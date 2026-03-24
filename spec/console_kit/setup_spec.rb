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
        %i[tenant_shard tenant_mongo_db tenant_redis_db tenant_elasticsearch_prefix partner_identifier].each do |attr|
          define_method(attr) { instance_variable_get("@#{attr}") }
          define_method("#{attr}=") { |val| instance_variable_set("@#{attr}", val) }
        end
      end
    end
  end

  def stub_successful_setup(tenant)
    allow(ConsoleKit::TenantSelector).to receive(:select).and_return(tenant)

    allow(ConsoleKit::TenantConfigurator).tap do |configurator|
      configurator.to receive(:configure_tenant).with(tenant)
      configurator.to receive(:configuration_success).and_return(true)
    end
  end

  shared_examples 'a successful tenant setup' do |tenant|
    it "sets current_tenant to #{tenant}" do
      stub_successful_setup(tenant)
      described_class.setup
      expect(described_class.current_tenant).to eq(tenant)
    end
  end

  before do
    ConsoleKit.configure do |config|
      config.tenants = tenants
      config.context_class = context_class
    end
    described_class.current_tenant = nil
    allow(ConsoleKit::Output).to receive(:print_success)
  end

  describe '.tenant_setup_successful?' do
    it 'returns true if current_tenant is set' do
      described_class.current_tenant = 'acme'
      expect(described_class.tenant_setup_successful?).to be true
    end

    it 'returns false if current_tenant is nil' do
      described_class.current_tenant = nil
      expect(described_class.tenant_setup_successful?).to be false
    end
  end

  describe '.setup' do
    it_behaves_like 'a successful tenant setup', 'acme'

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
        allow(ConsoleKit::TenantConfigurator).to receive(:configure_tenant)
        allow(ConsoleKit::TenantConfigurator).to receive(:configuration_success).and_return(false)
        described_class.setup
        expect(described_class.current_tenant).to be_nil
      end
    end

    context 'when no tenants are configured' do
      it 'prints an error when tenants are nil' do
        ConsoleKit.configure { |c| c.tenants = nil }
        allow(ConsoleKit::Output).to receive(:print_error)
        described_class.setup
        expect(ConsoleKit::Output).to have_received(:print_error).with(/tenants.*not configured/)
      end

      it 'prints an error when tenants are empty' do
        ConsoleKit.configure { |c| c.tenants = {} }
        allow(ConsoleKit::Output).to receive(:print_error)
        described_class.setup
        expect(ConsoleKit::Output).to have_received(:print_error).with(/tenants.*not configured/)
      end
    end

    context 'when tenant selection is none or aborted' do
      before do
        allow($stdin).to receive(:tty?).and_return(true)
        allow(ConsoleKit::Output).to receive(:print_info)
        allow(Kernel).to receive(:exit)
      end

      it 'calls Kernel.exit if tenant selection returns :exit' do
        allow(ConsoleKit::TenantSelector).to receive(:select).and_return(:exit)
        described_class.setup
        expect(Kernel).to have_received(:exit)
      end

      it 'prints info if tenant selection returns :none' do
        allow(ConsoleKit::TenantSelector).to receive(:select).and_return(:none)
        described_class.setup
        expect(ConsoleKit::Output).to have_received(:print_info).with(/No tenant selected/)
      end

      it 'calls Kernel.exit if tenant selection returns :abort' do
        allow(ConsoleKit::TenantSelector).to receive(:select).and_return(:abort)
        described_class.setup
        expect(Kernel).to have_received(:exit)
      end
    end

    context 'when tenant selection fails' do
      before do
        allow($stdin).to receive(:tty?).and_return(true)
        allow(ConsoleKit::Output).to receive(:print_error)
      end

      it 'prints error if tenant selection returns nil' do
        allow(ConsoleKit::TenantSelector).to receive(:select).and_return(nil)
        described_class.setup
        expect(ConsoleKit::Output).to have_received(:print_error).with(/Tenant selection failed/)
      end

      it 'prints error if tenant selection returns empty string' do
        allow(ConsoleKit::TenantSelector).to receive(:select).and_return('')
        described_class.setup
        expect(ConsoleKit::Output).to have_received(:print_error).with(/Tenant selection failed/)
      end
    end

    context 'when configure_tenant raises StandardError' do
      before do
        allow(ConsoleKit::Output).to receive(:print_error)
        allow(ConsoleKit::Output).to receive(:print_backtrace)
        allow(ConsoleKit::TenantSelector).to receive(:select).and_return('acme')
        allow(ConsoleKit::TenantConfigurator).to receive(:configure_tenant).and_raise(StandardError, 'Boom')
        described_class.setup
      end

      it 'prints the error message' do
        expect(ConsoleKit::Output).to have_received(:print_error).with(/Boom/)
      end

      it 'prints the backtrace' do
        expect(ConsoleKit::Output).to have_received(:print_backtrace)
      end
    end

    context 'when configure_tenant raises RuntimeError' do
      before do
        allow(ConsoleKit::Output).to receive(:print_error)
        allow(ConsoleKit::Output).to receive(:print_backtrace)
        allow(ConsoleKit::TenantSelector).to receive(:select).and_return('acme')
        allow(ConsoleKit::TenantConfigurator).to receive(:configure_tenant).and_raise(RuntimeError, 'Unexpected error')
        described_class.setup
      end

      it 'prints the error message' do
        expect(ConsoleKit::Output).to have_received(:print_error).with(/Unexpected error/)
      end

      it 'prints the backtrace' do
        expect(ConsoleKit::Output).to have_received(:print_backtrace)
      end
    end

    context 'when auto-selecting tenants with a single tenant' do
      before { ConsoleKit.configure { |c| c.tenants = { 'only_one' => tenants['acme'] } } }

      it 'auto-selects the only tenant in interactive mode' do
        allow($stdin).to receive(:tty?).and_return(true)
        allow(ConsoleKit::TenantConfigurator).to receive(:configure_tenant).with('only_one')
        allow(ConsoleKit::TenantConfigurator).to receive(:configuration_success).and_return(true)
        described_class.setup
        expect(described_class.current_tenant).to eq('only_one')
      end

      it 'auto-selects the only tenant in non-interactive mode' do
        allow($stdin).to receive(:tty?).and_return(false)
        allow(ConsoleKit::TenantConfigurator).to receive(:configure_tenant).with('only_one')
        allow(ConsoleKit::TenantConfigurator).to receive(:configuration_success).and_return(true)
        described_class.setup
        expect(described_class.current_tenant).to eq('only_one')
      end
    end

    context 'when auto-selecting tenants with multiple tenants in non-interactive mode' do
      before do
        allow($stdin).to receive(:tty?).and_return(false)
        allow(ConsoleKit::TenantConfigurator).tap do |configurator|
          configurator.to receive(:configure_tenant).with('acme')
          configurator.to receive(:configuration_success).and_return(true)
        end
      end

      it 'auto-selects the first tenant' do
        described_class.setup
        expect(described_class.current_tenant).to eq('acme')
      end
    end

    describe 'auto_select? helper' do
      it 'returns true if there is only one tenant' do
        ConsoleKit.configure { |c| c.tenants = { 'one' => {} } }
        expect(described_class.send(:auto_select?)).to be true
      end

      it 'returns true if not a TTY' do
        ConsoleKit.configure { |c| c.tenants = { 'one' => {}, 'two' => {} } }
        allow($stdin).to receive(:tty?).and_return(false)
        expect(described_class.send(:auto_select?)).to be true
      end

      it 'returns false if multiple tenants and a TTY' do
        ConsoleKit.configure { |c| c.tenants = { 'one' => {}, 'two' => {} } }
        allow($stdin).to receive(:tty?).and_return(true)
        expect(described_class.send(:auto_select?)).to be false
      end
    end

    describe 'tenant_partner helper' do
      it 'returns the partner code if present' do
        ConsoleKit.configure { |c| c.tenants = { 'acme' => { constants: { partner_code: 'ACME' } } } }
        expect(ConsoleKit::TenantSelector.send(:tenant_partner, 'acme')).to eq('ACME')
      end

      it 'returns N/A if partner code is missing' do
        ConsoleKit.configure { |c| c.tenants = { 'acme' => { constants: {} } } }
        expect(ConsoleKit::TenantSelector.send(:tenant_partner, 'acme')).to eq('N/A')
      end
    end

    context 'when handling edge cases with symbol keys in tenant config' do
      before do
        ConsoleKit.configure do |c|
          c.tenants = { acme: { constants: { shard: 'shard_acme', mongo_db: 'acme_db', partner_code: 'ACME' } } }
        end
        allow(ConsoleKit::TenantSelector).to receive(:select).and_return(:acme)
        allow(ConsoleKit::TenantConfigurator).to receive(:configure_tenant).with(:acme)
        allow(ConsoleKit::TenantConfigurator).to receive(:configuration_success).and_return(true)
      end

      it 'sets up tenant with symbol keys' do
        described_class.setup
        expect(described_class.current_tenant).to eq(:acme)
      end
    end
  end

  describe '.print_tenant_banner' do
    before do
      allow(ConsoleKit::Output).to receive(:print_error)
      allow(ConsoleKit::Output).to receive(:print_warning)
      allow(ConsoleKit::Output).to receive(:print_info)
      allow(ConsoleKit::Connections::Dashboard).to receive(:display)
    end

    context 'when environment is production' do
      before do
        ConsoleKit.configure do |config|
          config.tenants = {
            'acme' => { constants: { shard: 'shard_acme', partner_code: 'ACME', environment: 'production' } }
          }
          config.context_class = context_class
        end
      end

      it 'prints a production warning' do
        described_class.send(:print_tenant_banner, 'acme')
        expect(ConsoleKit::Output).to have_received(:print_error).with(/PRODUCTION/)
      end
    end

    context 'when environment is staging' do
      before do
        ConsoleKit.configure do |config|
          config.tenants = {
            'acme' => { constants: { shard: 'shard_acme', partner_code: 'ACME', environment: 'staging' } }
          }
          config.context_class = context_class
        end
      end

      it 'prints a staging warning' do
        described_class.send(:print_tenant_banner, 'acme')
        expect(ConsoleKit::Output).to have_received(:print_warning).with(/staging/)
      end
    end

    context 'when environment is not set' do
      before do
        ConsoleKit.configure do |config|
          config.tenants = { 'acme' => { constants: { shard: 'shard_acme', partner_code: 'ACME' } } }
          config.context_class = context_class
        end
      end

      it 'does not print a production error' do
        described_class.send(:print_tenant_banner, 'acme')
        expect(ConsoleKit::Output).not_to have_received(:print_error)
      end

      it 'does not print a staging warning' do
        described_class.send(:print_tenant_banner, 'acme')
        expect(ConsoleKit::Output).not_to have_received(:print_warning)
      end
    end
  end

  describe '.reapply' do
    context 'when a tenant is already setup' do
      before do
        described_class.current_tenant = 'acme'
        allow(ConsoleKit::TenantConfigurator).to receive(:configure_tenant).with('acme')
      end

      it 're-calls configuration for the current tenant' do
        described_class.reapply
        expect(ConsoleKit::TenantConfigurator).to have_received(:configure_tenant).with('acme')
      end

      it 'silences the output during re-application' do
        allow(ConsoleKit::Output).to receive(:silence).and_call_original
        described_class.reapply
        expect(ConsoleKit::Output).to have_received(:silence)
      end
    end

    context 'when no tenant is setup' do
      before do
        described_class.current_tenant = nil
        allow(ConsoleKit::TenantConfigurator).to receive(:configure_tenant)
      end

      it 'does not call configuration' do
        described_class.reapply
        expect(ConsoleKit::TenantConfigurator).not_to have_received(:configure_tenant)
      end
    end
  end

  describe '.reset_current_tenant' do
    context 'when no tenants are configured' do
      before do
        allow($stdin).to receive(:tty?).and_return(true)
        ConsoleKit.configure { |c| c.tenants = nil }
        allow(ConsoleKit::Output).to receive(:print_warning)
      end

      it 'prints a warning' do
        described_class.reset_current_tenant
        expect(ConsoleKit::Output).to have_received(:print_warning).with(/Cannot reset tenant/)
      end

      it 'returns nil' do
        expect(described_class.reset_current_tenant).to be_nil
      end
    end

    context 'when a tenant is already set' do
      before do
        described_class.current_tenant = 'acme'
        allow($stdin).to receive(:tty?).and_return(true)
        allow(ConsoleKit::TenantSelector).to receive(:select).and_return('globex')
        allow(ConsoleKit::TenantConfigurator).to receive(:clear)
        allow(ConsoleKit::TenantConfigurator).to receive(:configure_tenant).with('globex')
        allow(ConsoleKit::TenantConfigurator).to receive(:configuration_success).and_return(true)
        allow(ConsoleKit::Output).to receive(:print_warning)
      end

      it 'prints a reset warning' do
        described_class.reset_current_tenant
        expect(ConsoleKit::Output).to have_received(:print_warning).with(/Resetting tenant: acme/)
      end

      it 'sets current_tenant to the new tenant' do
        described_class.reset_current_tenant
        expect(described_class.current_tenant).to eq('globex')
      end

      # rubocop:disable RSpec/MultipleExpectations, RSpec/MessageSpies
      it 'clears the old tenant configuration before setting the new one' do
        expect(ConsoleKit::TenantConfigurator).to receive(:clear).ordered
        expect(ConsoleKit::TenantConfigurator).to receive(:configure_tenant).with('globex').ordered
        described_class.reset_current_tenant
      end
      # rubocop:enable RSpec/MultipleExpectations, RSpec/MessageSpies
    end

    context 'when user presses Ctrl+C during switch_tenant' do
      before do
        described_class.current_tenant = 'acme'
        allow($stdin).to receive(:tty?).and_return(true)
        allow(ConsoleKit::TenantSelector).to receive(:select).and_return(:abort)
        allow(ConsoleKit::Output).to receive(:print_warning)
      end

      it 'keeps the current tenant' do
        described_class.reset_current_tenant
        expect(described_class.current_tenant).to eq('acme')
      end

      it 'prints a cancellation warning' do
        described_class.reset_current_tenant
        expect(ConsoleKit::Output).to have_received(:print_warning).with(/Tenant switch cancelled/)
      end

      it 'does not clear tenant configuration' do
        allow(ConsoleKit::TenantConfigurator).to receive(:clear)
        described_class.reset_current_tenant
        expect(ConsoleKit::TenantConfigurator).not_to have_received(:clear)
      end
    end

    context 'when setup fails or none selected during reset' do
      before do
        described_class.current_tenant = 'acme'
        allow($stdin).to receive(:tty?).and_return(true)
        allow(ConsoleKit::TenantConfigurator).to receive(:clear)
        allow(ConsoleKit::TenantSelector).to receive(:select).and_return(:none)
        allow(ConsoleKit::TenantConfigurator).to receive(:configure_tenant)
        allow(ConsoleKit::Output).to receive(:print_info)
      end

      it 'clears current_tenant when selection returns :none' do
        described_class.reset_current_tenant
        expect(described_class.current_tenant).to be_nil
      end

      it 'returns nil if tenant selection returns :none' do
        result = described_class.reset_current_tenant
        expect(result).to be_nil
      end
    end
  end

  describe 'reloading and re-application' do
    let(:config) { ConsoleKit.configuration }

    describe 'context_class resolution' do
      it 'resolves a string to a constant' do
        stub_const('MyTestContext', Class.new)
        config.context_class = 'MyTestContext'
        expect(config.context_class).to eq(MyTestContext)
      end

      it 'resolves a symbol to a constant' do
        stub_const('MyTestContext', Class.new)
        config.context_class = :MyTestContext
        expect(config.context_class).to eq(MyTestContext)
      end

      it 'returns the class object if already a class' do
        klass = Class.new
        config.context_class = klass
        expect(config.context_class).to eq(klass)
      end

      it 'raises ConsoleKit::Error if the string context_class does not exist' do
        config.context_class = 'NonExistentContextClass'
        expect { config.context_class }.to raise_error(ConsoleKit::Error, /could not be found/)
      end
    end

    describe '.reapply silence' do
      before do
        described_class.current_tenant = 'acme'
        allow(ConsoleKit::TenantConfigurator).to receive(:configure_tenant).and_raise('Boom')
        allow(ConsoleKit::Output).to receive(:silence).and_call_original
        begin
          described_class.reapply
        rescue StandardError
          nil
        end
      end

      it 'activates silence during reconfiguration' do
        expect(ConsoleKit::Output).to have_received(:silence)
      end

      it 'ensures output is not silent after failure' do
        expect(ConsoleKit::Output.silent).to be_falsey
      end
    end
  end
end
