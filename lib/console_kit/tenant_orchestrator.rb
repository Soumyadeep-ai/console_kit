# frozen_string_literal: true

require_relative 'tenant_state'
require_relative 'tenant_selector'
require_relative 'tenant_configurator'
require_relative 'output'
require_relative 'setup_ui'

module ConsoleKit
  # Orchestrates tenant lifecycle, selection, and configuration
  class TenantOrchestrator
    NO_TENANT_SELECTED = 'No tenant selected. Loading without tenant configuration.'

    class << self
      def auto_select? = (tenants.size == 1) || !$stdin.tty?

      def current_tenant = StateStore.tenant_key

      # Declares the current tenant key without touching connections. Re-assigning
      # the key that is already current preserves the fully-configured state.
      def current_tenant=(val)
        return if StateStore.tenant_key == val

        val.nil? ? StateStore.clear! : StateStore.current = TenantState.new(tenant_key: val)
      end

      def reapply
        key = current_tenant
        Output.silence { TenantSwitch.call(key) } if tenant_setup_successful?
      rescue StandardError => e
        Output.print_error("Failed to reapply tenant '#{key}': #{scrub(e.message)}")
      end

      def reset
        return Output.print_warning('Cannot reset tenant: No tenants configured.') unless tenants?

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

      private

      def tenant_setup_successful? = !current_tenant.to_s.empty?

      def perform_reset
        key = select_tenant_key
        return Output.print_warning('Tenant switch cancelled.') if key == :abort || key.blank?
        return Output.print_info("Already using tenant: #{key}. No changes made.") if key == current_tenant

        apply_reset(key)
      end

      def apply_reset(key)
        clear_current_tenant
        return Output.print_info(NO_TENANT_SELECTED) if %i[exit none].include?(key)

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

        Output.print_info(NO_TENANT_SELECTED) if key == :none
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

      def clear_current_tenant
        if current_tenant
          Output.print_warning("Resetting tenant: #{current_tenant}")
          TenantConfigurator.clear
        end
        self.current_tenant = nil
      end

      def handle_error(error)
        Output.print_error("Error setting up tenant: #{scrub(error.message)}")
        Output.print_backtrace(error)
      end

      def scrub(message) = Connections::DiagnosticHelpers.scrub(message)
    end
  end
end
