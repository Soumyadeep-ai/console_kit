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

      private

      def switch_message(db)
        db ? "Switching to MongoDB client: #{db}" : 'Resetting MongoDB client to default'
      end
    end
  end
end
