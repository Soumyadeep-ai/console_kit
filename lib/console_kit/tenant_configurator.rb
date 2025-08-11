# frozen_string_literal: true

require_relative 'output'

module ConsoleKit
  # For tenant configuration
  module TenantConfigurator
    class << self
      def configure_tenant(key, tenants, context_class)
        config = tenants[key]
        return missing_config_error(key) unless config

        apply_tenant_configuration(context_class, config[:constants])
        Output.print_success("Tenant set to: #{key}")
        true
      rescue StandardError => e
        handle_error(e, key)
        false
      end

      def clear(context_class)
        context_class.tenant_shard = nil
        context_class.tenant_mongo_db = nil
        context_class.partner_identifier = nil

        Output.print_info('Tenant context has been cleared.')
      end

      private

      def missing_config_error(key)
        Output.print_error("No configuration found for tenant: #{key}")
        false
      end

      def apply_tenant_configuration(context_class, constants)
        required_keys = %i[shard partner_code]
        missing_keys = required_keys.reject { |key| constants&.key?(key) }
        raise "Tenant constants missing keys: #{missing_keys.join(', ')}" unless missing_keys.empty?

        apply_context(context_class, constants)
        setup_database_connections(context_class)
      end

      def apply_context(context_class, constants)
        context_class.tenant_shard = constants[:shard]
        context_class.tenant_mongo_db = constants[:mongo_db]
        context_class.partner_identifier = constants[:partner_code]
      end

      def setup_database_connections(context_class)
        ApplicationRecord.establish_connection(context_class.tenant_shard.to_sym) if defined?(ApplicationRecord)
        return unless defined?(Mongoid) && Mongoid.respond_to?(:override_client)
        return if context_class.tenant_mongo_db.nil? || context_class.tenant_mongo_db.empty?

        Mongoid.override_client(context_class.tenant_mongo_db.to_s)
      end

      def handle_error(error, key)
        Output.print_error("Failed to configure tenant '#{key}': #{error.message}")
        Output.print_backtrace(error)
      end
    end
  end
end
