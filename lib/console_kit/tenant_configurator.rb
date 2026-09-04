# frozen_string_literal: true

require_relative 'output'
require_relative 'errors'
require_relative 'tenant_state'
require_relative 'connections/connection_manager'
require_relative 'connections/dashboard'
require_relative 'tenant_configurator/context_wrapper'
require_relative 'tenant_switch'

module ConsoleKit
  # Console-facing tenant configuration.
  #
  # Since 1.5.0 the actual work is done by the transactional TenantSwitch
  # coordinator; this module keeps the pre-1.5 non-raising API used by the
  # console flow (it reports failures through Output and returns false).
  module TenantConfigurator
    CONTEXT_MAPPING = {
      partner_identifier: :partner_code,
      tenant_shard: :shard,
      tenant_mongo_db: :mongo_db,
      tenant_redis_db: :redis_db,
      tenant_elasticsearch_prefix: :elasticsearch_prefix
    }.freeze

    class << self
      def configuration_success? = StateStore.configured?
      alias configuration_success configuration_success?

      # Compat shim: assigning a falsey value clears the current tenant state.
      def configuration_success=(val)
        StateStore.clear! unless val
      end

      def current_tenant_key = StateStore.tenant_key

      # Compat shim: assigning nil clears the current tenant state, forcing the
      # next `configure_tenant` call to re-apply from scratch.
      def current_tenant_key=(val)
        StateStore.clear! if val.nil?
      end

      def configure_tenant(key)
        return true if key == current_tenant_key && configuration_success

        TenantSwitch.call(key)
        Output.print_success("Tenant set to: #{key}")
        true
      rescue StandardError => e
        report_failure(e, key)
        false
      end

      def clear
        ctx = ConsoleKit.configuration.context_class
        return unless ctx

        perform_clear(ctx, ContextWrapper.for_context(ctx))
      end

      private

      def perform_clear(ctx, wrapper)
        return unless configuration_success || wrapper.any_set?

        TenantSwitch.clear(context: ctx)
        Output.print_info('Tenant context has been cleared.')
        true
      end

      def report_failure(error, key)
        return print_missing_config(key) if tenant_missing?(error)

        print_error_details(error, key)
      end

      def tenant_missing?(error)
        error.is_a?(TenantNotFoundError) ||
          (error.is_a?(TenantSwitchError) && error.original_error.is_a?(TenantNotFoundError))
      end

      def print_missing_config(key)
        Output.print_error("No configuration found for tenant: #{key}")
        nil
      end

      def print_error_details(error, key)
        Output.print_error("Failed to configure tenant '#{key}': #{error.message}")
        Output.print_backtrace(error)
        nil
      end
    end
  end
end
