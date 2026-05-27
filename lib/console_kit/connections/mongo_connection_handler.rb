# frozen_string_literal: true

require_relative 'base_connection_handler'

module ConsoleKit
  module Connections
    # Handles MongoDB connections
    class MongoConnectionHandler < BaseConnectionHandler
      def initialize(context)
        super
        @mongoid = nil
      end

      def connect
        @mongoid = Mongoid
        db = context_attribute(:tenant_mongo_db).presence
        switch_mongo(db)
      rescue NoMethodError
        Output.print_warning('Mongoid client override is not available in this version of Mongoid.')
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

      def switch_mongo(db)
        unless db
          Output.print_info('Resetting MongoDB client to default')
          return reset_overrides
        end

        if named_client?(db)
          switch_to_named_client(db)
        else
          switch_to_database(db)
        end
      end

      def switch_to_named_client(db)
        Output.print_info("Switching to MongoDB client: #{db}")
        @mongoid.override_client(db)
      end

      def switch_to_database(db)
        Output.print_info("Switching to MongoDB database: #{db}")
        @mongoid.override_database(db)
      end

      def reset_overrides
        @mongoid.override_client(nil)
      rescue NoMethodError
        nil
      ensure
        @mongoid.override_database(nil)
      end

      def named_client?(name)
        @mongoid::Config.clients.key?(name.to_s)
      rescue StandardError
        false
      end
    end
  end
end
