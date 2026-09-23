# frozen_string_literal: true

require_relative 'output'
require_relative 'errors'
require_relative 'tenant_state'
require_relative 'connections/connection_manager'
require_relative 'connections/dashboard'
require_relative 'tenant_configurator/context_wrapper'
require_relative 'tenant_switch'

module ConsoleKit
  module TenantConfigurator
    class << self
      def context_mapping
        { partner_identifier: :partner_code }.merge(backend_context_mapping)
      end

      def configuration_success? = StateStore.configured?
      alias configuration_success configuration_success?

      def configuration_success=(val)
        StateStore.clear! unless val
      end

      def current_tenant_key = StateStore.tenant_key

      def current_tenant_key=(val)
        StateStore.clear! if val.nil?
      end

      def configure_tenant(key)
        switch_unless_current(key)
        true
      rescue StandardError, NotImplementedError => e
        report_failure(e, key)
        false
      end

      def clear
        ctx = ConsoleKit.configuration.context_class
        return unless ctx

        perform_clear(ctx, ContextWrapper.for_context(ctx))
      end

      private

      def backend_context_mapping
        Connections::BaseConnectionHandler.registry.to_h { |handler| [handler.context_attribute, handler.constants_key] }
      end

      def switch_unless_current(key)
        return if key == current_tenant_key && configuration_success

        TenantSwitch.call(key)
      end

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
        message = Connections::DiagnosticHelpers.scrub(error.message)
        Output.print_error("Failed to configure tenant '#{key}': #{message}")
        Output.print_backtrace(error)
        nil
      end
    end
  end
end
