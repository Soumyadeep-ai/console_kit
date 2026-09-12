# frozen_string_literal: true

require_relative '../errors'
require_relative 'sql_strategy'

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
      CREDENTIAL_URL = %r{\b(?:rediss?|unix)://\S*}i
      DIGITS = /\A\d+\z/
      MEMO_KEY = :console_kit_redis_isolation

      class << self
        def scrub(message) = message.to_s.gsub(CREDENTIAL_URL, '[redis-url]')

        # Redis' own `databases` setting is configurable, so no upper bound is
        # imposed here; the server rejects an index above it.
        def db_index(value)
          return value if value.is_a?(Integer) && !value.negative?
          return nil unless value.is_a?(String) && value.match?(DIGITS)

          value.to_i
        end

        # nil means "use the default DB" and is always valid.
        def db_index_error(value)
          return if value.nil? || (value.is_a?(Integer) && !value.negative?)
          return if value.is_a?(String) && value.match?(DIGITS)

          'expected a non-negative Integer or a digit String'
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
        raw = client.then { |target| target && read_db(target) }
        raw.nil? ? nil : Integer(raw, exception: false)
      end

      def select(db)
        target = client
        target.select(db) if target.respond_to?(:select)
      end

      private

      # Feature detection across the clients seen in the wild: redis-rb 5's
      # `Redis::Client#db`, the redis-client gem's `config.db`, redis-rb 4's
      # `Redis#connection` hash.
      def read_db(target)
        return target.db if target.respond_to?(:db)
        return target.config.db if target.respond_to?(:config) && target.config.respond_to?(:db)

        info = target.connection if target.respond_to?(:connection)
        info[:db] if info.respond_to?(:[])
      end

      # `Redis.current` is the only process-wide handle any Redis client ever
      # offered. redis-rb 5.0 removed it and the redis-client gem never had one.
      def resolve
        return nil unless defined?(::Redis) && ::Redis.respond_to?(:current)

        ::Redis.current
      rescue StandardError => e
        raise e if programming_error?(e)

        nil
      end

      # The probe spawns a thread, so the verdict is remembered per thread - but
      # only while the application still hands back the very same client object.
      def remembered_isolation
        here = resolve
        memo = Thread.current[MEMO_KEY]
        return memo[:model] if memo && memo[:client].equal?(here)

        remember(here, probe_isolation(here))
      end

      # :unknown is not remembered: a probe that could not run this time may
      # well run next time.
      def remember(client, model)
        Thread.current[MEMO_KEY] = { client: client, model: model } unless model == :unknown
        model
      end

      def probe_isolation(here)
        return :none if here.nil? || !resolve.equal?(here)

        # A probe that could not reach the client observed nothing; reading that
        # as "a different object, so per-thread" would turn a failed observation
        # into the strongest claim this class makes.
        elsewhere = Thread.new { resolve }.value
        return :unknown if elsewhere.nil?

        elsewhere.equal?(here) ? :process_global : :scoped
      rescue StandardError => e
        raise e if programming_error?(e)

        :unknown
      end

      def programming_error?(error) = SqlStrategy.programming_error?(error)
    end
  end
end
