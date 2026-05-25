# frozen_string_literal: true

require_relative 'output'
require_relative 'connections/connection_manager'
require_relative 'connections/dashboard'
require_relative 'tenant_configurator/context_wrapper'

module ConsoleKit
  # For tenant configuration
  module TenantConfigurator
    CONTEXT_MAPPING = {
      partner_identifier: :partner_code,
      tenant_shard: :shard,
      tenant_mongo_db: :mongo_db,
      tenant_redis_db: :redis_db,
      tenant_elasticsearch_prefix: :elasticsearch_prefix
    }.freeze

    class << self
      def configuration_success = Thread.current[:console_kit_configuration_success]

      def configuration_success=(val)
        Thread.current[:console_kit_configuration_success] = val
      end

      def current_tenant_key = Thread.current[:console_kit_current_tenant_key]

      def current_tenant_key=(val)
        Thread.current[:console_kit_current_tenant_key] = val
      end

      def configure_tenant(key)
        return true if key == current_tenant_key && configuration_success

        attempt_configuration(key)
      rescue StandardError => e
        handle_error?(e, key)
      end

      def clear
        ctx = ConsoleKit.configuration.context_class
        return unless ctx

        perform_clear(ContextWrapper.for_context(ctx))
      end

      private

      def attempt_configuration(key)
        constants = ConsoleKit.configuration.tenants[key]&.[](:constants)
        return missing_config_error?(key) unless constants

        execute_configuration(key, constants)
        configuration_success
      end

      def perform_clear(wrapper)
        return unless configuration_success || wrapper.any_set?

        reset_tenant(wrapper)
        Output.print_info('Tenant context has been cleared.')
        true
      end

      def reset_tenant(wrapper)
        self.configuration_success = false
        self.current_tenant_key = nil
        wrapper.reset
        setup_connections(wrapper.ctx)
      end

      def validate_constants!(constants)
        missing = %i[shard partner_code] - constants.keys
        raise Error, "Tenant constants missing keys: #{missing.join(', ')}" unless missing.empty?
      end

      def missing_config_error?(key)
        self.configuration_success = false
        Output.print_error("No configuration found for tenant: #{key}")
        false
      end

      def execute_configuration(key, constants)
        validate_constants!(constants)
        apply_context(constants)
        mark_success(key)
      end

      def apply_context(constant)
        wrapper = ContextWrapper.for_context(ConsoleKit.configuration.context_class)
        wrapper.assign(constant, CONTEXT_MAPPING).each do |attr, existing, configured|
          warn_case_mismatch(attr, existing, configured) if case_mismatch?(existing, configured)
        end
        setup_connections(wrapper.ctx)
      end

      def case_mismatch?(existing, new_value)
        existing.is_a?(String) && new_value.is_a?(String) &&
          existing != new_value &&
          existing.casecmp(new_value).zero?
      end

      def setup_connections(context)
        Connections::ConnectionManager.available_handlers(context).each(&:connect)
      end

      def mark_success(key)
        Output.print_success("Tenant set to: #{key}")
        self.configuration_success = true
        self.current_tenant_key = key
      end

      def warn_case_mismatch(attr, existing, configured)
        Output.print_warning(
          "#{attr} case mismatch: context had '#{existing}', config set '#{configured}'. " \
          'Check your ConsoleKit tenant configuration.'
        )
      end

      def handle_error?(error, key)
        self.configuration_success = false
        Output.print_error("Failed to configure tenant '#{key}': #{error.message}")
        Output.print_backtrace(error)
        false
      end
    end
  end
end
