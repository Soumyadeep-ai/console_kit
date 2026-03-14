# frozen_string_literal: true

require_relative 'tenant_selector'
require_relative 'tenant_configurator'
require_relative 'output'

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

        if current_tenant
          warn_reset
          TenantConfigurator.clear
        end

        self.current_tenant = nil
        setup
      end

      ENVIRONMENT_WARNINGS = {
        'production' => -> { Output.print_error('WARNING: You are connected to a PRODUCTION environment!') },
        'staging' => -> { Output.print_warning('You are connected to a staging environment.') }
      }.freeze

      private

      def run_setup
        return if tenant_setup_successful?

        ConsoleKit.configuration.validate!

        select_and_configure
      rescue StandardError => e
        handle_error(e)
      end

      def select_and_configure
        key = select_tenant_key
        return handle_selection_result(key) if %i[exit abort none].include?(key) || key.blank?

        configure(key)
      end

      def handle_selection_result(key)
        exit_on_key(key) if key == :exit

        case key
        when :abort, :none
          Output.print_info('No tenant selected. Loading without tenant configuration.')
        when nil, ''
          Output.print_error('Tenant selection failed. Loading without tenant configuration.')
        end
      end

      def exit_on_key(_key)
        Output.print_info('Exiting console...')
        Kernel.exit
      end

      def configure(key)
        TenantConfigurator.configure_tenant(key)
        return unless TenantConfigurator.configuration_success

        self.current_tenant = key
        print_tenant_banner(key)
      end

      def print_tenant_banner(key)
        constants = ConsoleKit.configuration.tenants[key]&.[](:constants) || {}
        env = constants[:environment]&.to_s&.downcase

        Output.print_success("Tenant initialized: #{key}")
        print_environment_warning(env) if env
        print_active_connections
      end

      def print_environment_warning(env)
        ENVIRONMENT_WARNINGS[env]&.call
      end

      def print_active_connections
        names = active_connection_names
        Output.print_info("Active connections: #{names.join(', ')}") unless names.empty?
      end

      def active_connection_names
        ctx = context_class
        return [] unless ctx

        handlers = ConsoleKit::Connections::ConnectionManager.available_handlers(ctx)
        handlers.map { |h| h.class.name.demodulize.delete_suffix('ConnectionHandler') }
      end

      def tenants = ConsoleKit.configuration.tenants
      def context_class = ConsoleKit.configuration.context_class
      def tenants? = tenants&.any?
      def no_tenants? = !tenants?
      def select_tenant_key = auto_select? ? tenants.keys.first : TenantSelector.select
      def auto_select? = single_tenant? || non_interactive?
      def single_tenant? = tenants.size == 1
      def non_interactive? = !$stdin.tty?
      def warn_no_tenants = Output.print_warning('Cannot reset tenant: No tenants configured.')
      def warn_reset = Output.print_warning("Resetting tenant: #{current_tenant}")

      def handle_error(error)
        Output.print_error("Error setting up tenant: #{error.message}")
        Output.print_backtrace(error)
      end
    end
  end
end
