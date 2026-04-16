# frozen_string_literal: true

require_relative 'tenant_selector'
require_relative 'tenant_configurator'
require_relative 'output'
require_relative 'setup_ui'

# Core Logic for initial Setup
module ConsoleKit
  # Does the initial setup
  module Setup
    class << self
      def current_tenant = Thread.current[:console_kit_current_tenant]

      def current_tenant=(val)
        Thread.current[:console_kit_current_tenant] = val
      end

      def setup = run_setup
      def tenant_setup_successful? = !current_tenant.to_s.empty?

      def reapply
        return unless tenant_setup_successful?

        Output.silence { TenantConfigurator.configure_tenant(current_tenant) }
      end

      def reset_current_tenant
        return warn_no_tenants unless tenants?

        perform_tenant_reset
      end

      private

      def perform_tenant_reset
        key = select_tenant_key
        return cancel_switch if key == :abort || key.blank?

        clear_current_tenant
        return skip_tenant_message if %i[exit none].include?(key)

        configure(key)
      end

      def run_setup
        return if tenant_setup_successful?

        config = ConsoleKit.configuration
        config.validate!
        select_and_configure
      rescue StandardError => exception
        handle_error(exception)
      end

      def select_and_configure
        key = select_tenant_key
        return handle_selection_result(key) if %i[exit abort none].include?(key) || key.blank?

        configure(key)
      end

      def handle_selection_result(key)
        exit_on_key if %i[exit abort].include?(key)

        skip_tenant_message if key == :none
        Output.print_error('Tenant selection failed. Loading without tenant configuration.') if key.blank?
      end

      def exit_on_key
        Output.print_info('Exiting console...')
        Kernel.exit
      end

      def configure(key)
        TenantConfigurator.configure_tenant(key)
        return unless TenantConfigurator.configuration_success

        self.current_tenant = key
        Prompt.apply
        SetupUI.print_tenant_banner(key, ConsoleKit.configuration)
      end

      def tenants = ConsoleKit.configuration.tenants
      def tenants? = tenants&.any?
      def select_tenant_key = auto_select? ? tenants.keys.first : TenantSelector.select
      def auto_select? = (tenants.size == 1) || !$stdin.tty?
      def warn_no_tenants = Output.print_warning('Cannot reset tenant: No tenants configured.')
      def cancel_switch = Output.print_warning('Tenant switch cancelled.')
      def skip_tenant_message = Output.print_info('No tenant selected. Loading without tenant configuration.')

      def clear_current_tenant
        if current_tenant
          Output.print_warning("Resetting tenant: #{current_tenant}")
          TenantConfigurator.clear
        end
        self.current_tenant = nil
      end

      def handle_error(error)
        Output.print_error("Error setting up tenant: #{error.message}")
        Output.print_backtrace(error)
      end
    end
  end
end
