# frozen_string_literal: true

require 'active_support/core_ext/object/blank'
require 'active_support/core_ext/object/inclusion'
require 'active_support/core_ext/string/inflections'

require_relative 'console_kit/errors'
require_relative 'console_kit/readonly_mode'
require_relative 'console_kit/version'
require_relative 'console_kit/fiber_storage'
require_relative 'console_kit/context'
require_relative 'console_kit/tenant_resolver'
require_relative 'console_kit/hook_registry'
require_relative 'console_kit/step_registry'
require_relative 'console_kit/pipeline_context'
require_relative 'console_kit/benchmarker'
require_relative 'console_kit/switch_pipeline'
require_relative 'console_kit/scoped_switcher'
require_relative 'console_kit/status'
require_relative 'console_kit/configuration'
require_relative 'console_kit/setup'
require_relative 'console_kit/prompt'
require_relative 'console_kit/output'
require_relative 'console_kit/tenant_history'
require_relative 'console_kit/audit_logger'
require_relative 'console_kit/prompt_builder'
require_relative 'console_kit/connections/connection_manager'
require_relative 'console_kit/connections/shard_resolver'
require_relative 'console_kit/connections/shard_strategy'
require_relative 'console_kit/connections/shard_strategy_factory'
require_relative 'console_kit/connections/diagnostic_helpers'
require_relative 'console_kit/connections/base_connection_handler'
require_relative 'console_kit/connections/mongo_connection_handler'
require_relative 'console_kit/connections/redis_connection_handler'
require_relative 'console_kit/connections/elasticsearch_connection_handler'
require_relative 'console_kit/connections/sql_connection_handler'
require_relative 'console_kit/connections/apartment_connection_handler'
require_relative 'console_kit/connections/acts_as_tenant_connection_handler'
require_relative 'console_kit/connections/table_formatter'
require_relative 'console_kit/connections/table_renderer'
require_relative 'console_kit/connections/dashboard'
require_relative 'console_kit/tenant_configurator/context_wrapper'
require_relative 'console_kit/steps/base'
require_relative 'console_kit/steps/welcome_banner'
require_relative 'console_kit/steps/preset_applier'
require_relative 'console_kit/steps/env_resolver'
require_relative 'console_kit/steps/safeguard_check'
require_relative 'console_kit/steps/tenant_selector'
require_relative 'console_kit/steps/before_hooks'
require_relative 'console_kit/steps/tenant_configurator'
require_relative 'console_kit/steps/shard_connector'
require_relative 'console_kit/steps/prompt_applier'
require_relative 'console_kit/steps/after_hooks'
require_relative 'console_kit/steps/readonly_enforcer'
require_relative 'console_kit/steps/audit_log_writer'
require_relative 'console_kit/steps/startup_summary'
require_relative 'console_kit/console_helpers'
# :nocov:
require_relative 'console_kit/railtie' if defined?(Rails::Railtie)
# :nocov:
require_relative 'console_kit/doctor/check_registry'
require_relative 'console_kit/doctor/checks/base'
require_relative 'console_kit/doctor/checks/tenants_configured'
require_relative 'console_kit/doctor/checks/tenant_keys_unique'
require_relative 'console_kit/doctor/checks/context_class_resolvable'
require_relative 'console_kit/doctor/checks/required_constants_present'
require_relative 'console_kit/doctor/checks/adapter_supported'
require_relative 'console_kit/doctor/checks/sharding_compatibility'
require_relative 'console_kit/doctor/checks/hook_callable_arity'
require_relative 'console_kit/doctor/checks/history_path_writable'
require_relative 'console_kit/doctor/checks/readonly_mode_compatibility'
require_relative 'console_kit/doctor/checks/audit_log_path_writable'
require_relative 'console_kit/doctor/checks/apartment_compatibility'
require_relative 'console_kit/doctor/checks/acts_as_tenant_compatibility'
require_relative 'console_kit/doctor/checks/preset_config_valid'
require_relative 'console_kit/doctor/check_runner'
require_relative 'console_kit/doctor/reporter'

# Top-level namespace and public API for ConsoleKit.
module ConsoleKit
  class << self
    def configure
      yield(configuration)
    end

    def configuration
      @configuration ||= Configuration.new
    end

    def reset_configuration!
      @configuration = nil
      Context.reset!
      ReadonlyMode.deactivate!
    end

    def readonly? = ReadonlyMode.active?

    # Existing accessors (backward-compat)
    def pretty_output         = configuration.pretty_output
    def tenants               = configuration.tenants
    def context_class         = configuration.context_class
    def show_dashboard        = configuration.show_dashboard
    def current_tenant        = Context.current.tenant
    def reset_current_tenant  = Setup.reset_current_tenant

    def pretty_output=(val)
      configuration.pretty_output = val
    end

    def tenants=(val)
      configuration.tenants = val
    end

    def context_class=(val)
      configuration.context_class = val
    end

    def show_dashboard=(val)
      configuration.show_dashboard = val
    end

    def enable_pretty_output
      configuration.pretty_output = true
    end

    def disable_pretty_output
      configuration.pretty_output = false
    end

    # v2.0.0 public API
    def with(tenant_key, &)
      ScopedSwitcher.for(configuration).with(tenant_key, &)
    end

    def switch_tenant!
      result = SwitchPipeline.run(config: configuration)
      result.success ? result.tenant : nil
    end

    def status
      Status.build
    end
  end
end
