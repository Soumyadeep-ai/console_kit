# frozen_string_literal: true

require 'forwardable'
require_relative 'base_connection_handler'

module ConsoleKit
  module Connections
    # Handles MongoDB connections
    class MongoConnectionHandler < BaseConnectionHandler
      extend Forwardable

      def_delegator :@context, :tenant_mongo_db

      def connect
        db = tenant_mongo_db.presence
        Output.print_info(switch_message(db))
        Mongoid.override_client(db)
      rescue NoMethodError
        Output.print_warning('Mongoid.override_client is not defined.')
      end

      def available? = defined?(Mongoid)

      private

      def switch_message(db)
        db ? "Switching to MongoDB client: #{db}" : 'Resetting MongoDB client to default'
      end
    end
  end
end
