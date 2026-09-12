# frozen_string_literal: true

require 'spec_helper'

# Minimal diagnostics-capable handler used across this file. Deliberately NOT a
# BaseConnectionHandler subclass, so it can never leak into
# BaseConnectionHandler.registry (which walks .descendants).
class DiagnosticsSpecHandler
  attr_reader :backend_key, :display_name

  def initialize(backend_key, identity: nil, &block)
    @backend_key = backend_key
    @display_name = backend_key.to_s
    @identity = identity
    @block = block
  end

  def diagnostics(level:) = @block.call(level)

  # What a cached :full row's freshness is keyed on. A Proc is re-read on every
  # call, so an example can move the backend - or break the read - between two
  # renders.
  def diagnostic_identity = @identity.is_a?(Proc) ? @identity.call : @identity

  def safe_diagnostics(level:, timeout: ConsoleKit::Diagnostics::DEFAULT_TIMEOUT)
    ConsoleKit::Diagnostics::Runner.call(self, timeout: timeout, level: level)
  end
end

RSpec.describe ConsoleKit::Diagnostics do
  before { described_class.clear_cache! }

  after do
    described_class::Runner.shutdown!
    described_class.clear_cache!
  end

  def failing_handler(key, error)
    DiagnosticsSpecHandler.new(key) { raise error }
  end

  def fast_handler(key)
    DiagnosticsSpecHandler.new(key) { connected_row(key.to_s) }
  end

  def connected_row(name = 'x')
    { name: name, status: :connected, latency_ms: nil, details: {} }
  end

  # Fetches through the cache, bumping counter[0] on every real backend call
  # (a cache hit never runs the block), so tests can assert on call counts
  # without relying on instance variables. Only :full is cached, so that is the
  # level every cache example uses unless it is about :basic specifically.
  def counting_fetch(backend_key, counter, row_proc = -> { connected_row }, level: :full)
    described_class::Cache.fetch_row(DiagnosticsSpecHandler.new(backend_key), level) do
      counter[0] += 1
      row_proc.call
    end
  end

  describe '.run' do
    it 'raises ConfigurationError for an unknown level' do
      expect { described_class.run(level: :deep) }.to raise_error(ConsoleKit::ConfigurationError, /:deep/)
    end

    it 'returns the diagnostic row for each available handler' do
      row = connected_row('Dbl')
      handler = double(backend_key: :dbl, safe_diagnostics: row)
      allow(ConsoleKit::Connections::ConnectionManager).to receive(:available_handlers).and_return([handler])
      expect(described_class.run(level: :basic)).to eq([row])
    end
  end

  # A handler reads its backend state from thread-local storage: the SQL shard
  # frame, Mongoid's overrides, the scoped Redis client. A check taken anywhere
  # but the calling thread therefore describes a tenant nobody asked about.
  describe 'where a :full check executes' do
    def thread_probe(key)
      DiagnosticsSpecHandler.new(key) { connected_row(key.to_s).merge(details: { thread: Thread.current }) }
    end

    it 'runs on the calling thread' do
      row = described_class::Runner.call(thread_probe(:thread_probe_backend), level: :full)
      expect(row[:details][:thread]).to equal(Thread.current)
    end
  end

  describe 'a :full check taken while a tenant is applied' do
    include_context 'with a four-backend tenant setup'

    before { ConsoleKit.switch_tenant('acme') }

    def full_details(handler_class)
      described_class::Runner.call(handler_class.new(context_class), level: :full)[:details]
    end

    it 'reports the Mongo database the caller is on' do
      expect(full_details(ConsoleKit::Connections::MongoConnectionHandler)[:database]).to eq('acme_db')
    end
  end

  # The runner used to bound a slow backend on a worker thread, and paid for that
  # bound with a row describing the worker's tenant rather than the caller's. What
  # replaced it is pinned here: the budget is reported, the check still answers,
  # and no thread is held.
  describe 'a check that overruns its budget' do
    let(:handler) { fast_handler(:overrun_backend) }

    it 'still answers with the row the backend gave' do
      row = described_class::Runner.call(handler, timeout: 0, level: :full)
      expect(row[:status]).to eq(:connected)
    end

    it 'counts the overrun under the diagnostics timeout counter' do
      described_class::Runner.call(handler, timeout: 0, level: :full)
      expect(ConsoleKit::Instrumentation.counters[described_class::TIMEOUT_COUNTER]).to eq(1)
    end

    it 'leaves a check that stayed inside its budget uncounted' do
      described_class::Runner.call(handler, timeout: 30, level: :full)
      expect(ConsoleKit::Instrumentation.counters[described_class::TIMEOUT_COUNTER]).to eq(0)
    end
  end

  describe 'the threads a check uses' do
    it 'holds no diagnostics thread of its own' do
      described_class::Runner.call(fast_handler(:threadless_backend), level: :full)
      expect(described_class::Runner.live_thread_count).to eq(0)
    end

    it 'winds down without anything to stop' do
      expect(described_class::Runner.shutdown!).to eq(0)
    end
  end

  describe 'a handler that raises a plain failure' do
    it 'never raises into the caller' do
      handler = failing_handler(:non_raising_backend, StandardError.new('boom'))
      expect { described_class::Runner.call(handler, level: :basic) }.not_to raise_error
    end

    it 'reports :error status' do
      handler = failing_handler(:error_status_backend, StandardError.new('boom'))
      row = described_class::Runner.call(handler, level: :basic)
      expect(row[:status]).to eq(:error)
    end

    it 'carries the failure message in details[:error]' do
      handler = failing_handler(:error_message_backend, StandardError.new('boom'))
      row = described_class::Runner.call(handler, level: :basic)
      expect(row[:details][:error]).to eq('boom')
    end
  end

  # Rescuing this would swallow Interrupt as well, and a check that blocks its
  # caller is exactly the one an operator has to be able to abandon.
  describe 'a failure the runner deliberately does not rescue' do
    let(:handler) { failing_handler(:interrupted_backend, Interrupt.new('ctrl-c')) }

    it 'reaches the caller' do
      expect { described_class::Runner.call(handler, level: :full) }.to raise_error(Interrupt)
    end
  end

  describe 'the short-TTL cache' do
    before { ConsoleKit::StateStore.current = ConsoleKit::TenantState.new(tenant_key: 'acme') }

    it 'does not call the backend again for a second call within the TTL' do
      counter = [0]
      2.times { counting_fetch(:ttl_backend, counter) }
      expect(counter.first).to eq(1)
    end

    context 'when the TTL has elapsed' do
      let(:clock) { [1_000_000.0] }

      before { allow(ConsoleKit::Connections::DiagnosticHelpers).to receive(:clock_time) { clock.first } }

      it 'calls the backend again' do
        counter = [0]
        counting_fetch(:ttl_expiry_backend, counter)
        clock[0] += described_class::CACHE_TTL_SECONDS + 1
        counting_fetch(:ttl_expiry_backend, counter)
        expect(counter.first).to eq(2)
      end
    end

    it 'reissues the backend call immediately after a tenant switch, even within the TTL' do
      counter = [0]
      counting_fetch(:switch_backend, counter)
      ConsoleKit::StateStore.current = ConsoleKit::TenantState.new(tenant_key: 'acme')
      counting_fetch(:switch_backend, counter)
      expect(counter.first).to eq(2)
    end

    it 'does not cache a :timeout row, so a recovered backend is asked again' do
      rows = [{ name: 'x', status: :timeout, latency_ms: nil, details: {} }, connected_row].each
      counter = [0]
      2.times { counting_fetch(:uncacheable_timeout_backend, counter, -> { rows.next }) }
      expect(counter.first).to eq(2)
    end

    it 'does not cache an :error row, so a recovered backend is asked again' do
      rows = [{ name: 'x', status: :error, latency_ms: nil, details: {} }, connected_row].each
      counter = [0]
      2.times { counting_fetch(:uncacheable_error_backend, counter, -> { rows.next }) }
      expect(counter.first).to eq(2)
    end

    it 'empties the cache so the next call reaches the backend again' do
      counter = [0]
      counting_fetch(:clear_backend, counter)
      described_class.clear_cache!
      counting_fetch(:clear_backend, counter)
      expect(counter.first).to eq(2)
    end

    # Freshness can only observe THIS thread's TenantState, so a cached :basic
    # row survives another thread moving a process-global backend. A :basic row
    # is a local read anyway, so it is never cached.
    it 'does not cache a :basic row, because it is read out of memory anyway' do
      counter = [0]
      2.times { counting_fetch(:basic_uncached_backend, counter, level: :basic) }
      expect(counter.first).to eq(2)
    end
  end

  describe 'the bounded LRU cache' do
    before { ConsoleKit::StateStore.current = ConsoleKit::TenantState.new(tenant_key: 'acme') }

    def store_size
      described_class::Cache.send(:store).size
    end

    it 'never grows past its capacity, however many distinct keys are cached' do
      (described_class::Cache::CAPACITY + 10).times { |i| counting_fetch(:"lru_cap_backend#{i}", [0]) }
      expect(store_size).to eq(described_class::Cache::CAPACITY)
    end

    it 'evicts the least-recently-used entry first when capacity is exceeded' do
      described_class::Cache::CAPACITY.times { |i| counting_fetch(:"lru_order_backend#{i}", [0]) }
      counting_fetch(:lru_order_overflow_backend, [0])
      counter = [0]
      counting_fetch(:lru_order_backend0, counter)
      expect(counter.first).to eq(1)
    end

    context 'when an entry is touched before capacity is exceeded' do
      let(:counter) { [0] }

      before do
        described_class::Cache::CAPACITY.times { |i| counting_fetch(:"lru_touch_backend#{i}", [0]) }
        counting_fetch(:lru_touch_backend0, [0]) # promotes backend0 ahead of backend1
        counting_fetch(:lru_touch_overflow_backend, [0]) # evicts the new LRU, backend1
        counting_fetch(:lru_touch_backend0, counter)
      end

      it 'keeps the touched entry over one merely inserted earlier' do
        expect(counter.first).to eq(0)
      end
    end

    context 'when an entry has expired' do
      let(:clock) { [1_000_000.0] }

      before { allow(ConsoleKit::Connections::DiagnosticHelpers).to receive(:clock_time) { clock.first } }

      it 'does not occupy a capacity slot after it expires' do
        counting_fetch(:lru_expired_backend, [0])
        clock[0] += described_class::CACHE_TTL_SECONDS + 1
        (described_class::Cache::CAPACITY - 1).times { |i| counting_fetch(:"lru_expired_filler_#{i}", [0]) }
        expect(store_size).to eq(described_class::Cache::CAPACITY - 1)
      end

      it 'is re-fetched from the backend rather than served stale once expired' do
        counting_fetch(:lru_expired_reread_backend, [0])
        clock[0] += described_class::CACHE_TTL_SECONDS + 1
        counter = [0]
        counting_fetch(:lru_expired_reread_backend, counter)
        expect(counter.first).to eq(1)
      end
    end
  end

  # Elasticsearch and Redis are documented as process-global: another thread
  # moving one changes nothing this thread's TenantState can show, so a cached
  # row would keep reporting a tenant that has already been switched away.
  describe 'a process-global backend moved by another thread' do
    let(:live_prefix) { ['acme_es'] }
    let(:handler) do
      DiagnosticsSpecHandler.new(:process_global_backend) do
        { name: 'Elasticsearch', status: :connected, latency_ms: nil, details: { prefix: live_prefix.first } }
      end
    end

    before do
      ConsoleKit::StateStore.current = ConsoleKit::TenantState.new(tenant_key: 'acme')
      allow(ConsoleKit::Connections::ConnectionManager).to receive(:available_handlers).and_return([handler])
      described_class.run(level: :basic)
      Thread.new { live_prefix[0] = 'someone_elses_tenant' }.join
    end

    it 'reports the prefix the backend is actually on' do
      expect(described_class.run(level: :basic).first[:details][:prefix]).to eq('someone_elses_tenant')
    end
  end

  # The same defect at the level that IS cached. Freshness keyed on this
  # thread's TenantState cannot see a foreign thread move a process-global
  # attribute, so the cached :full row went on reporting a prefix the process
  # had already left - which is exactly why :basic stopped being cached.
  describe 'a cached :full row whose process-global backend was moved by another thread' do
    let(:handler) { ConsoleKit::Connections::ElasticsearchConnectionHandler.new(Class.new) }

    before do
      ConsoleKit::StateStore.current = ConsoleKit::TenantState.new(tenant_key: 'acme')
      allow(ConsoleKit::Connections::ConnectionManager).to receive(:available_handlers).and_return([handler])
      Elasticsearch::Model.index_name_prefix = 'acme_es'
      described_class.run(level: :full)
      Thread.new { Elasticsearch::Model.index_name_prefix = 'globex_es' }.join
    end

    it 'reports the prefix the backend is actually on' do
      expect(described_class.run(level: :full).first[:details][:prefix]).to eq('globex_es')
    end
  end

  # Freshness reads identity out of memory, so re-reading it on every render
  # must not turn into re-asking the backend: sparing the backends is the whole
  # reason this cache exists.
  describe 'a cached :full row whose backend has not moved' do
    let(:handler) { ConsoleKit::Connections::ElasticsearchConnectionHandler.new(Class.new) }

    before do
      ConsoleKit::StateStore.current = ConsoleKit::TenantState.new(tenant_key: 'acme')
      allow(ConsoleKit::Connections::ConnectionManager).to receive(:available_handlers).and_return([handler])
      Elasticsearch::Model.index_name_prefix = 'acme_es'
      2.times { described_class.run(level: :full) }
    end

    it 'pings the cluster once rather than on every render' do
      expect(Elasticsearch::Model.client.ping_calls).to eq(1)
    end
  end

  # An identity ConsoleKit cannot read is not evidence that the row is still
  # true, and the dashboard must not blow up over it either.
  describe 'a backend whose identity cannot be read' do
    let(:counter) { [0] }

    def unreadable_fetch
      handler = DiagnosticsSpecHandler.new(:unreadable_identity_backend, identity: -> { raise 'cannot read' })
      described_class::Cache.fetch_row(handler, :full) do
        counter[0] += 1
        connected_row
      end
    end

    before { ConsoleKit::StateStore.current = ConsoleKit::TenantState.new(tenant_key: 'acme') }

    it 'does not raise into the caller' do
      expect { unreadable_fetch }.not_to raise_error
    end

    it 'refetches rather than serving a row it cannot prove is current' do
      2.times { unreadable_fetch }
      expect(counter.first).to eq(2)
    end

    it 'still surfaces a programming error in the identity read' do
      handler = DiagnosticsSpecHandler.new(:buggy_identity_backend, identity: -> { raise NoMethodError })
      expect { described_class::Cache.fetch_row(handler, :full) { connected_row } }.to raise_error(NoMethodError)
    end
  end

  describe 'thread isolation of the cache' do
    def fetch_isolated_row(tenant_key, name)
      ConsoleKit::StateStore.current = ConsoleKit::TenantState.new(tenant_key: tenant_key)
      handler = DiagnosticsSpecHandler.new(:thread_iso_backend)
      described_class::Cache.fetch_row(handler, :full) { connected_row(name) }
    end

    it "does not use another thread's cached row for this thread's tenant" do
      main_row = fetch_isolated_row('acme', 'acme-row')
      Thread.new { fetch_isolated_row('globex', 'globex-row') }.join
      expect(main_row[:name]).to eq('acme-row')
    end

    it "keeps the other thread's cached row scoped to its own tenant" do
      fetch_isolated_row('acme', 'acme-row')
      other_row = nil
      Thread.new { other_row = fetch_isolated_row('globex', 'globex-row') }.join
      expect(other_row[:name]).to eq('globex-row')
    end
  end

  # Freshness is keyed on the thread's TenantState, so the cache has to be read
  # and written in that same scope. A fiber reading a state of its own sees the
  # empty one, which matches every other empty one - and a row cached under the
  # tenant the thread has since left would go on being served.
  describe 'the cache inside a fiber' do
    let(:counter) { [0] }
    let(:fiber) { Fiber.new { loop { Fiber.yield(counting_fetch(:fiber_cache_backend, counter)) } } }

    before { ConsoleKit::StateStore.current = ConsoleKit::TenantState.new(tenant_key: 'acme') }

    it 'asks the backend again once its thread has switched tenant' do
      fiber.resume
      ConsoleKit::StateStore.current = ConsoleKit::TenantState.new(tenant_key: 'globex')
      fiber.resume
      expect(counter.first).to eq(2)
    end

    it 'reuses the row its thread already cached' do
      counting_fetch(:fiber_cache_backend, counter)
      fiber.resume
      expect(counter.first).to eq(1)
    end
  end

  describe 'instrumentation' do
    it 'emits the diagnostics event with the backend and level in the payload' do
      events = []
      ConsoleKit::Instrumentation.subscribe { |name, _duration, payload| events << [name, payload] }
      described_class::Runner.call(fast_handler(:instrumented_backend), level: :full)
      expect(events).to include([described_class::EVENT, hash_including(backend: :instrumented_backend, level: :full)])
    end
  end

  describe 'credential redaction in error rows' do
    it 'redacts a connection URL embedded in the error message' do
      message = 'failed: postgres://admin:s3cr3t@db.internal:5432/prod'
      handler = failing_handler(:cred_url_backend, StandardError.new(message))
      row = described_class::Runner.call(handler, level: :basic)
      expect(row[:details][:error]).not_to include('s3cr3t')
    end

    it 'redacts a password= assignment embedded in the error message' do
      handler = failing_handler(:cred_kv_backend, StandardError.new('auth failed, password=hunter2'))
      row = described_class::Runner.call(handler, level: :basic)
      expect(row[:details][:error]).not_to include('hunter2')
    end
  end

  describe 'no broad-rescue masking of programming errors' do
    it 'propagates a genuine programming error instead of converting it to an :error row' do
      handler = failing_handler(:programming_bug_backend, NoMethodError.new("undefined method 'foo' for nil"))
      expect { described_class::Runner.call(handler, level: :basic) }.to raise_error(NoMethodError)
    end

    describe '.programming_error?' do
      it 'treats NoMethodError as a programming error' do
        expect(described_class.programming_error?(NoMethodError.new)).to be(true)
      end

      it 'does not treat a plain StandardError as a programming error' do
        expect(described_class.programming_error?(StandardError.new)).to be(false)
      end
    end
  end

  describe 'the dashboard remains callable with no arguments' do
    before do
      allow(ConsoleKit::Connections::ConnectionManager).to receive(:available_handlers).and_return([])
      allow(ConsoleKit::Output).to receive(:print_warning)
    end

    it 'does not raise' do
      expect { ConsoleKit::Connections::Dashboard.display }.not_to raise_error
    end
  end
end
