# frozen_string_literal: true

require_relative 'tenant_selector'
require_relative 'tenant_configurator'
require_relative 'output'

# Core Logic for initial Setup
module ConsoleKit
  class << self
    attr_accessor :tenants, :context_class

    def setup
      return Output.print_error('No tenants configured.') if tenants.nil? || tenants.empty?

      tenant_key = resolve_tenant_key
      return Output.print_error('No tenant selected. Loading without tenant configuration.') unless tenant_key

      initialize_tenant(tenant_key)
    rescue StandardError => e
      handle_setup_error(e)
    end

    def configure
      yield self
    end

    private

    def resolve_tenant_key
      single_tenant? || non_interactive? ? tenants.keys.first : TenantSelector.select(tenants, tenants.keys)
    end

    def single_tenant?
      tenants.size == 1
    end

    def non_interactive?
      !$stdin.tty?
    end

    def initialize_tenant(tenant_key)
      TenantConfigurator.configure_tenant(tenant_key, tenants, context_class)
      Output.print_success("Tenant initialized: #{tenant_key}")
    end

    def handle_setup_error(error)
      Output.print_error("Error setting up tenant: #{error.message}")
      Output.print_backtrace(error)
    end
  end
end
