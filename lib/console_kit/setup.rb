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

        key = select_tenant_key
        return Output.print_error('No tenant selected. Loading without tenant configuration.') unless key

        configure(key)
      rescue StandardError => e
        handle_error(e)
      end

      def tenant_setup_successful? = !@current_tenant.to_s.empty?

      def reset_current_tenant
        return warn_no_tenants unless tenants?

        warn_reset if @current_tenant
        TenantConfigurator.clear if @current_tenant

        @current_tenant = nil
        setup
      end

      private

      def configure(key)
        TenantConfigurator.configure_tenant(key)
        return unless TenantConfigurator.configuration_success

        @current_tenant = key
        Output.print_success("Tenant initialized: #{key}")
      end

      def tenants = ConsoleKit.configuration.tenants
      def context_class = ConsoleKit.configuration.context_class
      def tenants? = tenants&.any?
      def no_tenants? = !tenants?

      def select_tenant_key
        return tenants.keys.first if auto_select?

        TenantSelector.select
      end

      def auto_select? = single_tenant? || non_interactive?
      def single_tenant? = tenants.size == 1
      def non_interactive? = !$stdin.tty?
      def warn_no_tenants = Output.print_warning('Cannot reset tenant: No tenants configured.')
      def warn_reset = Output.print_warning("Resetting tenant: #{@current_tenant}")

      def handle_error(error)
        Output.print_error("Error setting up tenant: #{error.message}")
        Output.print_backtrace(error)
      end
    end
  end
end
