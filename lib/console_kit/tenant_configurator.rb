# frozen_string_literal: true

require_relative 'output'

module ConsoleKit
  # For tenant configuration
  module TenantConfigurator
    # Raised internally when tenant constants are absent.
    class NotConfigured < Error; end

    class << self
      def configuration_success = Context.current.configuration_success

      # :reek:ControlParameter -- shim setter; truthy val triggers mark_configured!
      def configuration_success=(val)
        Context.mark_configured! if val
      end

      def current_tenant_key = Context.current.tenant

      def current_tenant_key=(_val)
        nil
      end

      def configure_tenant(key, tenants, context_class)
        constants = tenants[key]&.[](:constants)
        raise NotConfigured, key unless constants

        setup_tenant(key, constants, context_class)
        true
      rescue NotConfigured => e
        Output.print_error("No configuration found for tenant: #{e.message}")
        false
      rescue StandardError => e
        handle_error(e, key)
        false
      end

      def clear(context_class)
        %i[tenant_shard tenant_mongo_db partner_identifier].each do |attr|
          context_class.public_send("#{attr}=", nil)
        end
        Output.print_info('Tenant context has been cleared.')
      end

      private

      def setup_tenant(key, constants, context_class)
        validate_constants!(constants)
        apply_context(context_class, constants)
        setup_connections(context_class)
        Output.print_success("Tenant set to: #{key}")
      end

      def validate_constants!(constants)
        missing = %i[shard partner_code] - constants.keys
        raise "Tenant constants missing keys: #{missing.join(', ')}" unless missing.empty?
      end

      def apply_context(ctx, constant)
        ctx.tenant_shard = constant[:shard]
        ctx.tenant_mongo_db = constant[:mongo_db]
        ctx.partner_identifier = constant[:partner_code]
      end

      # :reek:ManualDispatch -- necessary for Rails/Mongoid detection compatibility
      # :reek:NilCheck -- nil-check is idiomatic for optional mongo_db config
      def setup_connections(ctx)
        ApplicationRecord.establish_connection(ctx.tenant_shard.to_sym) if defined?(ApplicationRecord)
        return unless defined?(Mongoid) && Mongoid.respond_to?(:override_client)

        mongo_db = ctx.tenant_mongo_db
        return if mongo_db.nil? || mongo_db.empty?

        Mongoid.override_client(mongo_db.to_s)
      end

      def handle_error(error, key)
        Output.print_error("Failed to configure tenant '#{key}': #{error.message}")
        Output.print_backtrace(error)
      end
    end
  end
end
