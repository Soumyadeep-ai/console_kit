# frozen_string_literal: true

module ConsoleKit
  # Orchestrates tenant lifecycle, selection, and configuration
  class TenantOrchestrator
    class << self
      def auto_select? = (tenants.size == 1) || !$stdin.tty?

      def current_tenant = Setup.current_tenant

      def current_tenant=(val)
        Setup.current_tenant = val
      end

      def reapply
        return unless tenant_setup_successful?

        Output.silence do
          TenantConfigurator.current_tenant_key = nil
          TenantConfigurator.configure_tenant(current_tenant)
        end
      end

      def reset
        return warn_no_tenants unless tenants?

        perform_reset
      end

      def run
        return if tenant_setup_successful?

        perform_setup
      rescue StandardError => e
        handle_error(e)
      end

      def tenants = ConsoleKit.configuration.tenants
      def tenants? = tenants&.any?
      def select_tenant_key = auto_select? ? tenants.keys.first : TenantSelector.select
      def warn_no_tenants = Output.print_warning('Cannot reset tenant: No tenants configured.')
      def cancel_switch = Output.print_warning('Tenant switch cancelled.')
      def skip_tenant_message = Output.print_info('No tenant selected. Loading without tenant configuration.')

      private

      def tenant_setup_successful? = !current_tenant.to_s.empty?

      def perform_reset
        key = select_tenant_key
        return cancel_switch if key == :abort || key.blank?
        return already_on_tenant?(key) if key == current_tenant

        clear_current_tenant
        return skip_tenant_message if %i[exit none].include?(key)

        configure(key)
      end

      def perform_setup
        ConsoleKit.configuration.validate!
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

        Setup.current_tenant = key
        Prompt.apply
        SetupUI.print_tenant_banner(key, ConsoleKit.configuration)
      end

      def already_on_tenant?(key)
        Output.print_info("Already using tenant: #{key}. No changes made.")
        true
      end

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
