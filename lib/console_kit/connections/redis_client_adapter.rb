# frozen_string_literal: true

require_relative '../errors'
require_relative 'sql_strategy'

module ConsoleKit
  module Connections
    # Resolves the Redis client ConsoleKit is able to act on, reports which
    # logical DB that client currently points at without any network round trip,
    # and classifies how isolated a SELECT on it really is.
    #
    # The isolation model is decided empirically rather than by version
    # sniffing, because what matters is the object the application hands back,
    # not the gem version that built it. The resolver is called twice on this
    # thread and once on a fresh thread:
    #
    #   * the same object every time            -> :process_global
    #   * a different object on the other thread -> :scoped
    #   * nothing resolvable, or a new object on
    #     every call in one thread               -> :none
    #   * the probe itself could not run          -> :unknown
    #
    # :unknown is never an isolation claim: it says the model was not observed,
    # so nothing may assume isolation from it. A programming error inside the
    # probe is re-raised instead, because a bug in ConsoleKit must never be
    # laundered into a verdict the rest of the system trusts.
    class RedisClientAdapter
      # Matches anything that could carry a host, ACL username or password out
      # of a client error message.
      CREDENTIAL_URL = %r{\b(?:rediss?|unix)://\S*}i
      # A logical Redis DB index. This lives here rather than on the handler
      # because this class owns what a client will accept; the handler's
      # target_error delegates, so there is exactly one rule.
      DIGITS = /\A\d+\z/
      # Where this thread's isolation verdict is remembered, together with the
      # client it was observed on.
      MEMO_KEY = :console_kit_redis_isolation

      class << self
        def scrub(message) = message.to_s.gsub(CREDENTIAL_URL, '[redis-url]')

        # The Integer a client would accept for this value, or nil if the value
        # is not a usable DB index. Redis' own `databases` setting is
        # configurable, so no upper bound is imposed here; an index above it is
        # rejected by the server and surfaces from #connect! as a ConnectionError.
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

      # The client for the CURRENT thread. Never memoized: under the :scoped
      # model each thread must get its own object.
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
      # `Redis::Client#db`, the redis-client gem's `config.db`, and redis-rb
      # 4's `Redis#connection` hash. A client answering none of these cannot
      # report its DB at all, and the handler refuses non-default DBs for it.
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

      # The probe spawns a thread, and this adapter is built fresh for every
      # handler instance - which is one per tenant switch, and one per Rails
      # reload through the Railtie. The verdict describes the object the
      # application hands back, so it is remembered per thread and reused only
      # while that is still the very same object: a client swapped underneath
      # us fails the identity guard and is probed again.
      def remembered_isolation
        here = resolve
        memo = Thread.current[MEMO_KEY]
        return memo[:model] if memo && memo[:client].equal?(here)

        remember(here, probe_isolation(here))
      end

      # :unknown is the absence of a verdict rather than one, so it is not
      # remembered: a probe that could not run this time may well run next time.
      def remember(client, model)
        Thread.current[MEMO_KEY] = { client: client, model: model } unless model == :unknown
        model
      end

      def probe_isolation(here)
        return :none if here.nil? || !resolve.equal?(here)

        # A probe that could not reach the client has observed nothing. Reading
        # that as "the other thread got a different object, so the client must be
        # per-thread" would turn a failed observation into an isolation claim -
        # the strongest claim this class makes, on no evidence.
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
