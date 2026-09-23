# frozen_string_literal: true

require 'spec_helper'

# The 1.4.0 API that 1.5.0 keeps as delegators until 2.0.
RSpec.describe ConsoleKit::Deprecation do
  let(:setup) { ConsoleKit::Setup }
  let(:context_class) { Class.new { class << self; attr_accessor :partner_identifier, :tenant_shard; end } }

  before do
    allow(Kernel).to receive(:warn)
    ConsoleKit.configure do |config|
      config.tenants = { 'acme' => { constants: { shard: 'shard_acme', partner_code: 'ACME' } },
                         'globex' => { constants: { shard: 'shard_globex', partner_code: 'GBX' } } }
      config.context_class = context_class
    end
  end

  def silently(&) = ConsoleKit::Output.silence(&)

  describe '.call' do
    it 'warns once per name, not on every call' do
      2.times { described_class.call("spec-#{object_id}", 'something else') { nil } }
      expect(Kernel).to have_received(:warn).with(/spec-#{object_id} is deprecated/).once
    end

    it 'returns what the replacement returns' do
      expect(described_class.call('spec-value', 'x') { 42 }).to eq(42)
    end
  end

  describe 'ConsoleKit::Setup' do
    it '.setup runs the tenant setup' do
      silently { setup.setup }
      expect(ConsoleKit.current_tenant).to eq('acme')
    end

    it '.current_tenant reads the current tenant' do
      ConsoleKit::TenantOrchestrator.current_tenant = 'acme'
      expect(setup.current_tenant).to eq('acme')
    end

    it '.current_tenant= declares the current tenant' do
      setup.current_tenant = 'acme'
      expect(ConsoleKit.current_tenant).to eq('acme')
    end

    it '.tenant_setup_successful? is true once a tenant is set' do
      silently { setup.setup }
      expect(setup.tenant_setup_successful?).to be(true)
    end

    it '.reapply re-applies the current tenant' do
      silently { setup.setup }
      context_class.partner_identifier = nil
      setup.reapply
      expect(context_class.partner_identifier).to eq('ACME')
    end

    it '.reset_current_tenant re-selects the tenant' do
      setup.current_tenant = 'globex'
      silently { setup.reset_current_tenant }
      expect(ConsoleKit.current_tenant).to eq('acme')
    end

    it '.auto_select? answers like the orchestrator' do
      expect(setup.auto_select?).to eq(ConsoleKit::TenantOrchestrator.auto_select?)
    end
  end

  describe 'ConsoleKit configuration shortcuts' do
    it '.pretty_output reads the configuration' do
      ConsoleKit.configuration.pretty_output = false
      expect(ConsoleKit.pretty_output).to be(false)
    end

    it '.pretty_output= writes the configuration' do
      ConsoleKit.pretty_output = false
      expect(ConsoleKit.configuration.pretty_output).to be(false)
    end

    it '.tenants= writes the configuration' do
      ConsoleKit.tenants = { 'globex' => {} }
      expect(ConsoleKit.configuration.tenants).to eq('globex' => {})
    end

    it '.context_class reads the configuration' do
      expect(ConsoleKit.context_class).to eq(context_class)
    end

    it '.context_class= writes the configuration' do
      ConsoleKit.context_class = Object
      expect(ConsoleKit.configuration.context_class).to eq(Object)
    end

    it '.show_dashboard reads the configuration' do
      ConsoleKit.configuration.show_dashboard = true
      expect(ConsoleKit.show_dashboard).to be(true)
    end

    it '.show_dashboard= writes the configuration' do
      ConsoleKit.show_dashboard = true
      expect(ConsoleKit.configuration.show_dashboard).to be(true)
    end
  end

  describe 'ConsoleKit::Configuration#validate' do
    it 'is true for a valid configuration' do
      expect(ConsoleKit.configuration.validate).to be(true)
    end

    it 'is false instead of raising for an invalid one' do
      ConsoleKit.configuration.tenants = nil
      expect(ConsoleKit.configuration.validate).to be(false)
    end
  end
end
