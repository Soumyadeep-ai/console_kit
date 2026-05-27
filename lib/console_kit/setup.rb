# frozen_string_literal: true

require_relative 'tenant_selector'
require_relative 'tenant_configurator'
require_relative 'output'
require_relative 'tenant_orchestrator'

# Core Logic for initial Setup
module ConsoleKit
  # Thin shim that delegates lifecycle operations to TenantOrchestrator and Context.
  module Setup
    class << self
      def current_tenant
        Context.current.tenant
      end

      def current_tenant=(val)
        Context.push(val) if val
      end

      def tenant_setup_successful?
        Context.current.configured?
      end

      def setup
        TenantOrchestrator.run
      end

      def reapply
        TenantOrchestrator.reapply
      end

      def reset_current_tenant
        TenantOrchestrator.reset
      end

      def auto_select?
        TenantOrchestrator.auto_select?
      end
    end
  end
end
