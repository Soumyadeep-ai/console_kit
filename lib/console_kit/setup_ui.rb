# frozen_string_literal: true

module ConsoleKit
  # UI helpers for Setup
  module SetupUI
    ENVIRONMENT_WARNINGS = {
      'production' => -> { Output.print_error('!!! CAUTION: YOU ARE IN PRODUCTION ENVIRONMENT !!!') },
      'staging' => -> { Output.print_warning('CAUTION: You are in staging environment.') }
    }.freeze

    class << self
      def print_tenant_banner(key, config)
        Output.print_success("Tenant initialized: #{key}")
        print_env_warning(key, config)
        print_active_connections
        ConsoleKit::Connections::Dashboard.display if config.show_dashboard
      end

      private

      def print_env_warning(key, config)
        constants = config.tenants[key]&.[](:constants) || {}
        env = constants[:environment]&.to_s&.downcase
        ENVIRONMENT_WARNINGS[env]&.call if env
      end

      def print_active_connections
        ctx = ConsoleKit.configuration.context_class
        active = Connections::ConnectionManager.available_handlers(ctx).map do |handler|
          handler.class.name.demodulize.delete_suffix('ConnectionHandler')
        end

        Output.print_info("Active connections: #{active.join(', ')}") if active.any?
      end
    end
  end
end
