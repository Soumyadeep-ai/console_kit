# lib/console_kit/configuration.rb
# frozen_string_literal: true

require_relative 'hook_registry'

module ConsoleKit
  # Stores and exposes all ConsoleKit configuration options.
  class Configuration
    DEFAULTS = {
      pretty_output: true,
      tenants: nil,
      tenant_resolver: nil,
      sql_base_class: 'ApplicationRecord',
      show_dashboard: false,
      env_tenant_key: 'CONSOLE_KIT_TENANT',
      production_environments: %w[production],
      protected_tenants: [],
      confirm_dangerous_context: false,
      required_tenant_keys: %i[shard partner_code],
      context_field_mapping: {
        partner_identifier: :partner_code,
        tenant_shard: :shard,
        tenant_mongo_db: :mongo_db,
        tenant_redis_db: :redis_db,
        tenant_elasticsearch_prefix: :elasticsearch_prefix,
        tenant_apartment_schema: :apartment_schema,
        tenant_acts_as_tenant_id: :acts_as_tenant_id
      },
      use_rails_sharding: false,
      default_shard: :default,
      shard_role: :writing,
      recent_tenant_history_path: '~/.console_kit_history',
      recent_tenant_limit: 5,
      benchmark: false,
      readonly_mode: false,
      readonly_environments: [],
      audit_log: false,
      audit_log_path: '~/.console_kit_audit.log',
      acts_as_tenant_model: nil,
      acts_as_tenant_finder: nil,
      presets: {}
    }.freeze

    DEFAULTS.each_key do |attr|
      define_method(attr)        { @data[attr] }
      define_method(:"#{attr}=") { |val| @data[attr] = val }
    end

    def initialize
      @data = DEFAULTS.transform_values do |default|
        default.is_a?(Array) || default.is_a?(Hash) ? default.dup : default
      end
      @hook_registry = HookRegistry.new
      @pipeline_steps = nil
    end

    attr_reader :hook_registry

    def tenant_resolver_instance
      @tenant_resolver_instance ||= TenantResolver.build(
        @data[:tenants] || {},
        @data[:tenant_resolver]
      )
    end

    def tenants=(val)
      @data[:tenants] = val
      @tenant_resolver_instance = nil
    end

    def tenant_resolver=(val)
      @data[:tenant_resolver] = val
      @tenant_resolver_instance = nil
    end

    def context_class
      val = @data[:context_class]
      case val
      when String, Symbol then resolve_context_class(val)
      else val
      end
    end

    def context_class=(val)
      @data[:context_class] = val
    end

    def pipeline_steps
      @pipeline_steps || ConsoleKit::StepRegistry.ordered
    end

    attr_writer :pipeline_steps

    def before_switch(on_error: :abort, &block)
      @hook_registry.register(:before_switch, on_error: on_error, &block)
    end

    def after_switch(on_error: :warn, &block)
      @hook_registry.register(:after_switch, on_error: on_error, &block)
    end

    def validate
      validate!
      true
    rescue Error
      false
    end

    def validate!
      raise Error, 'ConsoleKit: `tenants` is not configured.' if tenants.blank?
      raise Error, 'ConsoleKit: `tenants` must be a Hash, Array, or :dynamic.' \
        unless tenants.is_a?(Hash) || tenants.is_a?(Array) || tenants == :dynamic
      raise Error, 'ConsoleKit: `context_class` is not configured.' if @data[:context_class].blank?
    end

    private

    def resolve_context_class(val)
      klass = val.to_s.safe_constantize
      return klass if klass

      raise Error, "ConsoleKit: context_class '#{val}' could not be found. " \
                   'Ensure the class is defined before configuration is accessed.'
    end
  end
end
