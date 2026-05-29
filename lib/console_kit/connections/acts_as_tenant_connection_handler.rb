# frozen_string_literal: true

require_relative 'base_connection_handler'

module ConsoleKit
  module Connections
    # Sets ActsAsTenant.current_tenant for model-based multi-tenancy.
    # Supports direct ID lookup or a custom finder proc.
    class ActsAsTenantConnectionHandler < BaseConnectionHandler
      def connect
        tenant_object = resolve_tenant_object
        Output.print_info("Setting ActsAsTenant.current_tenant: #{tenant_object.inspect}")
        ActsAsTenant.current_tenant = tenant_object
      end

      def available? = defined?(ActsAsTenant)

      def diagnostics
        return unavailable_diagnostics('ActsAsTenant') unless available?

        perform_diagnostics
      rescue StandardError => e
        error_diagnostics('ActsAsTenant', e)
      end

      private

      def perform_diagnostics
        current = ActsAsTenant.current_tenant
        {
          name: 'ActsAsTenant',
          status: current.present? ? :connected : :error,
          latency_ms: nil,
          details: { tenant_id: current&.try(:id), tenant_class: current&.class&.name }
        }
      end

      def resolve_tenant_object
        finder = ConsoleKit.configuration.acts_as_tenant_finder
        return finder.call(tenant_key, config_hash) if finder

        find_by_id
      end

      def find_by_id
        id = context_attribute(:tenant_acts_as_tenant_id)
        return nil unless id

        model_class = tenant_model_class
        return nil unless model_class

        model_class.find_by(id: id)
      end

      def tenant_model_class
        model_name = ConsoleKit.configuration.acts_as_tenant_model
        return nil unless model_name

        model_name.to_s.safe_constantize
      end

      def tenant_key = context_attribute(:partner_identifier)

      def config_hash
        ConsoleKit.configuration.context_field_mapping.each_with_object({}) do |(ctx_attr, const_key), hash|
          val = context_attribute(ctx_attr)
          hash[const_key] = val unless val.nil?
        end
      end
    end
  end
end
