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

    it 'calls setup without raising errors' do
      expect { ConsoleKit::Setup.setup }.not_to raise_error
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
      expect(described_class.pretty_output).to be(true)
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
      expect(described_class.pretty_output).to be(false)
    end

    it 'defaults tenants to nil or empty' do
      expect(described_class.tenants).to be_nil.or be_empty
    end
  end

  describe 'thread safety' do
    before { described_class.tenants = ['main'] }

    it 'allows a thread to set its own tenants value' do
      thread = Thread.new do
        described_class.tenants = ['thread']
        expect(described_class.tenants).to eq(['thread'])
      end
      thread.join
    end

    it 'does not affect the main thread tenants value' do
      expect(described_class.tenants).to eq(['main'])
    end
  end

  describe 'delegated tenant methods' do
    describe '.current_tenant' do
      before { allow(ConsoleKit::Setup).to receive(:current_tenant).and_return('tenant1') }

      it 'calls ConsoleKit::Setup.current_tenant' do
        described_class.current_tenant
        expect(ConsoleKit::Setup).to have_received(:current_tenant)
      end

      it 'returns the tenant from ConsoleKit::Setup.current_tenant' do
        expect(described_class.current_tenant).to eq('tenant1')
      end

      it 'returns nil when ConsoleKit::Setup.current_tenant returns nil' do
        allow(ConsoleKit::Setup).to receive(:current_tenant).and_return(nil)
        expect(described_class.current_tenant).to be_nil
      end

      it 'returns the tenant on any calls' do
        described_class.current_tenant # call once to simulate first call
        expect(described_class.current_tenant).to eq('tenant1')
      end
    end

    describe '.reset_current_tenant' do
      before { allow(ConsoleKit::Setup).to receive(:reset_current_tenant).and_return(true) }

      it 'calls ConsoleKit::Setup.reset_current_tenant' do
        described_class.reset_current_tenant
        expect(ConsoleKit::Setup).to have_received(:reset_current_tenant)
      end

      it 'returns true when ConsoleKit::Setup.reset_current_tenant returns true' do
        expect(described_class.reset_current_tenant).to be(true)
      end

      it 'returns false when ConsoleKit::Setup.reset_current_tenant returns false' do
        allow(ConsoleKit::Setup).to receive(:reset_current_tenant).and_return(false)
        expect(described_class.reset_current_tenant).to be(false)
      end

      it 'returns true on any calls' do
        described_class.reset_current_tenant
        expect(described_class.reset_current_tenant).to be(true)
      end
    end
  end

  describe 'pretty_output toggle methods' do
    before do
      described_class.configure { |c| c.pretty_output = false }
    end

    it 'starts with pretty_output default as false' do
      expect(described_class.pretty_output).to be(false)
    end

    it 'enables pretty_output when it is false' do
      described_class.enable_pretty_output
      expect(described_class.pretty_output).to be true
    end

    it 'keeps pretty_output enabled when already true' do
      described_class.configure { |c| c.pretty_output = true }
      described_class.enable_pretty_output
      expect(described_class.pretty_output).to be true
    end

    it 'disables pretty_output when it is true' do
      described_class.configure { |c| c.pretty_output = true }
      described_class.disable_pretty_output
      expect(described_class.pretty_output).to be false
    end

    it 'keeps pretty_output disabled when already false' do
      described_class.disable_pretty_output
      expect(described_class.pretty_output).to be false
    end

    context 'when toggling pretty_output' do
      it 'toggles from false to true' do
        described_class.configure { |c| c.pretty_output = false }
        described_class.enable_pretty_output
        expect(described_class.pretty_output).to be true
      end

      it 'toggles from true to false' do
        described_class.configure { |c| c.pretty_output = true }
        described_class.disable_pretty_output
        expect(described_class.pretty_output).to be false
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
        expect(described_class.tenants).to eq(%w[tenant1 tenant2])
      end

      it 'preserves context_class when enabling pretty_output' do
        described_class.enable_pretty_output
        expect(described_class.context_class).to eq(dummy_class)
      end

      it 'preserves tenants when disabling pretty_output' do
        described_class.configure { |c| c.pretty_output = true }
        described_class.disable_pretty_output
        expect(described_class.tenants).to eq(%w[tenant1 tenant2])
      end

      it 'preserves context_class when disabling pretty_output' do
        described_class.configure { |c| c.pretty_output = true }
        described_class.disable_pretty_output
        expect(described_class.context_class).to eq(dummy_class)
      end
    end
  end
end
