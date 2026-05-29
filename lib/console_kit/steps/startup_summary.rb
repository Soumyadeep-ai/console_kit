# frozen_string_literal: true

require_relative 'base'

module ConsoleKit
  module Steps
    # Prints a one-line "ready" summary after all setup steps complete.
    # Skipped when no tenant resolved or inside a scoped switch.
    class StartupSummary < Base
      register priority: 90

      def call
        return success if ctx.scoped || ctx.resolved_tenant.nil?

        Output.print_success(summary_line)
        success
      end

      private

      def summary_line
        parts = [ctx.resolved_tenant.to_s, current_env]
        parts << 'readonly: ON' if ConsoleKit.readonly?
        parts << "preset: #{active_preset}" if active_preset
        parts.join('  |  ')
      end

      def active_preset
        ENV.fetch(Steps::PresetApplier::ROLE_ENV_KEY, nil)
      end
    end
  end
end
