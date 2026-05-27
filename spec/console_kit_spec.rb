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
    it 'responds to setup' do
      expect(ConsoleKit::Setup).to respond_to(:setup)
    end

    it 'returns a SwitchPipeline::Result' do
      allow(ConsoleKit::SwitchPipeline).to receive(:run)
        .and_return(ConsoleKit::SwitchPipeline::Result.new(success: false, error: 'no tenants'))
      result = ConsoleKit::Setup.setup
      expect(result).to be_a(ConsoleKit::SwitchPipeline::Result)
    end
  end

  describe 'error class' do
    it 'defines a custom base error class' do
      expect(ConsoleKit::Error).to be < StandardError
    end

    it 'can raise and rescue ConsoleKit::Error' do
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

  describe 'configuration accessors' do
    before do
      described_class.configure do |config|
        config.tenants = nil
        config.context_class = nil
        config.pretty_output = false
      end
    end

    it 'allows setting and getting tenants' do
      described_class.tenants = %w[tenant_1 tenant_2]
      expect(described_class.tenants).to eq(%w[tenant_1 tenant_2])
    end

    it 'allows setting and getting context_class' do
      dummy_class = Class.new
      described_class.context_class = dummy_class
      expect(described_class.context_class).to eq(dummy_class)
    end

    it 'allows setting and getting pretty_output' do
      described_class.configure { |config| config.pretty_output = true }
      expect(described_class.pretty_output).to be true
    end
  end

  describe 'default configuration values' do
    before do
      described_class.configure do |config|
        config.tenants = nil
        config.context_class = nil
        config.pretty_output = false
      end
    end

    it 'defaults to pretty_output = false' do
      expect(described_class.pretty_output).to be false
    end

    it 'defaults tenants to nil or empty' do
      expect(described_class.tenants).to be_nil.or be_empty
    end
  end

  describe 'configuration sharing' do
    after { described_class.reset_configuration! }

    it 'shares configuration across threads (module-level config)' do
      described_class.tenants = ['main']
      thread = Thread.new { expect(described_class.tenants).to eq(['main']) }
      thread.join
    end

    it 'retains the configured tenants after thread completes' do
      described_class.tenants = ['main']
      Thread.new { nil }.join
      expect(described_class.tenants).to eq(['main'])
    end
  end

  describe '.current_tenant' do
    after { ConsoleKit::Context.reset! }

    it 'reads from Context' do
      ConsoleKit::Context.push(:my_tenant)
      expect(described_class.current_tenant).to eq(:my_tenant)
    end

    it 'returns nil if no tenant is set' do
      ConsoleKit::Context.reset!
      expect(described_class.current_tenant).to be_nil
    end

    it 'reflects the latest pushed tenant' do
      ConsoleKit::Context.push(:tenant1)
      expect(described_class.current_tenant).to eq(:tenant1)
    end
  end

  describe '.reset_current_tenant' do
    it 'delegates to ConsoleKit::Setup.reset_current_tenant' do
      allow(ConsoleKit::Setup).to receive(:reset_current_tenant).and_return(true)
      described_class.reset_current_tenant
      expect(ConsoleKit::Setup).to have_received(:reset_current_tenant)
    end

    it 'returns the value from ConsoleKit::Setup.reset_current_tenant' do
      allow(ConsoleKit::Setup).to receive(:reset_current_tenant).and_return(false)
      expect(described_class.reset_current_tenant).to be false
    end

    it 'returns true when Setup succeeds' do
      allow(ConsoleKit::Setup).to receive(:reset_current_tenant).and_return(true)
      expect(described_class.reset_current_tenant).to be true
    end
  end

  describe '.enable_pretty_output' do
    before { described_class.configure { |c| c.pretty_output = false } }

    it 'enables pretty_output' do
      described_class.enable_pretty_output
      expect(described_class.pretty_output).to be true
    end

    it 'keeps pretty_output true if already enabled' do
      described_class.configure { |c| c.pretty_output = true }
      described_class.enable_pretty_output
      expect(described_class.pretty_output).to be true
    end
  end

  describe '.disable_pretty_output' do
    before { described_class.configure { |c| c.pretty_output = true } }

    it 'disables pretty_output' do
      described_class.disable_pretty_output
      expect(described_class.pretty_output).to be false
    end

    it 'keeps pretty_output false if already disabled' do
      described_class.configure { |c| c.pretty_output = false }
      described_class.disable_pretty_output
      expect(described_class.pretty_output).to be false
    end

    it 'does not affect tenants' do
      described_class.configure { |c| c.tenants = %w[tenant1 tenant2] }
      described_class.disable_pretty_output
      expect(described_class.tenants).to eq(%w[tenant1 tenant2])
    end

    it 'does not affect context_class' do
      described_class.configure { |c| c.context_class = Class.new }
      described_class.disable_pretty_output
      expect(described_class.context_class).not_to be_nil
    end
  end

  describe 'pretty_output toggling' do
    it 'goes from false to true after enable' do
      described_class.configure { |c| c.pretty_output = false }
      described_class.enable_pretty_output
      expect(described_class.pretty_output).to be true
    end

    it 'goes from true to false after disable' do
      described_class.configure { |c| c.pretty_output = true }
      described_class.disable_pretty_output
      expect(described_class.pretty_output).to be false
    end
  end

  describe '.with' do
    before do
      described_class.configure do |c|
        c.tenants = { tenant_a: { constants: { shard: 's', partner_code: 'p' } } }
        c.context_class = 'Object'
      end
      allow(ConsoleKit::SwitchPipeline).to receive(:run)
        .and_return(ConsoleKit::SwitchPipeline::Result.new(success: true, tenant: :tenant_a))
    end

    after { ConsoleKit::Context.reset! }

    it 'yields block' do
      result = nil
      described_class.with(:tenant_a) { result = :done }
      expect(result).to eq(:done)
    end

    it 'restores tenant after block' do
      ConsoleKit::Context.push(:tenant_b)
      described_class.with(:tenant_a) { nil }
      expect(ConsoleKit::Context.current.tenant).to eq(:tenant_b)
    end
  end

  describe '.status' do
    it 'returns a Status instance' do
      expect(described_class.status).to be_a(ConsoleKit::Status)
    end
  end

  describe '.current_tenant (shim)' do
    after { ConsoleKit::Context.reset! }

    it 'reads from Context' do
      ConsoleKit::Context.push(:tenant_a)
      expect(described_class.current_tenant).to eq(:tenant_a)
    end
  end

  describe '.show_dashboard=' do
    it 'sets show_dashboard on configuration' do
      described_class.show_dashboard = true
      expect(described_class.show_dashboard).to be true
    end
  end

  describe '.pretty_output=' do
    it 'sets pretty_output on configuration' do
      described_class.pretty_output = false
      expect(described_class.pretty_output).to be false
    end
  end

  describe '.switch_tenant!' do
    before do
      described_class.configure do |c|
        c.tenants = { tenant_a: { constants: { shard: 's', partner_code: 'p' } } }
        c.context_class = 'Object'
      end
    end

    after { ConsoleKit::Context.reset! }

    it 'runs SwitchPipeline and returns a result' do
      allow(ConsoleKit::SwitchPipeline).to receive(:run)
        .and_return(ConsoleKit::SwitchPipeline::Result.new(success: true, tenant: :tenant_a))
      result = described_class.switch_tenant!
      expect(result).to be_a(ConsoleKit::SwitchPipeline::Result)
    end
  end
end
