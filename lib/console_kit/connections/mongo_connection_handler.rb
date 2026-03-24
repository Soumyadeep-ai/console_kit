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

        client = Mongoid.default_client
        latency = measure_latency { client.database.command(ping: 1) }
        build_mongo_diagnostics(client, latency)
      rescue StandardError => e
        error_diagnostics('MongoDB', e)
      end

      private

      def build_mongo_diagnostics(client, latency)
        build_info = client.database.command(buildInfo: 1).first
        {
          name: 'MongoDB',
          status: :connected,
          latency_ms: latency,
          details: {
            database: client.database.name,
            version: build_info['version']
          }
        }
      end

      def switch_message(db)
        db ? "Switching to MongoDB client: #{db}" : 'Resetting MongoDB client to default'
      end
    end
  end
end
