# frozen_string_literal: true

require 'spec_helper'

# Minimal diagnostics-capable handler used across this file. Deliberately NOT a
# BaseConnectionHandler subclass, so it can never leak into
# BaseConnectionHandler.registry (which walks .descendants).
class DiagnosticsSpecHandler
  attr_reader :backend_key, :display_name

  def initialize(backend_key, &block)
    @backend_key = backend_key
    @display_name = backend_key.to_s
    @block = block
  end

  def diagnostics(level:) = @block.call(level)
end

RSpec.describe ConsoleKit::Diagnostics do
  before { described_class.clear_cache! }

  after do
    described_class::Runner.shutdown!
    described_class.clear_cache!
  end

  def blocking_handler(key, release)
    DiagnosticsSpecHandler.new(key) do
      release.pop
      connected_row(key.to_s)
    end
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
  # without relying on instance variables.
  def counting_fetch(backend_key, counter, row_proc = -> { connected_row })
    described_class::Cache.fetch_row(backend_key, :basic) do
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

  describe 'level dispatch' do
    it 'runs the basic level inline without spawning a worker thread' do
      baseline = described_class::Runner.live_thread_count
      described_class::Runner.call(fast_handler(:basic_dispatch), level: :basic)
      expect(described_class::Runner.live_thread_count).to eq(baseline)
    end

    it 'may dispatch the full level through a worker thread' do
      baseline = described_class::Runner.live_thread_count
      described_class::Runner.call(fast_handler(:full_dispatch), level: :full)
      expect(described_class::Runner.live_thread_count).to eq(baseline + 1)
    end
  end

  describe 'the bounded, leak-free runner' do
    describe 'when many calls target handlers that block past their timeout' do
      let(:releases) { Array.new(3) { Queue.new } }
      let(:handlers) { releases.each_with_index.map { |queue, i| blocking_handler(:"cap_backend_#{i}", queue) } }

      after { releases.each { |queue| queue.push(:release) } }

      it 'never holds more live threads than the number of distinct backends called' do
        baseline = described_class::Runner.live_thread_count
        50.times { handlers.each { |handler| described_class::Runner.call(handler, timeout: 0.01, level: :full) } }
        expect(described_class::Runner.live_thread_count).to eq(baseline + handlers.size)
      end
    end

    describe 'a request for a backend whose worker is still busy with a previous timed-out call' do
      let(:release) { Queue.new }
      let(:handler) { blocking_handler(:busy_backend, release) }

      before { described_class::Runner.call(handler, timeout: 0.01, level: :full) }

      after { release.push(:release) }

      it 'does not spawn another thread' do
        baseline = described_class::Runner.live_thread_count
        described_class::Runner.call(handler, timeout: 0.01, level: :full)
        expect(described_class::Runner.live_thread_count).to eq(baseline)
      end

      it 'answers with a :timeout status' do
        row = described_class::Runner.call(handler, timeout: 0.01, level: :full)
        expect(row[:status]).to eq(:timeout)
      end

      it 'explains that a previous check is still running' do
        row = described_class::Runner.call(handler, timeout: 0.01, level: :full)
        expect(row[:details][:error]).to eq(ConsoleKit::Connections::DiagnosticHelpers::BUSY_REASON)
      end

      it 'answers immediately rather than waiting out the timeout again' do
        start = ConsoleKit::Connections::DiagnosticHelpers.clock_time
        described_class::Runner.call(handler, timeout: 5, level: :full)
        elapsed = ConsoleKit::Connections::DiagnosticHelpers.clock_time - start
        expect(elapsed).to be < 1
      end
    end

    describe 'a straggler that finishes after the caller has already timed out' do
      let(:release) { Queue.new }
      let(:handler) { blocking_handler(:straggler_backend, release) }
      let(:worker) { described_class::Worker.new(:straggler_backend) }

      # Runs the whole scenario once (memoized) so every `it` below observes
      # the same sequence of events without duplicating the choreography.
      let(:scenario) do
        first_job = described_class::Job.new(handler, :full)
        first_outcome = worker.call(first_job, 0.01)
        release.push(:release_first)
        straggler_outcome = first_job.wait(5)
        thread_before_second_job = worker.instance_variable_get(:@thread)
        release.push(:release_second)
        second_outcome = worker.call(described_class::Job.new(handler, :full), 5)
        {
          first_outcome: first_outcome, straggler_outcome: straggler_outcome, second_outcome: second_outcome,
          thread_before_second_job: thread_before_second_job,
          thread_after_second_job: worker.instance_variable_get(:@thread)
        }
      end

      after do
        release.push(:cleanup)
        worker.stop
        worker.join(1)
      end

      it 'reports :timeout to the caller while the straggler is still running' do
        expect(scenario[:first_outcome]).to eq(:timeout)
      end

      it 'eventually resolves the straggler to the handler row' do
        expect(scenario[:straggler_outcome]).to be_a(Hash)
      end

      it 'accepts the next job on the same worker instead of answering :busy' do
        expect(scenario[:second_outcome]).to be_a(Hash)
      end

      it 'never spawns a second thread for the reused worker' do
        expect(scenario[:thread_after_second_job]).to equal(scenario[:thread_before_second_job])
      end
    end

    describe 'a thread blocked past its timeout' do
      let(:release) { Queue.new }
      let(:handler) { blocking_handler(:not_killed_backend, release) }
      let(:worker) { described_class::Worker.new(:not_killed_backend) }

      before { worker.call(described_class::Job.new(handler, :full), 0.01) }

      after do
        release.push(:release)
        worker.stop
        worker.join(1)
      end

      it 'keeps the blocked thread alive rather than killing it' do
        expect(worker.alive?).to be(true)
      end
    end

    describe 'a handler that blocks past its timeout' do
      let(:release) { Queue.new }
      let(:handler) { blocking_handler(:timeout_status_backend, release) }

      after { release.push(:release) }

      it 'reports :timeout status' do
        row = described_class::Runner.call(handler, timeout: 0.01, level: :full)
        expect(row[:status]).to eq(:timeout)
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
  end

  describe 'thread isolation of the cache' do
    def fetch_isolated_row(tenant_key, name)
      ConsoleKit::StateStore.current = ConsoleKit::TenantState.new(tenant_key: tenant_key)
      described_class::Cache.fetch_row(:thread_iso_backend, :basic) { connected_row(name) }
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

  describe 'instrumentation' do
    it 'emits the diagnostics event with the backend and level in the payload' do
      events = []
      ConsoleKit::Instrumentation.subscribe { |name, _duration, payload| events << [name, payload] }
      described_class::Runner.call(fast_handler(:instrumented_backend), level: :full)
      expect(events).to include([described_class::EVENT, hash_including(backend: :instrumented_backend, level: :full)])
    end

    describe 'a timed-out check' do
      let(:release) { Queue.new }
      let(:handler) { blocking_handler(:instrumented_timeout_backend, release) }

      after { release.push(:release) }

      it 'increments the timeout counter' do
        described_class::Runner.call(handler, timeout: 0.01, level: :full)
        expect(ConsoleKit::Instrumentation.counters[described_class::TIMEOUT_COUNTER]).to eq(1)
      end
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
