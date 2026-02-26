# frozen_string_literal: true

require_relative 'output'
require_relative 'connections/connection_manager'

module ConsoleKit
  # For tenant configuration
  module TenantConfigurator
    class << self
      def configuration_success = Thread.current[:console_kit_configuration_success]

      def configuration_success=(val)
        Thread.current[:console_kit_configuration_success] = val
      end

      def configure_tenant(key)
        constants = ConsoleKit.configuration.tenants[key]&.[](:constants)
        return missing_config_error(key) unless constants

        perform_configuration(key, constants)
      rescue StandardError => e
        handle_error(e, key)
      end

      def clear
        self.configuration_success = false
        ctx = ConsoleKit.configuration.context_class
        return unless ctx

        reset_context_attributes(ctx)
        Output.print_info('Tenant context has been cleared.')
      end

      private

      def reset_context_attributes(ctx)
        %i[tenant_shard tenant_mongo_db partner_identifier].each do |attr|
          ctx.public_send("#{attr}=", nil)
        end
      end

      def validate_constants!(constants)
        missing = %i[shard partner_code] - constants.keys
        raise Error, "Tenant constants missing keys: #{missing.join(', ')}" unless missing.empty?
      end

      def missing_config_error(key)
        self.configuration_success = false
        Output.print_error("No configuration found for tenant: #{key}")
      end

      def perform_configuration(key, constants)
        validate_constants!(constants)
        apply_context(constants)
        configure_success(key)
      end

      def validate_context_interface!(ctx)
        missing = %i[tenant_shard= tenant_mongo_db= partner_identifier=].reject { |s| ctx.respond_to?(s) }
        return if missing.empty?

        raise Error, "Context class #{ctx} does not implement the required interface. " \
                     "Missing setters: #{missing.join(', ')}"
      end

      def apply_context(constant)
        ctx = ConsoleKit.configuration.context_class
        validate_context_interface!(ctx)

        assign_context_attributes(ctx, constant)
        setup_connections(ctx)
      end

      def assign_context_attributes(ctx, constant)
        ctx.tenant_shard = constant[:shard]
        ctx.tenant_mongo_db = constant[:mongo_db]
        ctx.partner_identifier = constant[:partner_code]
      end

      def setup_connections(context)
        ConsoleKit::Connections::ConnectionManager.available_handlers(context).each(&:connect)
      end

      def configure_success(key)
        Output.print_success("Tenant set to: #{key}")
        self.configuration_success = true
      end

      def handle_error(error, key)
        self.configuration_success = false
        Output.print_error("Failed to configure tenant '#{key}': #{error.message}")
        Output.print_backtrace(error)
      end
    end
  end
end
