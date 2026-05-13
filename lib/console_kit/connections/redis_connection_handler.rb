# frozen_string_literal: true

require_relative 'base_connection_handler'

module ConsoleKit
  module Connections
    # Handles Redis connections
    class RedisConnectionHandler < BaseConnectionHandler
      DEFAULT_REDIS_DB = 0

      def connect
        db = context_attribute(:tenant_redis_db) || DEFAULT_REDIS_DB
        Output.print_info(switch_message(db))
        select_redis_db(db)
      end

      def available? = defined?(Redis)

      def diagnostics
        name = 'Redis'
        return unavailable_diagnostics(name) unless available?

        redis = fetch_redis_client
        return unavailable_diagnostics(name) unless redis

        latency = measure_latency { redis.ping }
        build_redis_diagnostics(redis.info, latency)
      rescue StandardError => e
        error_diagnostics(name, e)
      end

      private

      def fetch_redis_client
        Redis.respond_to?(:current) && Redis.current
      end

      def build_redis_diagnostics(info, latency)
        {
          name: 'Redis',
          status: :connected,
          latency_ms: latency,
          details: redis_details(info)
        }
      end

      def redis_details(info)
        {
          db: context_attribute(:tenant_redis_db) || DEFAULT_REDIS_DB,
          version: info['redis_version'],
          memory: info['used_memory_human']
        }
      end

      def select_redis_db(db)
        redis = fetch_redis_client
        if redis
          redis.select(db)
        elsif defined?(RedisClient) && db != DEFAULT_REDIS_DB
          warn_about_redis_client(db)
        end
      rescue NoMethodError
        Output.print_warning('Redis.current is not available (deprecated in Redis v5+).')
      end

      def warn_about_redis_client(db)
        Output.print_warning("Redis DB #{db} configured but auto-select not supported with RedisClient. " \
                             'Ensure your Redis configuration sets the correct DB.')
      end

      def switch_message(db)
        db ? "Switching to Redis DB: #{db}" : 'Resetting Redis connection to default'
      end
    end
  end
end
