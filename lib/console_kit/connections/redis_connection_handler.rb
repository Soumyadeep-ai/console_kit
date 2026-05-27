# frozen_string_literal: true

require_relative 'base_connection_handler'

module ConsoleKit
  module Connections
    # Handles Redis connections
    class RedisConnectionHandler < BaseConnectionHandler
      DEFAULT_REDIS_DB = 0

      class << self
        def redis_client = Redis.try(:current)

        def warn_no_auto_select(db_index)
          Output.print_warning("Redis DB #{db_index} configured but auto-select not supported with RedisClient. " \
                               'Ensure your Redis configuration sets the correct DB.')
        end
      end

      def connect
        db_index = context_attribute(:tenant_redis_db) || DEFAULT_REDIS_DB
        Output.print_info(switch_message(db_index))
        select_redis_db(db_index)
      end

      def available? = defined?(Redis)

      def diagnostics
        redis = self.class.redis_client if available?
        return unavailable_diagnostics('Redis') unless redis

        perform_diagnostics(redis)
      rescue StandardError => e
        error_diagnostics('Redis', e)
      end

      private

      def perform_diagnostics(redis)
        latency = measure_latency { redis.ping }
        info = redis.info
        build_redis_diagnostics(info['redis_version'], info['used_memory_human'], latency)
      end

      def build_redis_diagnostics(version, memory, latency)
        {
          name: 'Redis',
          status: :connected,
          latency_ms: latency,
          details: {
            db: context_attribute(:tenant_redis_db) || DEFAULT_REDIS_DB,
            version: version,
            memory: memory
          }
        }
      end

      def select_redis_db(db_index)
        klass = self.class
        redis = klass.redis_client
        if redis
          redis.select(db_index)
        elsif defined?(RedisClient) && db_index != DEFAULT_REDIS_DB
          klass.warn_no_auto_select(db_index)
        end
      rescue NoMethodError
        Output.print_warning('Redis.current is not available (deprecated in Redis v5+).')
      end

      def switch_message(db_index)
        db_index ? "Switching to Redis DB: #{db_index}" : 'Resetting Redis connection to default'
      end
    end
  end
end
