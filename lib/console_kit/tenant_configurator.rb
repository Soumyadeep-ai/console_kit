# frozen_string_literal: true

require_relative 'output'
require_relative 'connections/connection_manager'
require_relative 'connections/dashboard'

module ConsoleKit
  # For tenant configuration
  module TenantConfigurator
    class << self
      HANDLER_ATTRIBUTES = {
        Connections::SqlConnectionHandler => :tenant_shard,
        Connections::MongoConnectionHandler => :tenant_mongo_db,
        Connections::RedisConnectionHandler => :tenant_redis_db,
        Connections::ElasticsearchConnectionHandler => :tenant_elasticsearch_prefix
      }.freeze

      def configuration_success = Thread.current[:console_kit_configuration_success]

      def configuration_success=(val)
        Thread.current[:console_kit_configuration_success] = val
      end

      def configure_tenant(key)
        constants = ConsoleKit.configuration.tenants[key]&.[](:constants)
        return missing_config_error(key) unless constants

        perform_configuration(key, constants)
      rescue StandardError => exception
        handle_error(exception, key)
      end

      def clear
        ctx = ConsoleKit.configuration.context_class
        return unless ctx

        reset_tenant(ctx)
        Output.print_info('Tenant context has been cleared.')
      end

      private

      def reset_tenant(ctx)
        self.configuration_success = false
        reset_context_attributes(ctx)
        setup_connections(ctx)
      end

      def reset_context_attributes(ctx)
        available_context_attributes(ctx).each do |attr|
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

      def handler_available?(handler_class)
        handler_class.new(nil).available?
      rescue NotImplementedError, StandardError => exception
        false
      end

      def available_context_attributes(ctx)
        attributes = ctx.respond_to?(:partner_identifier=) ? [:partner_identifier] : []

        HANDLER_ATTRIBUTES.each_with_object(attributes) do |(handler, attr), list|
          next unless ctx.respond_to?("#{attr}=")
          next unless handler_available?(handler)

          list << attr
        end
      end

      def apply_context(constant)
        ctx = ConsoleKit.configuration.context_class
        assign_context_attributes(ctx, constant)
        setup_connections(ctx)
      end

      def assign_context_attributes(ctx, constant)
        attribute_to_constant = {
          partner_identifier: :partner_code,
          tenant_shard: :shard,
          tenant_mongo_db: :mongo_db,
          tenant_redis_db: :redis_db,
          tenant_elasticsearch_prefix: :elasticsearch_prefix
        }

        available_context_attributes(ctx).each do |attr|
          ctx.public_send("#{attr}=", constant[attribute_to_constant[attr]])
        end
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
