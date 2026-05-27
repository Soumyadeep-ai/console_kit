# lib/console_kit/steps/tenant_selector.rb
# frozen_string_literal: true

require_relative 'base'

module ConsoleKit
  module Steps
    # Pipeline step that resolves the active tenant via interactive selection
    # or auto-selects when only one tenant is configured.
    class TenantSelector < Base
      register priority: 30

      def call
        return success if ctx.skip_selector || ctx.scoped

        resolve_tenant
      end

      private

      def resolve_tenant
        key = auto_select? ? config.tenants.keys.first : interactive_select
        return failure('Tenant selection aborted.') if aborted?(key)

        apply_tenant(key)
      end

      def aborted?(key)
        key == :abort || !key
      end

      def apply_tenant(key)
        ctx.resolved_tenant = key
        history.record(key)
        success
      end

      def auto_select?
        config.tenants&.size == 1
      end

      def interactive_select
        if tty_prompt_available?
          PromptBuilder.new(config, history).select
        else
          LegacyTenantSelector.select
        end
      end

      def tty_prompt_available?
        require 'tty-prompt'
        true
      rescue LoadError
        false
      end

      def history
        @history ||= TenantHistory.new(
          config.recent_tenant_history_path,
          config.recent_tenant_limit
        )
      end
    end
  end
end
