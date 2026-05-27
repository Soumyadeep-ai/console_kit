# spec/integration/full_console_flow_spec.rb
# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Full console flow', type: :integration do
  let(:context_class) do
    Class.new do
      class << self
        attr_accessor :partner_code, :shard
      end
    end
  end

  let(:full_pipeline_steps) do
    [
      ConsoleKit::Steps::EnvResolver,
      ConsoleKit::Steps::SafeguardCheck,
      ConsoleKit::Steps::TenantSelector,
      ConsoleKit::Steps::BeforeHooks,
      ConsoleKit::Steps::TenantConfigurator,
      ConsoleKit::Steps::ShardConnector,
      ConsoleKit::Steps::PromptApplier,
      ConsoleKit::Steps::AfterHooks
    ]
  end

  before do
    stub_const('IntegrationContext', context_class)
    ConsoleKit.configure do |c|
      c.tenants = {
        tenant_a: { constants: { partner_code: 'pa', shard: 'shard_01' } },
        tenant_b: { constants: { partner_code: 'pb', shard: 'shard_02' } }
      }
      c.context_class = 'IntegrationContext'
      c.context_field_mapping = { partner_code: :partner_code, shard: :shard }
      c.pipeline_steps = full_pipeline_steps
    end
    allow(ConsoleKit::Connections::ConnectionManager).to receive(:available_handlers).and_return([])
    allow(ConsoleKit::Output).to receive(:print_success)
    allow(ConsoleKit::Output).to receive(:print_info)
    allow(ConsoleKit::Output).to receive(:print_warning)
    allow(ConsoleKit::Output).to receive(:print_banner)
  end

  describe 'ENV override skips selector' do
    after { ENV.delete('CONSOLE_KIT_TENANT') }

    it 'sets tenant from ENV' do
      ENV['CONSOLE_KIT_TENANT'] = 'tenant_a'
      ConsoleKit::SwitchPipeline.run(config: ConsoleKit.configuration)
      expect(ConsoleKit.current_tenant).to eq(:tenant_a)
    end
  end

  describe 'ConsoleKit.with block switching' do
    it 'sets tenant inside block' do
      observed = nil
      ConsoleKit.with(:tenant_b) { observed = ConsoleKit.current_tenant }
      expect(observed).to eq(:tenant_b)
    end

    it 'yields control to the block' do
      yielded = false
      ConsoleKit.with(:tenant_b) { yielded = true }
      expect(yielded).to be true
    end

    it 're-raises exceptions from the block' do
      expect { ConsoleKit.with(:tenant_b) { raise 'oops' } }.to raise_error('oops')
    end

    it 'restores tenant after block completes' do
      ConsoleKit::Context.push(:tenant_a)
      ConsoleKit.with(:tenant_b) { nil }
      expect(ConsoleKit.current_tenant).to eq(:tenant_a)
    end

    it 'restores tenant after exception in block' do
      ConsoleKit::Context.push(:tenant_a)
      ConsoleKit.with(:tenant_b) { raise 'oops' } rescue nil # rubocop:disable Style/RescueModifier
      expect(ConsoleKit.current_tenant).to eq(:tenant_a)
    end

    it 'applies the requested tenant constants inside the block' do
      observed = nil
      ConsoleKit.with(:tenant_b) { observed = context_class.partner_code }
      expect(observed).to eq('pb')
    end
  end

  describe 'before_switch hook fires' do
    it 'calls hook with tenant key' do
      received = nil
      ConsoleKit.configuration.before_switch { |t| received = t }
      ConsoleKit::SwitchPipeline.run(tenant_key: :tenant_a, scoped: true, config: ConsoleKit.configuration)
      expect(received).to eq(:tenant_a)
    end
  end

  describe 'before_switch hook with on_error :abort' do
    it 'aborts switch when hook raises' do
      ConsoleKit.configuration.before_switch(on_error: :abort) { raise 'veto' }
      result = ConsoleKit::SwitchPipeline.run(tenant_key: :tenant_a, scoped: true, config: ConsoleKit.configuration)
      expect(result.failure?).to be true
    end
  end

  describe 'ConsoleKit.status' do
    it 'returns configured true after successful switch' do
      ConsoleKit::SwitchPipeline.run(tenant_key: :tenant_a, scoped: true, config: ConsoleKit.configuration)
      expect(ConsoleKit.status.configured).to be true
    end

    it 'returns correct tenant after successful switch' do
      ConsoleKit::SwitchPipeline.run(tenant_key: :tenant_a, scoped: true, config: ConsoleKit.configuration)
      expect(ConsoleKit.status.tenant).to eq(:tenant_a)
    end
  end

  describe 'end-to-end tenant context application' do
    it 'applies tenant constants to the configured context class' do
      ConsoleKit::SwitchPipeline.run(tenant_key: :tenant_a, scoped: true, config: ConsoleKit.configuration)
      expect(context_class.partner_code).to eq('pa')
    end

    it 'applies shard constant to the configured context class' do
      ConsoleKit::SwitchPipeline.run(tenant_key: :tenant_b, scoped: true, config: ConsoleKit.configuration)
      expect(context_class.shard).to eq('shard_02')
    end
  end
end
