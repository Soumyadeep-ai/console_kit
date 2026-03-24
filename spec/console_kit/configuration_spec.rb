# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ConsoleKit::Configuration do
  subject(:config) { described_class.new }

  describe '#initialize' do
    it 'sets default pretty_output to true' do
      expect(config.pretty_output).to be true
    end

    it 'sets default tenants to nil' do
      expect(config.tenants).to be_nil
    end

    it 'sets default context_class to nil' do
      expect(config.instance_variable_get(:@context_class)).to be_nil
    end

    it 'sets default sql_base_class to ApplicationRecord' do
      expect(config.sql_base_class).to eq('ApplicationRecord')
    end

    it 'sets default show_dashboard to false' do
      expect(config.show_dashboard).to be false
    end
  end

  describe '#context_class' do
    it 'returns nil when not set' do
      expect(config.context_class).to be_nil
    end

    it 'resolves a string constant' do
      stub_const('MyContext', Class.new)
      config.context_class = 'MyContext'
      expect(config.context_class).to eq(MyContext)
    end

    it 'resolves a symbol constant' do
      stub_const('MyContext', Class.new)
      config.context_class = :MyContext
      expect(config.context_class).to eq(MyContext)
    end

    it 'returns the class if set directly' do
      klass = Class.new
      config.context_class = klass
      expect(config.context_class).to eq(klass)
    end
  end

  describe '#validate!' do
    it 'raises error if tenants is nil' do
      config.tenants = nil
      config.context_class = 'Something'
      expect { config.validate! }.to raise_error(ConsoleKit::Error, /tenants.*not configured/)
    end

    it 'raises error if tenants is empty' do
      config.tenants = {}
      config.context_class = 'Something'
      expect { config.validate! }.to raise_error(ConsoleKit::Error, /tenants.*not configured/)
    end

    it 'raises error if context_class is nil' do
      config.tenants = { 'a' => {} }
      config.context_class = nil
      expect { config.validate! }.to raise_error(ConsoleKit::Error, /context_class.*not configured/)
    end

    it 'does not raise error when both are set' do
      config.tenants = { 'a' => {} }
      config.context_class = 'Something'
      expect { config.validate! }.not_to raise_error
    end
  end

  describe 'pretty_output=' do
    it 'accepts truthy values' do
      config.pretty_output = 'yes'
      expect(config.pretty_output).to eq('yes')
    end
  end

  describe 'sql_base_class=' do
    it 'accepts nil' do
      config.sql_base_class = nil
      expect(config.sql_base_class).to be_nil
    end

    it 'accepts a string' do
      config.sql_base_class = 'MyBase'
      expect(config.sql_base_class).to eq('MyBase')
    end
  end

  describe 'reset_configuration!' do
    it 'resets the configuration to a new instance' do
      old_config = ConsoleKit.configuration
      ConsoleKit.reset_configuration!
      expect(ConsoleKit.configuration).not_to equal(old_config)
    end
  end

  describe 'direct delegation' do
    it 'delegates tenants to configuration' do
      ConsoleKit.tenants = { 'delegated' => {} }
      expect(ConsoleKit.configuration.tenants).to eq({ 'delegated' => {} })
    end

    it 'delegates context_class to configuration' do
      klass = Class.new
      ConsoleKit.context_class = klass
      expect(ConsoleKit.configuration.context_class).to eq(klass)
    end

    it 'delegates pretty_output to configuration' do
      ConsoleKit.pretty_output = false
      expect(ConsoleKit.configuration.pretty_output).to be false
    end

    it 'allows direct access to configuration object' do
      expect(ConsoleKit.configuration).to be_a(described_class)
    end

    it 'has a non-nil tenants hash after configuration' do
      ConsoleKit.configure { |c| c.tenants = { 'a' => {} } }
      expect(ConsoleKit.tenants).not_to be_nil
    end
  end
end
