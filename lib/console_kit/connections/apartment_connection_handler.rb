# frozen_string_literal: true

require_relative 'base_connection_handler'

module ConsoleKit
  module Connections
    # Handles Apartment gem schema switching for PostgreSQL-based multi-tenancy.
    class ApartmentConnectionHandler < BaseConnectionHandler
      def connect
        schema = resolved_schema
        Output.print_info("Switching Apartment schema to: #{schema}")
        Apartment::Tenant.switch!(schema)
      end

      def available? = defined?(Apartment)

      def diagnostics
        return unavailable_diagnostics('Apartment') unless available?

        perform_diagnostics
      rescue StandardError => e
        error_diagnostics('Apartment', e)
      end

      private

      def perform_diagnostics
        current = Apartment::Tenant.current
        {
          name: 'Apartment',
          status: current == resolved_schema ? :connected : :error,
          latency_ms: nil,
          details: { schema: current }
        }
      end

      def resolved_schema
        context_attribute(:tenant_apartment_schema).presence || context_attribute(:partner_identifier).to_s
      end
    end
  end
end
