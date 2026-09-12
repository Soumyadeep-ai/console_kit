# frozen_string_literal: true

require 'English'
require_relative 'errors'
require_relative 'tenant_state'
require_relative 'instrumentation'
require_relative 'connections/diagnostic_helpers'

module ConsoleKit
  # On-demand connection diagnostics.
  #
  # Diagnostics are decoupled from tenant switching: TenantSwitch never asks a
  # handler for diagnostics, and `config.show_dashboard` stays the only thing
  # that renders a dashboard when a tenant is applied.
  #
  # Levels
  #   :basic  resolved identity read out of memory. No network call, so it
  #           cannot block: it runs inline on the calling thread, with no
  #           worker and no timeout machinery at all.
  #   :full   may ping, read versions or health-check. Bounded by Runner.
  module Diagnostics
    LEVELS = %i[basic full].freeze
    DEFAULT_TIMEOUT = 2
    # Long enough that repeatedly typing `dashboard` cannot hammer a backend,
    # short enough that an operator who just restarted one sees it recover on
    # the next look. Deliberately equal to DEFAULT_TIMEOUT, so a cached row is
    # never older than the window a fresh check was allowed to take anyway.
    CACHE_TTL_SECONDS = 2.0
    EVENT = 'console_kit.diagnostics'
    TIMEOUT_COUNTER = 'console_kit.diagnostics_timeout'
    # A bug in ConsoleKit itself must never be laundered into an :error row that
    # hides it. A dependency being unreachable is a legitimate :error row.

    class << self
      # Diagnostic rows for every available handler. :full rows are memoised for
      # CACHE_TTL_SECONDS; :basic rows are read live on every call.
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

    # Short-lived, per-thread memo of :full diagnostic rows.
    #
    # Correctness before speed. An entry is reused only while all three of these
    # still hold:
    #
    #   * its TTL has not elapsed;
    #   * this thread is still on the very TenantState object that produced it -
    #     TenantSwitch commits a brand new TenantState on every switch, so a
    #     switch invalidates every row immediately, TTL or not;
    #   * the backend still reports the identity it reported when the row was
    #     written.
    #
    # The last one is what a tenant key cannot do on its own: Elasticsearch and
    # Redis are PROCESS-global, so a foreign thread can move the prefix or the
    # DB without touching this thread's TenantState, and a row keyed on tenant
    # alone would go on reporting a backend the process has already left. The
    # identity is read out of memory (it is exactly what a :basic row reports),
    # so checking it costs no round trip and the cache still does its job:
    # sparing the backends a hammering when nothing has moved.
    #
    # The store is a thread-local, so one thread's tenant can never leak into
    # another thread's dashboard. Only :full is cached; a :basic row is a local
    # read already, so caching it would buy nothing.
    module Cache
      STORE_KEY = :console_kit_diagnostics_cache
      CACHED_LEVEL = :full
      # A backend that just failed is re-asked on the next call. Holding a
      # failure for the full TTL would hide a backend that has since recovered,
      # and re-asking is cheap: while a timed-out check is still running the
      # runner answers :busy immediately instead of starting another one.
      UNCACHEABLE = %i[error timeout].freeze
      # Only :full is ever cached, so a key is really (tenant, backend). Four
      # backends today, and a console operator rarely keeps more than a handful
      # of tenants "warm" in one session - 32 gives comfortable headroom (8
      # tenants x 4 backends) while keeping a long-lived console from
      # accumulating one entry per distinct tenant ever visited.
      CAPACITY = 32

      class << self
        def fetch_row(handler, level)
          return yield unless level == CACHED_LEVEL

          key = [StateStore.tenant_key, level, handler.backend_key]
          identity = identity_of(handler)
          read(key, identity) || write(key, identity, yield)
        end

        def clear!
          Thread.current[STORE_KEY] = nil
        end

        private

        def store = Thread.current[STORE_KEY] ||= {}

        # A stale hit is evicted on the spot rather than merely ignored, so an
        # entry nobody rereads still cannot occupy a capacity slot forever.
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

        # The backend's own observed identity: the prefix Elasticsearch will
        # index with, the DB the Redis client is on. Read out of memory, never
        # over the wire, and never from this thread's tenant state - that is the
        # point of it.
        def identity_of(handler)
          handler.diagnostic_identity
        rescue StandardError => e
          raise e if Diagnostics.programming_error?(e)

          # Equal to nothing, including itself on the next read: an identity
          # ConsoleKit could not read is not evidence that a row is still true.
          Object.new
        end

        # Ruby Hashes preserve insertion order, so deleting and reinserting a
        # key moves it to the end. That makes `each_key.first` the
        # least-recently-used key, with no extra bookkeeping needed.
        def touch(key, entry)
          store.delete(key)
          store[key] = entry
        end

        # Nothing that already failed freshness will ever pass it again (TTL only
        # moves forward, a TenantState identity never changes back), so a stale
        # entry is dead weight - dropping it here means it stops costing a
        # capacity slot the moment it goes stale, not merely when eviction
        # eventually reaches it.
        def purge_expired!
          store.delete_if { |_, entry| !fresh?(entry) }
        end

        def evict_to_capacity!
          store.delete(store.each_key.first) while store.size > CAPACITY
        end

        def fresh?(entry) = entry[:expires_at] > now && entry[:state].equal?(state)

        # Freshness plus "the backend has not moved underneath the row".
        def current?(entry, identity) = fresh?(entry) && entry[:identity] == identity

        # The raw slot, not StateStore.current: `current` fabricates a fresh
        # TenantState.empty whenever nothing is set, which would make every
        # identity comparison a miss for a console with no tenant selected.
        def state = Thread.current[StateStore::STATE_KEY]
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

      # Blocks for at most `timeout` seconds. Returns nil when the worker has
      # not finished by then; the worker keeps going and stays owned.
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

    # One long-lived thread per backend, idle-blocked on a queue.
    #
    # A worker runs exactly one job at a time. A request that arrives while the
    # worker is still occupied - which is what a previous timeout leaves behind -
    # is answered :busy instead of starting another thread, so ConsoleKit can
    # never hold more diagnostic threads than it has backends. Threads are never
    # killed: 1.3.0 removed Thread.kill because killing a thread mid-operation
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

      # A worker unwinding on a failure the runner could not rescue has already
      # published that failure to its own caller as a row. Thread#join re-raises
      # it, so joining that thread would deliver the same failure a second time,
      # into an unrelated shutdown.
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

      # `error` is the failure this worker is about to unwind on, recorded so
      # #join knows this thread's death was already reported.
      def release(error = nil)
        @mutex.synchronize do
          @busy = false
          @failed = true if error
        end
      end

      # A replacement thread is not the one that died, so the note telling #join
      # to leave it alone is cleared with it.
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

      # Releases the worker before publishing, so a caller that gets its result
      # can immediately ask again without being told the worker is busy.
      #
      # `$ERROR_INFO` is the exception this method is unwinding on - the one
      # way to see a failure that is neither a StandardError nor a ScriptError
      # without rescuing Exception itself. Publishing it matters: an outcome of
      # nil reads to the caller as "did not finish in time", so a worker that
      # blew up was reported as a backend that was merely slow.
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

        # Runs the handler and returns its row, or the exception it raised.
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

        # Retires every worker and reports how many threads are still alive. A
        # worker stuck in a hung diagnostic is asked to stop, never killed, so a
        # non-zero answer means a backend has not returned yet.
        def shutdown!(timeout: DEFAULT_TIMEOUT)
          stopping = mutex.synchronize { workers.values.tap { workers.clear } }
          stopping.each(&:stop)
          stopping.each { |worker| worker.join(timeout) }
          mutex.synchronize { retired.concat(stopping.select(&:alive?)) }
          live_thread_count
        end

        private

        # :basic reads memory only, so it cannot block and needs no worker.
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
