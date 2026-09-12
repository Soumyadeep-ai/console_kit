# frozen_string_literal: true

require_relative 'base_connection_handler'
require_relative 'redis_client_adapter'

module ConsoleKit
  module Connections
    # Handles Redis connections.
    #
    # SELECT is a property of a connection, not of a thread, so isolation is
    # probed rather than assumed: #isolation_model reports :scoped,
    # :process_global, :none or :unknown, and only :scoped is really
    # tenant-isolated (see the README for what each state means). #prepare
    # rejects a non-default DB when no selectable, readable client is reachable.
    class RedisConnectionHandler < BaseConnectionHandler
      backend :redis,
              display_name: 'Redis',
              context_attribute: :tenant_redis_db,
              constants_key: :redis_db,
              detail_label: 'Redis DB'

      DEFAULT_REDIS_DB = 0

      PROCESS_GLOBAL_WARNING = 'Redis DB selection is process-wide with this client, so it is NOT isolated per ' \
                               'thread. Threads on different tenants share one logical DB.'

      class << self
        # Reset to re-arm the one-time process-global isolation warning.
        attr_accessor :isolation_warned

        def target_error(value) = RedisClientAdapter.db_index_error(value)
      end

      def available? = !!defined?(Redis) || !!defined?(RedisClient)

      def isolation_model = adapter.isolation_model
      def thread_isolated? = isolation_model == :scoped

      # Under :process_global the DB index is shared by every thread, so a cached
      # diagnostic row has to stay true for it. Reads cached state, issues no
      # command.
      def diagnostic_identity = adapter.current_db

      def prepare(target)
        validate_target!(target)
        db = coerce_db(target)
        return if target.nil? || (adapter.selectable? && adapter.db_readable?)

        raise UnsupportedBackendError, unsupported_message(db)
      end

      def snapshot = { db: adapter.current_db }

      def connect!(target)
        db = coerce_db(target)
        return unless adapter.movable_to?(db)

        Output.print_info(switch_message(db))
        warn_process_global
        apply(db)
      end

      # ConsoleKit never writes to a client that cannot report its DB, so a nil
      # reading here is the DB the application chose rather than an unproved
      # switch: only a target that asked for no DB at all can reach it.
      def verify!(target)
        expected = coerce_db(target)
        actual = adapter.current_db
        return true if verified?(expected, actual)

        raise verification_error(expected, actual)
      end

      def restore(state)
        db = state && state[:db]
        return if db.nil? || adapter.current_db == db

        apply(db)
      end

      def diagnostics(level: :basic)
        return unavailable_diagnostics unless available?

        level == :full ? full_diagnostics : basic_diagnostics
      rescue StandardError => e
        raise e if ConsoleKit.programming_error?(e)

        error_diagnostics(display_name, sanitized(e))
      end

      private

      # No network call.
      def basic_diagnostics
        {
          name: display_name, status: adapter.selectable? ? :connected : :unknown, latency_ms: nil,
          details: { db: resolved_db, isolation: isolation_model }
        }
      end

      def full_diagnostics
        redis = adapter.client
        return basic_diagnostics if redis.nil?

        latency = measure_latency { redis.ping }
        info = redis.info
        {
          name: display_name, status: :connected, latency_ms: latency,
          details: { db: resolved_db, version: info['redis_version'], memory: info['used_memory_human'] }
        }
      end

      def apply(db)
        adapter.select(db)
      rescue ConsoleKit::Error
        raise
      rescue StandardError => e
        raise ConnectionError.new("#{display_name} SELECT #{db} failed: #{RedisClientAdapter.scrub(e.message)}",
                                  backend: display_name, operation: :connect)
      end

      def verified?(expected, actual)
        actual == expected || (actual.nil? && expected == DEFAULT_REDIS_DB)
      end

      def warn_process_global
        return unless isolation_model == :process_global
        return if self.class.isolation_warned

        self.class.isolation_warned = true
        Output.print_warning(PROCESS_GLOBAL_WARNING)
      end

      def coerce_db(target)
        return DEFAULT_REDIS_DB if target.nil?

        normalize(target) ||
          raise(ConfigurationError, "ConsoleKit: Redis DB #{scrub(target.inspect)} is not a non-negative integer.")
      end

      def normalize(target) = RedisClientAdapter.db_index(target)

      def unsupported_message(db)
        "#{display_name} DB #{db} was requested but this client exposes no connection that can be selected and " \
          "verified without a round-trip (isolation model: #{isolation_model}). " \
          'Point each tenant at its own Redis URL instead.'
      end

      def switch_message(db)
        db == DEFAULT_REDIS_DB ? 'Resetting Redis connection to default' : "Switching to Redis DB: #{db}"
      end

      def resolved_db = adapter.current_db || coerce_db(target)
      def sanitized(error) = StandardError.new(RedisClientAdapter.scrub(error.message))
      def adapter = @adapter ||= RedisClientAdapter.new
    end
  end
end
