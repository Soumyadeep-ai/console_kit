# frozen_string_literal: true

require 'forwardable'
require_relative 'base_connection_handler'

module ConsoleKit
  module Connections
    # Handles Redis connections
    class RedisConnectionHandler < BaseConnectionHandler
      extend Forwardable

      def_delegator :@context, :tenant_redis_db

      def connect
        db = tenant_redis_db
        Output.print_info(switch_message(db))
        Redis.current.select(db) if db
      rescue NoMethodError
        Output.print_warning('Redis.current is not available (deprecated in Redis v5+).')
      end

      def available? = defined?(Redis)

      private

      def switch_message(db)
        db ? "Switching to Redis DB: #{db}" : 'Resetting Redis connection to default'
      end
    end
  end
end
