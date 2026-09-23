# frozen_string_literal: true

require_relative 'errors'
require_relative 'tenant_state'
require_relative 'instrumentation'
require_relative 'connections/diagnostic_helpers'

module ConsoleKit
  # On-demand connection diagnostics. A :basic row is resolved identity read out
  # of memory; a :full row may hit the network. Both run in the calling thread,
  # which is the only place a handler's backend scope exists.
  module Diagnostics
    LEVELS = %i[basic full].freeze
    DEFAULT_TIMEOUT = 2
    # Deliberately equal to DEFAULT_TIMEOUT: a cached row is then never older than
    # the budget a fresh check is given.
    CACHE_TTL_SECONDS = 2.0
    EVENT = 'console_kit.diagnostics'
    TIMEOUT_COUNTER = 'console_kit.diagnostics_timeout'

    class << self
      def run(level: :basic, timeout: DEFAULT_TIMEOUT)
        validate_level!(level)
        available_handlers.map { |handler| cached(handler, level, timeout) }
      end

      def clear_cache! = Cache.clear!

      def validate_level!(level)
        return level if LEVELS.include?(level)

        raise ConfigurationError,
              "ConsoleKit: unknown diagnostics level #{level.inspect}. Expected one of #{LEVELS.inspect}."
      end

      private

      def available_handlers
        Connections::ConnectionManager.available_handlers(ConsoleKit.configuration.context_class)
      end

      def cached(handler, level, timeout)
        Cache.fetch_row(handler, level) { handler.safe_diagnostics(timeout: timeout, level: level) }
      end
    end

    # Short-lived, per-thread memo of :full rows; a :basic row is a local read
    # already and is never cached. An entry survives only while its TTL holds, this
    # thread is still on the very TenantState that produced it, and the backend
    # still reports the identity it had when the row was written - Elasticsearch and
    # Redis are PROCESS-global, so another thread can move one without touching this
    # thread's TenantState.
    module Cache
      STORE_KEY = :console_kit_diagnostics_cache
      CACHED_LEVEL = :full

      class << self
        def fetch_row(handler, level)
          return yield unless level == CACHED_LEVEL

          key = [StateStore.tenant_key, level, handler.backend_key]
          identity = identity_of(handler)
          read(key, identity) || write(key, identity, yield)
        end

        def clear!
          Thread.current.thread_variable_set(STORE_KEY, nil)
        end

        private

        # A thread variable, not `Thread.current[]`: an entry is keyed on the
        # thread's TenantState, so it has to be read back in that same scope.
        def store
          thread = Thread.current
          thread.thread_variable_get(STORE_KEY) || thread.thread_variable_set(STORE_KEY, {})
        end

        def read(key, identity)
          entry = store[key]
          return nil unless entry

          unless current?(entry, identity)
            store.delete(key)
            return nil
          end

          entry[:row]
        end

        def write(key, identity, row)
          return row if row[:status] == :error

          purge_expired!
          store[key] = { row: row, expires_at: now + CACHE_TTL_SECONDS, state: state, identity: identity }
          row
        end

        def identity_of(handler)
          handler.diagnostic_identity
        rescue StandardError => e
          raise e if ConsoleKit.programming_error?(e)

          # Equal to nothing, including itself: an identity ConsoleKit could not
          # read is not evidence that a row is still true.
          Object.new
        end

        def purge_expired!
          store.delete_if { |_key, entry| !fresh?(entry) }
        end

        def fresh?(entry) = entry[:expires_at] > now && entry[:state].equal?(state)

        def current?(entry, identity) = fresh?(entry) && entry[:identity] == identity

        def state = StateStore.stored
        def now = Connections::DiagnosticHelpers.clock_time
      end
    end

    # One handler's diagnostics, executed in the CALLER's thread.
    #
    # A handler reads its backend state from thread-local storage - the SQL shard
    # frame, Mongoid's overrides, the scoped Redis client - so a check taken on a
    # worker thread describes a tenant nobody asked about, over a connection the
    # caller is not using. Nothing here can re-establish the caller's scope
    # elsewhere: only a handler knows what its scope is, and a process-global
    # backend cannot be re-pointed for one thread at all.
    #
    # `timeout` is therefore a budget that is REPORTED when a check overruns it,
    # not a bound that cuts one short: a slow backend blocks its caller until its
    # own driver gives up, and Interrupt still reaches that caller.
    module Runner
      class << self
        def call(handler, timeout: DEFAULT_TIMEOUT, level: :basic)
          Diagnostics.validate_level!(level)
          started = Connections::DiagnosticHelpers.clock_time
          outcome = execute(handler, level)
          report_overrun(started, timeout)
          resolve(handler, outcome)
        end

        # Never hands a backend's own failure to its caller: a diagnostics row is
        # not worth taking a console down for.
        def execute(handler, level)
          Instrumentation.instrument(EVENT, backend: handler.backend_key, level: level) do
            handler.diagnostics(level: level)
          end
        rescue StandardError, ScriptError => e
          e
        end

        private

        def resolve(handler, outcome) = outcome.is_a?(Hash) ? outcome : failed_row(handler, outcome)

        # An operator watching `diagnostics_timeout` still sees a backend that is
        # too slow to render; it is the report that survived, not the cut-off.
        def report_overrun(started, timeout)
          return if Connections::DiagnosticHelpers.clock_time - started <= timeout

          Instrumentation.increment(TIMEOUT_COUNTER)
        end

        def failed_row(handler, error)
          raise error if ConsoleKit.programming_error?(error)

          Connections::DiagnosticHelpers.error_diagnostics(handler.display_name, error)
        end
      end
    end
  end
end
