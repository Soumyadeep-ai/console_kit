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
        key = auto_select? ? single_tenant_key : interactive_select
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
        return false if dynamic_tenants?

        config.tenant_resolver_instance.size == 1
      end

      def single_tenant_key
        return nil if dynamic_tenants?

        config.tenant_resolver_instance.all_keys.first
      end

      def dynamic_tenants?
        config.tenants == :dynamic
      end

      def interactive_select
        if ::TTY_PROMPT_AVAILABLE
          PromptBuilder.new(config, history).select
        else
          LegacyTenantSelector.select
        end
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
