# frozen_string_literal: true

module ConsoleKit
  # Value object representing current ConsoleKit state (tenant, configuration, environment, shard)
  Status = Struct.new(:tenant, :configured, :env, :shard, keyword_init: true) do
    class << self
      def build
        ctx = Context.current
        new(
          tenant: ctx.tenant,
          configured: ctx.configured?,
          env: env_name,
          shard: FiberStorage[:console_kit_resolved_shard]
        )
      end

      private

      # Determine environment from Rails or ENV
      # :reek:ManualDispatch -- necessary for Rails/ENV detection compatibility
      def env_name
        if defined?(Rails) && Rails.respond_to?(:env)
          Rails.env.to_s
        else
          ENV.fetch('RAILS_ENV', 'unknown')
        end
      end
    end

    def print
      Output.print_header('ConsoleKit Status')
      Output.print_info("  Tenant     : #{tenant || 'none'}")
      Output.print_info("  Configured : #{configured}")
      Output.print_info("  Environment: #{env}")
      Output.print_info("  Shard      : #{shard || 'none'}")
    end
  end
end
