# frozen_string_literal: true

require_relative 'base_connection_handler'

module ConsoleKit
  module Connections
    # Handles MongoDB connections
    class MongoConnectionHandler < BaseConnectionHandler
      def connect
        db = context_attribute(:tenant_mongo_db).presence
        Output.print_info(switch_message(db))
        Mongoid.override_database(db)
      rescue NoMethodError
        Output.print_warning('Mongoid.override_database is not available in this version of Mongoid.')
      end

      def available? = defined?(Mongoid)

      def diagnostics
        return unavailable_diagnostics('MongoDB') unless available?

        perform_diagnostics
      rescue StandardError => e
        error_diagnostics('MongoDB', e)
      end

      private

      def perform_diagnostics
        db = tenant_database
        latency = measure_latency { db.command(ping: 1) }
        info = db.command(buildInfo: 1).first
        build_mongo_diagnostics(db.name, info['version'], latency)
      end

      def build_mongo_diagnostics(name, version, latency)
        {
          name: 'MongoDB',
          status: :connected,
          latency_ms: latency,
          details: { database: name, version: version }
        }
      end

      def tenant_database
        override = context_attribute(:tenant_mongo_db).presence
        client = Mongoid.default_client
        (override ? client.use(override) : client).database
      end

      def switch_message(db)
        db ? "Switching to MongoDB client: #{db}" : 'Resetting MongoDB client to default'
      end
    end
  end
end
