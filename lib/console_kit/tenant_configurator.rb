# frozen_string_literal: true

require_relative 'output'
require_relative 'connections/connection_manager'
require_relative 'connections/dashboard'
require_relative 'tenant_configurator/context_wrapper'

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

      def current_tenant_key = Thread.current[:console_kit_current_tenant_key]

      def current_tenant_key=(val)
        Thread.current[:console_kit_current_tenant_key] = val
      end

      def configure_tenant(key)
        return true if key == current_tenant_key && configuration_success

        constants = ConsoleKit.configuration.tenants[key]&.[](:constants)
        return missing_config_error?(key) unless constants

        run_configuration(key, constants)
      rescue StandardError => e
        handle_error?(e, key)
      end

      def clear
        ctx = ConsoleKit.configuration.context_class
        return unless ctx

        attributes = available_context_attributes(ctx)
        wrapper = ContextWrapper.new(ctx, attributes)
        return unless configuration_success || wrapper.any_set?

        reset_tenant(wrapper)
        Output.print_info('Tenant context has been cleared.')
        true
      end

      private

      def reset_tenant(wrapper)
        self.configuration_success = false
        self.current_tenant_key = nil
        wrapper.reset
        setup_connections(wrapper.ctx)
      end

      def validate_constants!(constants)
        missing = %i[shard partner_code] - constants.keys
        raise Error, "Tenant constants missing keys: #{missing.join(', ')}" unless missing.empty?
      end

      def missing_config_error?(key)
        self.configuration_success = false
        Output.print_error("No configuration found for tenant: #{key}")
        false
      end

      def run_configuration(key, constants)
        validate_constants!(constants)
        apply_context(constants)
        configure_success?(key)
      end

      def handler_available?(handler_class)
        handler_class.new(nil).available?
      rescue NotImplementedError, StandardError
        false
      end

      def available_context_attributes(ctx)
        methods = ctx.public_methods
        attributes = methods.include?(:partner_identifier=) ? [:partner_identifier] : []
        attributes + handler_attributes_for(methods)
      end

      def handler_attributes_for(methods)
        HANDLER_ATTRIBUTES.each_with_object([]) do |(handler, attr), list|
          next unless methods.include?(:"#{attr}=")
          next unless handler_available?(handler)

          list << attr
        end
      end

      def apply_context(constant)
        ctx = ConsoleKit.configuration.context_class
        attributes = available_context_attributes(ctx)
        wrapper = ContextWrapper.new(ctx, attributes)

        mapping = {
          partner_identifier: :partner_code,
          tenant_shard: :shard,
          tenant_mongo_db: :mongo_db,
          tenant_redis_db: :redis_db,
          tenant_elasticsearch_prefix: :elasticsearch_prefix
        }

        wrapper.assign(constant, mapping)
        setup_connections(ctx)
      end

      def setup_connections(context)
        Connections::ConnectionManager.available_handlers(context).each(&:connect)
      end

      def configure_success?(key)
        Output.print_success("Tenant set to: #{key}")
        self.configuration_success = true
        self.current_tenant_key = key
        true
      end

      def handle_error?(error, key)
        self.configuration_success = false
        Output.print_error("Failed to configure tenant '#{key}': #{error.message}")
        Output.print_backtrace(error)
        false
      end
    end
  end
end
