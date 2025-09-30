# frozen_string_literal: true

require_relative 'output'
require_relative 'connections/connection_manager'

module ConsoleKit
  # For tenant configuration
  module TenantConfigurator
    class << self
      attr_reader :configuration_success

      def configure_tenant(key)
        constants = ConsoleKit.configuration.tenants[key]&.[](:constants)
        return missing_config_error(key) unless constants

        perform_configuration(key, constants)
      rescue StandardError => e
        handle_error(e, key)
      end

      def clear
        @configuration_success = false
        %i[tenant_shard tenant_mongo_db partner_identifier].each do |attr|
          ConsoleKit.configuration.context_class.public_send("#{attr}=", nil)
        end
        Output.print_info('Tenant context has been cleared.')
      end

      private

      def validate_constants!(constants)
        missing = %i[shard partner_code] - constants.keys
        raise "Tenant constants missing keys: #{missing.join(', ')}" unless missing.empty?
      end

      def missing_config_error(key)
        @configuration_success = false
        Output.print_error("No configuration found for tenant: #{key}")
      end

      def perform_configuration(key, constants)
        validate_constants!(constants)
        apply_context(constants)
        configure_success(key)
      end

      def apply_context(constant)
        ctx = ConsoleKit.configuration.context_class
        ctx.tenant_shard = constant[:shard]
        ctx.tenant_mongo_db = constant[:mongo_db]
        ctx.partner_identifier = constant[:partner_code]

        setup_connections(ctx)
      end

      def setup_connections(context)
        ConsoleKit::Connections::ConnectionManager.available_handlers(context).each(&:connect)
      end

      def configure_success(key)
        Output.print_success("Tenant set to: #{key}")
        @configuration_success = true
      end

      def handle_error(error, key)
        @configuration_success = false
        Output.print_error("Failed to configure tenant '#{key}': #{error.message}")
        Output.print_backtrace(error)
      end
    end
  end
end
