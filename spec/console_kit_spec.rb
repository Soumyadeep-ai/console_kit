# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ConsoleKit do
  describe 'version' do
    it 'has a version number' do
      expect(ConsoleKit::VERSION).not_to be_nil
    end

    it 'has a semantic version string' do
      expect(ConsoleKit::VERSION).to match(/\A\d+\.\d+\.\d+\z/)
    end
  end

  describe 'setup' do
    it 'responds to run' do
      expect(ConsoleKit::TenantOrchestrator).to respond_to(:run)
    end

    it 'calls run without raising errors' do
      expect { ConsoleKit::TenantOrchestrator.run }.not_to raise_error
    end
  end

  describe 'error class' do
    it 'defines a custom base error class' do
      expect(ConsoleKit::Error).to be < StandardError
    end

    it 'can raise ConsoleKit::Error' do
      expect do
        raise ConsoleKit::Error, 'Something went wrong'
      end.to raise_error(ConsoleKit::Error, 'Something went wrong')
    end
  end

  describe '.configure' do
    it 'yields the configuration instance to the block' do
      yielded = nil
      described_class.configure { |config| yielded = config }
      expect(yielded).to be_a(ConsoleKit::Configuration)
    end

    it 'memoizes the configuration object' do
      config1 = described_class.configuration
      config2 = described_class.configuration
      expect(config1).to equal(config2)
    end
  end

  describe 'thread safety' do
    it 'shares configuration across threads' do
      described_class.configuration.tenants = { 'main' => {} }
      Thread.new { described_class.configuration.tenants = { 'thread' => {} } }.join
      expect(described_class.configuration.tenants).to eq({ 'thread' => {} })
    end

    it 'isolates current_tenant across threads' do
      ConsoleKit::TenantOrchestrator.current_tenant = 'main'
      Thread.new { ConsoleKit::TenantOrchestrator.current_tenant = 'thread' }.join
      expect(ConsoleKit::TenantOrchestrator.current_tenant).to eq('main')
    end
  end

  describe 'delegated tenant methods' do
    describe '.current_tenant' do
      before { ConsoleKit::StateStore.current = ConsoleKit::TenantState.new(tenant_key: 'tenant1') }

      it 'returns the tenant key held in StateStore' do
        expect(described_class.current_tenant).to eq('tenant1')
      end

      it 'returns nil when StateStore holds no tenant' do
        ConsoleKit::StateStore.clear!
        expect(described_class.current_tenant).to be_nil
      end

      it 'returns the tenant on any calls' do
        described_class.current_tenant
        expect(described_class.current_tenant).to eq('tenant1')
      end
    end

    describe '.reset_current_tenant' do
      before { allow(ConsoleKit::TenantOrchestrator).to receive(:reset).and_return(true) }

      it 'calls ConsoleKit::TenantOrchestrator.reset' do
        described_class.reset_current_tenant
        expect(ConsoleKit::TenantOrchestrator).to have_received(:reset)
      end

      it 'returns true when ConsoleKit::TenantOrchestrator.reset returns true' do
        expect(described_class.reset_current_tenant).to be(true)
      end

      it 'returns false when ConsoleKit::TenantOrchestrator.reset returns false' do
        allow(ConsoleKit::TenantOrchestrator).to receive(:reset).and_return(false)
        expect(described_class.reset_current_tenant).to be(false)
      end

      it 'returns true on any calls' do
        described_class.reset_current_tenant
        expect(described_class.reset_current_tenant).to be(true)
      end
    end
  end

  describe '.reset_configuration!' do
    before { ConsoleKit::StateStore.current = ConsoleKit::TenantState.new(tenant_key: 'acme', configured: true) }

    it 'clears configuration success by clearing the underlying tenant state' do
      described_class.reset_configuration!
      expect(ConsoleKit::TenantConfigurator.configuration_success).to be false
    end
  end

  describe 'pretty_output toggle methods' do
    before do
      described_class.configure { |c| c.pretty_output = false }
    end

    it 'starts with pretty_output default as false' do
      expect(described_class.configuration.pretty_output).to be(false)
    end

    it 'enables pretty_output when it is false' do
      described_class.enable_pretty_output
      expect(described_class.configuration.pretty_output).to be true
    end

    it 'keeps pretty_output enabled when already true' do
      described_class.configure { |c| c.pretty_output = true }
      described_class.enable_pretty_output
      expect(described_class.configuration.pretty_output).to be true
    end

    it 'disables pretty_output when it is true' do
      described_class.configure { |c| c.pretty_output = true }
      described_class.disable_pretty_output
      expect(described_class.configuration.pretty_output).to be false
    end

    it 'keeps pretty_output disabled when already false' do
      described_class.disable_pretty_output
      expect(described_class.configuration.pretty_output).to be false
    end

    context 'when toggling pretty_output' do
      it 'toggles from false to true' do
        described_class.configure { |c| c.pretty_output = false }
        described_class.enable_pretty_output
        expect(described_class.configuration.pretty_output).to be true
      end

      it 'toggles from true to false' do
        described_class.configure { |c| c.pretty_output = true }
        described_class.disable_pretty_output
        expect(described_class.configuration.pretty_output).to be false
      end
    end

    context 'when preserving configuration on toggle' do
      let(:dummy_class) { Class.new }

      before do
        described_class.configure do |c|
          c.tenants = %w[tenant1 tenant2]
          c.context_class = dummy_class
        end
      end

      it 'preserves tenants when enabling pretty_output' do
        described_class.enable_pretty_output
        expect(described_class.configuration.tenants).to eq(%w[tenant1 tenant2])
      end

      it 'preserves context_class when enabling pretty_output' do
        described_class.enable_pretty_output
        expect(described_class.configuration.context_class).to eq(dummy_class)
      end

      it 'preserves tenants when disabling pretty_output' do
        described_class.configure { |c| c.pretty_output = true }
        described_class.disable_pretty_output
        expect(described_class.configuration.tenants).to eq(%w[tenant1 tenant2])
      end

      it 'preserves context_class when disabling pretty_output' do
        described_class.configure { |c| c.pretty_output = true }
        described_class.disable_pretty_output
        expect(described_class.configuration.context_class).to eq(dummy_class)
      end
    end
  end
end
