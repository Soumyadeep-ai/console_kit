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
        return if tenant_mongo_db.blank?

        Output.print_info("Switching to MongoDB client: #{tenant_mongo_db}")
        Mongoid.override_client(tenant_mongo_db)
      rescue NoMethodError
        Output.print_warning('Mongoid.override_client is not defined.')
      end

      def available? = defined?(Mongoid)
    end
  end
end
