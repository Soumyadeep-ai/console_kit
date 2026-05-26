# frozen_string_literal: true

require_relative 'base'

module ConsoleKit
  module Steps
    # Runs after_switch hooks registered in configuration.
    class AfterHooks < Base
      register priority: 80

      def call
        config.hook_registry.run(:after_switch, ctx.resolved_tenant)
        success
      rescue HookError => error
        failure(error.message)
      end
    end
  end
end
