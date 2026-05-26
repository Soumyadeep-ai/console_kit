# spec/console_kit/configuration_spec.rb
# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ConsoleKit::Configuration do
  describe 'new config options' do
    subject(:config) { described_class.new }

    it 'defaults env_tenant_key to CONSOLE_KIT_TENANT' do
      expect(config.env_tenant_key).to eq('CONSOLE_KIT_TENANT')
    end

    it 'defaults production_environments to [production]' do
      expect(config.production_environments).to eq(%w[production])
    end

    it 'defaults protected_tenants to empty array' do
      expect(config.protected_tenants).to eq([])
    end

    it 'defaults confirm_dangerous_context to false' do
      expect(config.confirm_dangerous_context).to be false
    end

    it 'defaults required_tenant_keys to [:shard, :partner_code]' do
      expect(config.required_tenant_keys).to eq(%i[shard partner_code])
    end

    it 'defaults use_rails_sharding to false' do
      expect(config.use_rails_sharding).to be false
    end

    it 'defaults default_shard to :default' do
      expect(config.default_shard).to eq(:default)
    end

    it 'defaults shard_role to :writing' do
      expect(config.shard_role).to eq(:writing)
    end

    it 'defaults recent_tenant_history_path to ~/.console_kit_history' do
      expect(config.recent_tenant_history_path).to eq('~/.console_kit_history')
    end

    it 'defaults recent_tenant_limit to 5' do
      expect(config.recent_tenant_limit).to eq(5)
    end

    it 'defaults context_field_mapping with partner_identifier key' do
      expect(config.context_field_mapping).to include(partner_identifier: :partner_code)
    end

    it 'exposes hook_registry' do
      expect(config.hook_registry).to be_a(ConsoleKit::HookRegistry)
    end

    it 'registers before_switch hook via DSL' do
      called = false
      config.before_switch { called = true }
      config.hook_registry.run(:before_switch, :tenant_a)
      expect(called).to be true
    end

    it 'registers after_switch hook via DSL' do
      called = false
      config.after_switch { called = true }
      config.hook_registry.run(:after_switch, :tenant_a)
      expect(called).to be true
    end
  end
end
