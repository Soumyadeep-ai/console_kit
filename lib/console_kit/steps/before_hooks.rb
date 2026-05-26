# frozen_string_literal: true

require_relative 'base'

module ConsoleKit
  module Steps
    # Runs before_switch hooks registered in configuration.
    class BeforeHooks < Base
      register priority: 40

      def call
        config.hook_registry.run(:before_switch, ctx.resolved_tenant)
        success
      rescue HookError => error
        failure(error.message)
      end
    end
  end
end
