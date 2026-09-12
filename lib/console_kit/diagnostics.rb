# frozen_string_literal: true

require 'English'
require_relative 'errors'
require_relative 'tenant_state'
require_relative 'instrumentation'
require_relative 'connections/diagnostic_helpers'

module ConsoleKit
  # On-demand connection diagnostics. A :basic row is resolved identity read out
  # of memory and runs inline; a :full row may hit the network and is bounded by Runner.
  module Diagnostics
    LEVELS = %i[basic full].freeze
    DEFAULT_TIMEOUT = 2
    # Deliberately equal to DEFAULT_TIMEOUT: a cached row is then never older than
    # the window a fresh check was allowed to take anyway.
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

      def programming_error?(error) = ConsoleKit.programming_error?(error)

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
      UNCACHEABLE = %i[error timeout].freeze
      # 8 tenants x 4 backends: headroom without letting a long-lived console
      # accumulate one entry per tenant ever visited.
      CAPACITY = 32

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
          Thread.current.thread_variable_get(STORE_KEY) ||
            Thread.current.thread_variable_set(STORE_KEY, {})
        end

        def read(key, identity)
          entry = store[key]
          return nil unless entry

          unless current?(entry, identity)
            store.delete(key)
            return nil
          end

          touch(key, entry)
          entry[:row]
        end

        def write(key, identity, row)
          return row if UNCACHEABLE.include?(row[:status])

          purge_expired!
          touch(key, row: row, expires_at: now + CACHE_TTL_SECONDS, state: state, identity: identity)
          evict_to_capacity!
          row
        end

        def identity_of(handler)
          handler.diagnostic_identity
        rescue StandardError => e
          raise e if Diagnostics.programming_error?(e)

          # Equal to nothing, including itself: an identity ConsoleKit could not
          # read is not evidence that a row is still true.
          Object.new
        end

        # Ruby Hashes preserve insertion order, so delete-then-reinsert moves a key
        # to the end and makes `each_key.first` the least-recently-used key.
        def touch(key, entry)
          store.delete(key)
          store[key] = entry
        end

        def purge_expired!
          store.delete_if { |_, entry| !fresh?(entry) }
        end

        def evict_to_capacity!
          store.delete(store.each_key.first) while store.size > CAPACITY
        end

        def fresh?(entry) = entry[:expires_at] > now && entry[:state].equal?(state)

        def current?(entry, identity) = fresh?(entry) && entry[:identity] == identity

        def state = StateStore.stored
        def now = Connections::DiagnosticHelpers.clock_time
      end
    end

    # One diagnostics request plus the latch its caller blocks on.
    class Job
      attr_reader :handler, :level

      def initialize(handler, level)
        @handler = handler
        @level = level
        @mutex = Mutex.new
        @condition = ConditionVariable.new
        @done = false
        @outcome = nil
      end

      def set(outcome)
        @mutex.synchronize do
          @outcome = outcome
          @done = true
          @condition.broadcast
        end
      end

      # Returns nil when the worker has not finished within `timeout`; the worker
      # keeps going and stays owned.
      def wait(timeout)
        deadline = Connections::DiagnosticHelpers.clock_time + timeout
        @mutex.synchronize do
          until @done
            remaining = deadline - Connections::DiagnosticHelpers.clock_time
            return nil if remaining <= 0

            @condition.wait(@mutex, remaining)
          end
          @outcome
        end
      end
    end

    # One long-lived thread per backend, idle-blocked on a queue. One job at a time:
    # a request arriving while the worker is occupied is answered :busy rather than
    # starting another thread. Threads are never killed - killing one mid-operation
    # can corrupt a database connection.
    class Worker
      STOP = :__console_kit_stop__

      def initialize(key)
        @key = key
        @queue = Queue.new
        @mutex = Mutex.new
        @busy = false
        @stopping = false
        @failed = false
        @thread = nil
      end

      # The job's outcome, or :busy / :timeout. Never raises.
      def call(job, timeout)
        return :busy unless claim

        ensure_thread
        @queue << job
        job.wait(timeout) || :timeout
      end

      def alive? = @thread&.alive? || false

      def stop
        @mutex.synchronize { @stopping = true }
        @queue << STOP
      end

      # Thread#join re-raises the failure the thread died on, and that failure was
      # already published to its caller as a row - do not deliver it twice.
      def join(timeout)
        return if @failed

        @thread&.join(timeout)
      end

      private

      def claim
        @mutex.synchronize do
          return false if @busy || @stopping

          @busy = true
        end
      end

      def release(error = nil)
        @mutex.synchronize do
          @busy = false
          @failed = true if error
        end
      end

      # A replacement thread is not the one that died, so the note telling #join to
      # leave it alone is cleared with it.
      def ensure_thread
        @mutex.synchronize do
          next if @thread&.alive?

          @failed = false
          @thread = start_thread
        end
      end

      def start_thread
        thread = Thread.new { work }
        thread.report_on_exception = false
        thread.name = "console_kit-diagnostics-#{@key}"
        thread
      end

      def work
        loop do
          job = @queue.pop
          break if job == STOP

          perform(job)
        end
      end

      # Released before publishing, so a caller that gets its result can ask again
      # at once. `$ERROR_INFO` is the exception this method is unwinding on, and
      # publishing it stops a worker that blew up reading as one that was merely slow.
      def perform(job)
        outcome = Runner.execute(job.handler, job.level)
      ensure
        release($ERROR_INFO)
        job.set(outcome || $ERROR_INFO)
      end
    end

    # Bounded, leak-free execution of one handler's diagnostics.
    module Runner
      class << self
        def call(handler, timeout: DEFAULT_TIMEOUT, level: :basic)
          Diagnostics.validate_level!(level)
          resolve(handler, dispatch(handler, timeout, level), timeout)
        end

        # Never raises: a worker thread must not blow up on its caller's behalf.
        def execute(handler, level)
          Instrumentation.instrument(EVENT, backend: handler.backend_key, level: level) do
            handler.diagnostics(level: level)
          end
        rescue StandardError, ScriptError => e
          e
        end

        def live_thread_count
          mutex.synchronize do
            retired.select!(&:alive?)
            (workers.values + retired).count(&:alive?)
          end
        end

        # A stuck worker is asked to stop, never killed, so a non-zero answer means
        # a backend has not returned yet.
        def shutdown!(timeout: DEFAULT_TIMEOUT)
          stopping = mutex.synchronize { workers.values.tap { workers.clear } }
          stopping.each(&:stop)
          stopping.each { |worker| worker.join(timeout) }
          mutex.synchronize { retired.concat(stopping.select(&:alive?)) }
          live_thread_count
        end

        private

        def dispatch(handler, timeout, level)
          return execute(handler, level) if level == :basic

          worker_for(handler.backend_key).call(Job.new(handler, level), timeout)
        end

        def resolve(handler, outcome, timeout)
          case outcome
          when Hash then outcome
          when :busy then busy_row(handler)
          when :timeout then timeout_row(handler, timeout)
          else failed_row(handler, outcome)
          end
        end

        def busy_row(handler)
          Instrumentation.increment(TIMEOUT_COUNTER)
          Connections::DiagnosticHelpers.busy_diagnostics(handler.display_name)
        end

        def timeout_row(handler, timeout)
          Instrumentation.increment(TIMEOUT_COUNTER)
          Connections::DiagnosticHelpers.timeout_diagnostics(handler.display_name, timeout)
        end

        def failed_row(handler, error)
          raise error if Diagnostics.programming_error?(error)

          Connections::DiagnosticHelpers.error_diagnostics(handler.display_name, error)
        end

        def worker_for(key)
          mutex.synchronize { workers[key] ||= Worker.new(key) }
        end

        def workers = @workers ||= {}
        def retired = @retired ||= []
        def mutex = @mutex ||= Mutex.new
      end
    end
  end
end
