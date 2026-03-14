# frozen_string_literal: true

require_relative 'base_connection_handler'

module ConsoleKit
  module Connections
    # Handles Redis connections
    class RedisConnectionHandler < BaseConnectionHandler
      DEFAULT_REDIS_DB = 0

      def connect
        db = context_attribute(:tenant_redis_db)
        Output.print_info(switch_message(db))
        select_redis_db(db || DEFAULT_REDIS_DB)
      end

      def available? = defined?(Redis)

      private

      def select_redis_db(db)
        if Redis.respond_to?(:current) && Redis.current
          Redis.current.select(db)
        elsif defined?(RedisClient)
          Output.print_warning("Redis DB #{db} configured but auto-select not supported with RedisClient. " \
                               'Ensure your Redis configuration sets the correct DB.')
        end
      rescue NoMethodError
        Output.print_warning('Redis.current is not available (deprecated in Redis v5+).')
      end

      def switch_message(db)
        db ? "Switching to Redis DB: #{db}" : 'Resetting Redis connection to default'
      end
    end
  end
end
