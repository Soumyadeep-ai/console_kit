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
        mongo_db = tenant_mongo_db
        return if mongo_db.strip.empty?

        Output.print_info("Switching to MongoDB client: #{mongo_db}")
        Mongoid.override_client(mongo_db)
      rescue NoMethodError
        Output.print_warning('Mongoid.override_client is not defined.')
      end

      def available?
        defined?(Mongoid)
      end
    end
  end
end
