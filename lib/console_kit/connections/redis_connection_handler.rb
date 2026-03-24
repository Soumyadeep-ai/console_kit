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
        select_redis_db(db.nil? ? DEFAULT_REDIS_DB : db)
      end

      def available? = defined?(Redis)

      def diagnostics
        return unavailable_diagnostics('Redis') unless available?

        redis = Redis.respond_to?(:current) && Redis.current
        return unavailable_diagnostics('Redis') unless redis

        latency = measure_latency { redis.ping }
        build_redis_diagnostics(redis, latency)
      rescue StandardError => e
        error_diagnostics('Redis', e)
      end

      private

      def build_redis_diagnostics(redis, latency)
        {
          name: 'Redis',
          status: :connected,
          latency_ms: latency,
          details: redis_details(redis)
        }
      end

      def redis_details(redis)
        info = redis.info
        {
          db: context_attribute(:tenant_redis_db) || DEFAULT_REDIS_DB,
          version: info['redis_version'],
          memory: info['used_memory_human']
        }
      end

      def select_redis_db(db)
        if Redis.respond_to?(:current) && Redis.current
          Redis.current.select(db)
        elsif defined?(RedisClient) && db != DEFAULT_REDIS_DB
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
