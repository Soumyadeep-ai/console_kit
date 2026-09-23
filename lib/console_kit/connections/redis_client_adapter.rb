# frozen_string_literal: true

require_relative '../errors'

module ConsoleKit
  module Connections
    # Resolves the Redis client ConsoleKit can act on, reports which logical DB
    # it points at without a network round trip, and classifies isolation by
    # probing the object the application hands back rather than by sniffing gem
    # versions: the same object on another thread -> :process_global, a
    # different one -> :scoped, nothing resolvable -> :none, a probe that could
    # not run -> :unknown, which is the absence of a verdict and never an
    # isolation claim.
    class RedisClientAdapter
      DIGITS = /\A\d+\z/
      MEMO_KEY = :console_kit_redis_isolation

      class << self
        # Redis' own `databases` setting is configurable, so no upper bound is
        # imposed here; the server rejects an index above it.
        def db_index(value)
          return value if value.is_a?(Integer) && !value.negative?
          return nil unless value.is_a?(String) && value.match?(DIGITS)

          value.to_i
        end

        # nil means "use the default DB" and is always valid. #db_index returns
        # nil exactly when the value is invalid, and 0 is truthy.
        def db_index_error(value)
          'expected a non-negative Integer or a digit String' unless value.nil? || db_index(value)
        end

        # Feature detection across the clients seen in the wild: redis-rb 5's
        # `Redis::Client#db`, the redis-client gem's `config.db`, redis-rb 4's
        # `Redis#connection` hash.
        def read_db(target)
          return target.db if target.respond_to?(:db)

          config = target.config if target.respond_to?(:config)
          return config.db if config.respond_to?(:db)

          info = target.connection if target.respond_to?(:connection)
          info[:db] if info.respond_to?(:[])
        end
      end

      # Never memoized: under the :scoped model each thread must get its own
      # client object.
      def client = resolve

      def selectable? = client.respond_to?(:select)
      def db_readable? = !current_db.nil?
      def isolation_model = @isolation_model ||= remembered_isolation

      # Reads cached connection state only; issues no command.
      def current_db
        Integer(client.then { |target| target && self.class.read_db(target) }, exception: false)
      end

      # SELECT is a write like any other: on a client that cannot say where it
      # is, the switch cannot be verified and no snapshot can put it back, so
      # nothing is written to one.
      def movable_to?(db) = selectable? && ![nil, db].include?(current_db)

      def select(db)
        return unless selectable?

        client.select(db)
      end

      private

      # `Redis.current` is the only process-wide handle any Redis client ever
      # offered. redis-rb 5.0 removed it and the redis-client gem never had one.
      def resolve
        return nil unless defined?(::Redis) && ::Redis.respond_to?(:current)

        ::Redis.current
      rescue StandardError => e
        raise e if ConsoleKit.programming_error?(e)

        nil
      end

      # The probe spawns a thread, so the verdict is remembered per thread - but
      # only while the application still hands back the very same client object.
      def remembered_isolation
        here = resolve
        memo = Thread.current[MEMO_KEY]
        return memo[:model] if memo && memo[:client].equal?(here)

        model = probe_isolation(here)
        # :unknown is not remembered: a probe that could not run this time may
        # well run next time.
        Thread.current[MEMO_KEY] = { client: here, model: model } unless model == :unknown
        model
      end

      def probe_isolation(here)
        return :none unless here && resolve.equal?(here)

        elsewhere = resolve_elsewhere
        return :unknown unless elsewhere

        elsewhere.equal?(here) ? :process_global : :scoped
      end

      # A probe that could not reach the client observed nothing; reading that
      # as "a different object, so per-thread" would turn a failed observation
      # into the strongest claim this class makes.
      def resolve_elsewhere
        Thread.new { resolve }.value
      rescue StandardError => e
        raise e if ConsoleKit.programming_error?(e)

        nil
      end
    end
  end
end
