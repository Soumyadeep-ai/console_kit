# frozen_string_literal: true

require_relative 'tenant_state'
require_relative 'tenant_selector'
require_relative 'tenant_configurator'
require_relative 'output'
require_relative 'setup_ui'
require_relative 'tenant_orchestrator'

# Core Logic for initial Setup
module ConsoleKit
  # Does the initial setup
  module Setup
    class << self
      def current_tenant = StateStore.tenant_key

      # Declares the current tenant key without touching connections. Assigning a
      # key that is already current preserves the fully-configured state.
      def current_tenant=(val)
        return if StateStore.tenant_key == val

        val.nil? ? StateStore.clear! : StateStore.current = TenantState.new(tenant_key: val)
      end

      def setup = TenantOrchestrator.run
      def tenant_setup_successful? = !current_tenant.to_s.empty?
      def reapply = TenantOrchestrator.reapply
      def reset_current_tenant = TenantOrchestrator.reset
      def auto_select? = TenantOrchestrator.auto_select?
    end
  end
end
