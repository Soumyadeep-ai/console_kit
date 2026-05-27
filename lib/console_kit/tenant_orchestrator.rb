# frozen_string_literal: true

module ConsoleKit
  # Orchestrates tenant switching lifecycle: run, reset, reapply.
  module TenantOrchestrator
    class << self
      def run
        SwitchPipeline.run(config: ConsoleKit.configuration)
      end

      def reset
        Context.reset!
        SwitchPipeline.run(config: ConsoleKit.configuration)
      end

      def reapply
        SwitchPipeline.run(config: ConsoleKit.configuration) if Context.current.configured?
      end

      def auto_select?
        (ConsoleKit.tenants&.size == 1) || !$stdin.tty?
      end

      def current_tenant
        Context.current.tenant
      end
    end
  end
end
