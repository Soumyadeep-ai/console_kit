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
        name = 'MongoDB'
        return unavailable_diagnostics(name) unless available?

        db = tenant_database
        latency = measure_latency { db.command(ping: 1) }
        build_mongo_diagnostics(db, latency)
      rescue StandardError => e
        error_diagnostics(name, e)
      end

      private

      def tenant_database
        override = context_attribute(:tenant_mongo_db).presence
        client = Mongoid.default_client
        return client.database unless override

        client.use(override).database
      end

      def build_mongo_diagnostics(database, latency)
        build_info = database.command(buildInfo: 1).first
        {
          name: 'MongoDB',
          status: :connected,
          latency_ms: latency,
          details: mongo_details(database.name, build_info['version'])
        }
      end

      def mongo_details(name, version)
        { database: name, version: version }
      end

      def switch_message(db)
        db ? "Switching to MongoDB client: #{db}" : 'Resetting MongoDB client to default'
      end
    end
  end
end
