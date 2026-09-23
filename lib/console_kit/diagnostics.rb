# frozen_string_literal: true

require_relative 'errors'
require_relative 'tenant_state'
require_relative 'instrumentation'
require_relative 'connections/diagnostic_helpers'

module ConsoleKit
  module Diagnostics
    LEVELS = %i[basic full].freeze
    DEFAULT_TIMEOUT = 2
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

    module Runner
      class << self
        def call(handler, timeout: DEFAULT_TIMEOUT, level: :basic)
          Diagnostics.validate_level!(level)
          started = Connections::DiagnosticHelpers.clock_time
          outcome = execute(handler, level)
          report_overrun(started, timeout)
          resolve(handler, outcome)
        end

        def execute(handler, level)
          Instrumentation.instrument(EVENT, backend: handler.backend_key, level: level) do
            handler.diagnostics(level: level)
          end
        rescue StandardError, ScriptError => e
          e
        end

        private

        def resolve(handler, outcome) = outcome.is_a?(Hash) ? outcome : failed_row(handler, outcome)

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
