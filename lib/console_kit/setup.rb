# frozen_string_literal: true

require_relative 'tenant_selector'
require_relative 'tenant_configurator'
require_relative 'output'

# Core Logic for initial Setup
module ConsoleKit
  # Does the initial setup
  module Setup
    class << self
      attr_reader :current_tenant

      def setup
        return Output.print_error('No tenants configured.') if no_tenants?

        tenant_key = select_tenant_key
        return Output.print_error('No tenant selected. Loading without tenant configuration.') unless tenant_key

        configure_tenant(tenant_key)
      rescue StandardError => e
        handle_error(e)
      end

      def tenant_setup_successful?
        !@current_tenant.nil? && !@current_tenant.to_s.empty?
      end

      def reset_current_tenant
        return handle_reset_no_tenants if no_tenants?

        handle_reset_existing_tenant if @current_tenant
        @current_tenant = nil

        setup
        tenant_setup_successful?
      end

      private

      def no_tenants?
        ConsoleKit.configuration.tenants.nil? || ConsoleKit.configuration.tenants.empty?
      end

      def select_tenant_key
        return ConsoleKit.configuration.tenants.keys.first if auto_select_tenant?

        TenantSelector.select(ConsoleKit.configuration.tenants, ConsoleKit.configuration.tenants.keys)
      end

      def auto_select_tenant?
        single_tenant? || non_interactive?
      end

      def single_tenant?
        ConsoleKit.configuration.tenants.size == 1
      end

      def non_interactive?
        !$stdin.tty?
      end

      def handle_reset_no_tenants
        Output.print_warning('Cannot reset tenant: No tenants configured.')
        false
      end

      def handle_reset_existing_tenant
        Output.print_warning("Resetting tenant: #{@current_tenant}")
        TenantConfigurator.clear(ConsoleKit.configuration.context_class)
      end

      def configure_tenant(tenant_key)
        success = TenantConfigurator.configure_tenant(tenant_key, ConsoleKit.configuration.tenants,
                                                      ConsoleKit.configuration.context_class)
        return unless success

        @current_tenant = tenant_key
        Output.print_success("Tenant initialized: #{tenant_key}")
      end

      def handle_error(error)
        Output.print_error("Error setting up tenant: #{error.message}")
        Output.print_backtrace(error)
      end
    end
  end
end
