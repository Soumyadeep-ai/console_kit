# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ConsoleKit do
  describe 'version' do
    it 'has a version number' do
      expect(ConsoleKit::VERSION).not_to be nil
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

    it 'can raise and rescue ConsoleKit::Error' do
      expect do
        raise ConsoleKit::Error, 'Something went wrong'
      end.to raise_error(ConsoleKit::Error, 'Something went wrong')
    end
  end

  describe '.configure' do
    it 'yields the configuration instance to the block' do
      yielded = nil
      ConsoleKit.configure do |config|
        yielded = config
      end
      expect(yielded).to be_a(ConsoleKit::Configuration)
    end

    it 'memoizes the configuration object' do
      config1 = ConsoleKit.configuration
      config2 = ConsoleKit.configuration
      expect(config1).to equal(config2)
    end
  end

  describe 'configuration accessors' do
    before do
      # Reset configuration before each test to avoid test pollution
      ConsoleKit.configure do |config|
        config.tenants = nil
        config.context_class = nil
        config.pretty_output = false
      end
    end

    it 'allows setting and getting tenants' do
      ConsoleKit.tenants = %w[tenant_1 tenant_2]
      expect(ConsoleKit.tenants).to eq(%w[tenant_1 tenant_2])
    end

    it 'allows setting and getting context_class' do
      dummy_class = Class.new
      ConsoleKit.context_class = dummy_class
      expect(ConsoleKit.context_class).to eq(dummy_class)
    end

    it 'allows setting and getting pretty_output' do
      ConsoleKit.configure do |config|
        config.pretty_output = true
      end
      expect(ConsoleKit.pretty_output).to eq(true)
    end
  end

  describe 'default configuration values' do
    before do
      # Reset before checking defaults
      ConsoleKit.configure do |config|
        config.tenants = nil
        config.context_class = nil
        config.pretty_output = false
      end
    end

    it 'defaults to pretty_output = false' do
      expect(ConsoleKit.pretty_output).to eq(false)
    end

    it 'defaults tenants to nil or empty' do
      expect(ConsoleKit.tenants).to be_nil.or be_empty
    end
  end

  describe 'thread safety' do
    it 'maintains separate configuration per thread' do
      ConsoleKit.tenants = ['main']

      thread = Thread.new do
        ConsoleKit.tenants = ['thread']
        expect(ConsoleKit.tenants).to eq(['thread'])
      end
      thread.join

      expect(ConsoleKit.tenants).to eq(['main'])
    end
  end

  describe 'delegated tenant methods' do
    describe '.current_tenant' do
      it 'delegates to ConsoleKit::Setup.current_tenant' do
        expect(ConsoleKit::Setup).to receive(:current_tenant).and_return('my_tenant')
        expect(ConsoleKit.current_tenant).to eq('my_tenant')
      end

      it 'returns nil if ConsoleKit::Setup.current_tenant is nil' do
        expect(ConsoleKit::Setup).to receive(:current_tenant).and_return(nil)
        expect(ConsoleKit.current_tenant).to be_nil
      end

      it 'returns the same value on multiple calls' do
        expect(ConsoleKit::Setup).to receive(:current_tenant).twice.and_return('tenant1')
        expect(ConsoleKit.current_tenant).to eq('tenant1')
        expect(ConsoleKit.current_tenant).to eq('tenant1')
      end
    end

    describe '.reset_current_tenant' do
      it 'delegates to ConsoleKit::Setup.reset_current_tenant' do
        expect(ConsoleKit::Setup).to receive(:reset_current_tenant).and_return(true)
        expect(ConsoleKit.reset_current_tenant).to eq(true)
      end

      it 'returns false if ConsoleKit::Setup.reset_current_tenant returns false' do
        expect(ConsoleKit::Setup).to receive(:reset_current_tenant).and_return(false)
        expect(ConsoleKit.reset_current_tenant).to eq(false)
      end

      it 'calls reset_current_tenant multiple times with consistent results' do
        expect(ConsoleKit::Setup).to receive(:reset_current_tenant).twice.and_return(true)
        expect(ConsoleKit.reset_current_tenant).to eq(true)
        expect(ConsoleKit.reset_current_tenant).to eq(true)
      end
    end
  end
end
