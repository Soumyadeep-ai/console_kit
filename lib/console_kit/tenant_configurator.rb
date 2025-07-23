# frozen_string_literal: true

require_relative 'output'

module ConsoleKit
  # For tenant configuration
  module TenantConfigurator
    class << self
      def configure_tenant(key, tenants, context_class)
        config = tenants[key]
        return Output.print_error("No configuration found for tenant: #{key}") unless config

        constants = config[:constants]
        apply_context(context_class, constants)
        setup_database_connections(context_class)

        Output.print_success("Tenant set to: #{key}")
      rescue StandardError => e
        Output.print_error("Failed to configure tenant '#{key}': #{e.message}")
        Output.print_backtrace(e)
      end

      private

      def apply_context(context_class, constants)
        context_class.tenant_shard = constants[:shard]
        context_class.tenant_mongo_db = constants[:mongo_db]
        context_class.partner_identifier = constants[:partner_code]
      end

      def setup_database_connections(context_class)
        ApplicationRecord.establish_connection(context_class.tenant_shard.to_sym) if defined?(ApplicationRecord)
        return unless defined?(Mongoid) && Mongoid.respond_to?(:override_client)

        Mongoid.override_client(context_class.tenant_mongo_db.to_s)
      end
    end
  end
end
