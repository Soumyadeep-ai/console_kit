# frozen_string_literal: true

require_relative 'base_connection_handler'
require_relative 'redis_client_adapter'

module ConsoleKit
  module Connections
    # Handles Redis connections.
    #
    # ISOLATION MODEL - read this before relying on per-tenant Redis DBs.
    #
    # Redis has no per-thread notion of a "current database": SELECT is a
    # property of a connection. ConsoleKit cannot invent isolation it does not
    # own, so it probes the client the application actually installed and
    # reports the truth through #isolation_model / #thread_isolated?:
    #
    #   :scoped         the application hands out one client per thread or
    #                   fiber (for example `Redis.current` backed by a
    #                   Thread-local). SELECT then affects only the switching
    #                   thread and Redis really is tenant-isolated.
    #   :process_global `Redis.current` is the redis-rb 4.x memoized singleton,
    #                   shared by every thread in the process. SELECT is still
    #                   applied, for backward compatibility, but two threads on
    #                   different tenants WILL share one logical DB. A single
    #                   warning per process says so, and #thread_isolated? is
    #                   false. snapshot/restore capture and put back the
    #                   previous DB index so a failed switch cannot leave Redis
    #                   pointing at the wrong tenant.
    #   :none           no client handle is reachable. redis-rb 5.0 removed
    #                   `Redis.current`, and the redis-client gem (RedisClient)
    #                   never had a process-wide registry, so there is nothing
    #                   to SELECT on. #prepare then rejects any non-default DB
    #                   with UnsupportedBackendError instead of pretending the
    #                   switch worked; give each tenant its own Redis URL
    #                   (redis://host:6379/<db>) instead.
    #   :unknown        the probe itself failed against a reachable client, so
    #                   ConsoleKit does not know. It reports :unknown rather
    #                   than guessing :process_global, because an isolation
    #                   claim the rest of the system trusts must not be a
    #                   consolation prize for a failed probe. #thread_isolated?
    #                   is false, and whether a DB can be selected is still
    #                   decided by the client's own capabilities, not by this
    #                   verdict.
    class RedisConnectionHandler < BaseConnectionHandler
      CONTEXT_ATTRIBUTE = :tenant_redis_db
      DISPLAY_NAME = 'Redis'
      DEFAULT_REDIS_DB = 0

      PROCESS_GLOBAL_WARNING = 'Redis DB selection is process-wide with this client, so it is NOT isolated per ' \
                               'thread. Threads on different tenants share one logical DB.'

      class << self
        # Reset to re-arm the one-time process-global isolation warning.
        attr_accessor :isolation_warned
      end

      def available? = !!defined?(Redis) || !!defined?(RedisClient)

      def isolation_model = adapter.isolation_model
      def thread_isolated? = isolation_model == :scoped

      # Validate/resolve only, never mutates.
      def prepare(target)
        db = coerce_db(target)
        return if db == DEFAULT_REDIS_DB || (adapter.selectable? && adapter.db_readable?)

        raise UnsupportedBackendError, unsupported_message(db)
      end

      def snapshot = { db: adapter.current_db }

      def connect!(target)
        db = coerce_db(target)
        return if adapter.current_db == db || !adapter.selectable?

        Output.print_info(switch_message(db))
        warn_process_global
        apply(db)
      end

      # Compares the DB index we asked for against the one the live client
      # already knows it is on. A client that cannot report its DB is only ever
      # allowed to sit on the default DB (#prepare rejects everything else), so
      # there is nothing left to prove in that case.
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
        error_diagnostics(display_name, sanitized(e))
      end

      private

      # Availability, resolved DB identity and isolation model. No network call.
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
          raise(ConfigurationError, "ConsoleKit: Redis DB #{target.inspect} is not a non-negative integer.")
      end

      # Redis' own `databases` setting is configurable, so no upper bound is
      # imposed here; an index above it is rejected by the server and surfaces
      # from #connect! as a ConnectionError.
      def normalize(target)
        return target if target.is_a?(Integer) && !target.negative?
        return nil unless target.is_a?(String) && target.match?(/\A\d+\z/)

        target.to_i
      end

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
