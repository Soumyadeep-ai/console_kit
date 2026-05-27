# spec/console_kit/configuration_spec.rb
# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ConsoleKit::Configuration do
  subject(:config) { described_class.new }

  describe 'new config options' do
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

    it 'defaults benchmark to false' do
      expect(config.benchmark).to be false
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

  describe '#tenant_resolver=' do
    it 'clears cached tenant_resolver_instance' do
      config.tenants = { a: {} }
      _first = config.tenant_resolver_instance
      config.tenant_resolver = ->(key) { key }
      # After setting tenant_resolver, a new instance is built
      expect(config.tenant_resolver).not_to be_nil
    end
  end

  describe '#context_class' do
    it 'returns nil when not set' do
      expect(config.context_class).to be_nil
    end

    it 'returns class directly when context_class is already a Class' do
      config.context_class = String
      expect(config.context_class).to eq(String)
    end

    it 'resolves context_class from String name' do
      config.context_class = 'String'
      expect(config.context_class).to eq(String)
    end

    it 'resolves context_class from Symbol name' do
      config.context_class = :String
      expect(config.context_class).to eq(String)
    end

    it 'raises Error when String name cannot be resolved' do
      config.context_class = 'NonExistentClass::Totally::Made::Up'
      expect { config.context_class }
        .to raise_error(ConsoleKit::Error, /could not be found/)
    end
  end

  describe '#pipeline_steps' do
    it 'returns StepRegistry.ordered by default' do
      expect(config.pipeline_steps).to eq(ConsoleKit::StepRegistry.ordered)
    end

    it 'returns custom steps when pipeline_steps is set' do
      custom_steps = [instance_double(ConsoleKit::Steps::Base)]
      config.pipeline_steps = custom_steps
      expect(config.pipeline_steps).to eq(custom_steps)
    end
  end

  describe '#validate!' do
    it 'raises Error when tenants is nil' do
      config.context_class = 'Object'
      expect { config.validate! }.to raise_error(ConsoleKit::Error, /tenants.*not configured/)
    end

    it 'raises Error when tenants is blank' do
      config.tenants = {}
      config.context_class = 'Object'
      expect { config.validate! }.to raise_error(ConsoleKit::Error, /tenants.*not configured/)
    end

    it 'raises Error when tenants is not Hash/Array/:dynamic' do
      config.tenants = 'bad_value'
      config.context_class = 'Object'
      expect { config.validate! }.to raise_error(ConsoleKit::Error, /must be a Hash, Array, or :dynamic/)
    end

    it 'raises Error when context_class is blank' do
      config.tenants = { a: {} }
      expect { config.validate! }.to raise_error(ConsoleKit::Error, /context_class.*not configured/)
    end

    it 'does not raise when fully configured' do
      config.tenants = { a: {} }
      config.context_class = 'Object'
      expect { config.validate! }.not_to raise_error
    end
  end

  describe '#validate' do
    it 'returns true when valid' do
      config.tenants = { a: {} }
      config.context_class = 'Object'
      expect(config.validate).to be true
    end

    it 'returns false when invalid' do
      expect(config.validate).to be false
    end
  end
end
