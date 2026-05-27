# frozen_string_literal: true

require_relative 'base'

module ConsoleKit
  module Steps
    # Resolves tenant from CONSOLE_KIT_TENANT environment variable before interactive selection.
    class EnvResolver < Base
      register priority: 10

      def call
        env_value = ENV.fetch(config.env_tenant_key, nil)
        return success unless env_value

        resolved = find_tenant(env_value)
        return failure(failure_message(env_value)) unless resolved

        ctx.resolved_tenant = resolved
        ctx.skip_selector   = true
        success
      end

      private

      def find_tenant(env_value)
        config.tenant_resolver_instance.all_keys.find { |k| k.to_s.casecmp(env_value).zero? }
      end

      def failure_message(env_value)
        "#{config.env_tenant_key}='#{env_value}' not found in configured tenants"
      end
    end
  end
end
