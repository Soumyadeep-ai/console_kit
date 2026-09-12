# frozen_string_literal: true

require 'spec_helper'

# Dummy context object for connection handler specs
class DummyContext
  attr_reader :tenant_elasticsearch_prefix

  def initialize(tenant_elasticsearch_prefix: nil)
    @tenant_elasticsearch_prefix = tenant_elasticsearch_prefix
  end
end

RSpec.describe ConsoleKit::Connections::ElasticsearchConnectionHandler do
  let(:context) { instance_double(DummyContext, tenant_elasticsearch_prefix: 'acme') }
  let(:handler) { described_class.new(context) }
  let(:registry) { ConsoleKit::Connections::ElasticsearchPrefixRegistry }

  before do
    allow(ConsoleKit::Output).to receive(:print_info)
    allow(ConsoleKit::Output).to receive(:print_warning)
    ElasticsearchMocks.reset!
  end

  after do
    registry.record(nil)
    Thread.current[ConsoleKit::Connections::ElasticsearchPrefixRegistry::REPORTED_KEY] = nil
    ElasticsearchMocks.reset!
  end

  describe '#available?' do
    it 'returns true when Elasticsearch is defined' do
      expect(handler).to be_available
    end

    it 'returns false when Elasticsearch is not defined' do
      hide_const('Elasticsearch')
      expect(handler).not_to be_available
    end
  end

  describe 'isolation model' do
    it 'declares the prefix as process global' do
      expect(handler.isolation_model).to eq(:process_global)
    end

    it 'does not claim per-thread isolation' do
      expect(handler).not_to be_thread_isolated
    end
  end

  describe '#prepare' do
    context 'with a blank target' do
      it 'accepts nil' do
        expect { handler.prepare(nil) }.not_to raise_error
      end

      it 'accepts an empty string' do
        expect { handler.prepare('') }.not_to raise_error
      end
    end

    context 'with an illegal prefix' do
      it 'rejects an uppercase prefix' do
        expect { handler.prepare('Acme') }.to raise_error(ConsoleKit::ConfigurationError)
      end

      it 'rejects a prefix containing whitespace' do
        expect { handler.prepare('acme idx') }.to raise_error(ConsoleKit::ConfigurationError)
      end

      it 'rejects a prefix with a leading underscore' do
        expect { handler.prepare('_acme') }.to raise_error(ConsoleKit::ConfigurationError)
      end

      it 'rejects a prefix with a leading hyphen' do
        expect { handler.prepare('-acme') }.to raise_error(ConsoleKit::ConfigurationError)
      end

      it 'rejects a prefix containing an illegal character' do
        expect { handler.prepare('acme/idx') }.to raise_error(ConsoleKit::ConfigurationError)
      end

      it 'names the offending value in the message' do
        expect { handler.prepare('acme#idx') }.to raise_error(/"acme#idx"/)
      end
    end

    # A prefix is a name, not an arbitrary object. Coercing the value with
    # `#to_s` before checking it let an Integer through as "5" and an Array as
    # "[:acme]" - both legal index-name prefixes once stringified, and both
    # written straight to `index_name_prefix`.
    context 'with a target that is not a name at all' do
      it 'rejects an Integer rather than coercing it' do
        expect { handler.prepare(5) }.to raise_error(ConsoleKit::ConfigurationError)
      end

      it 'rejects an Array rather than coercing it' do
        expect { handler.prepare([:acme]) }.to raise_error(ConsoleKit::ConfigurationError)
      end

      it 'rejects a Hash rather than coercing it' do
        expect { handler.prepare({ prefix: 'acme' }) }.to raise_error(ConsoleKit::ConfigurationError)
      end

      # Configuration#validate! reports this reason without ever calling
      # #prepare, so the rule has to be readable there too.
      it 'says what it expected' do
        expect(described_class.target_error(5)).to eq('expected a String or Symbol')
      end

      it 'still accepts a Symbol' do
        expect(described_class.target_error(:acme)).to be_nil
      end
    end

    context 'when the prefix is valid' do
      before do
        allow(Elasticsearch::Model).to receive(:index_name_prefix=)
        handler.prepare('acme')
      end

      it 'does not set the index name prefix' do
        expect(Elasticsearch::Model).not_to have_received(:index_name_prefix=)
      end

      it 'does not record anything in the registry' do
        expect(registry.current).to be_nil
      end
    end

    context 'when Elasticsearch::Model cannot set a prefix' do
      before { stub_const('Elasticsearch::Model', Elasticsearch::ModelWithoutPrefix) }

      it 'raises UnsupportedBackendError for a requested prefix' do
        expect { handler.prepare('acme') }.to raise_error(ConsoleKit::UnsupportedBackendError)
      end

      it 'accepts a nil target' do
        expect { handler.prepare(nil) }.not_to raise_error
      end
    end

    # A prefix that can be written but not read back cannot be snapshotted:
    # #snapshot records nil, #verify! falls back to ConsoleKit's own registry
    # instead of reading Elasticsearch, and a rollback writes nil over the
    # previous tenant's process-wide prefix while the switch reports itself
    # verified. Both a tenant prefix and a reset write, so both are refused.
    context 'when Elasticsearch::Model can set a prefix but cannot read one back' do
      before { stub_const('Elasticsearch::Model', Elasticsearch::ModelWithWriteOnlyPrefix) }

      it 'refuses a tenant prefix' do
        expect { handler.prepare('acme') }.to raise_error(ConsoleKit::UnsupportedBackendError)
      end

      it 'names the backend in the refusal' do
        expect { handler.prepare('acme') }.to raise_error(/Elasticsearch/)
      end

      it 'refuses a reset, which would also write over an unknown prefix' do
        expect { handler.prepare(nil) }.to raise_error(ConsoleKit::UnsupportedBackendError)
      end

      it 'records nothing in the registry when it refuses' do
        refuse_prefix
        expect(registry.current).to be_nil
      end

      def refuse_prefix
        handler.prepare('acme')
      rescue ConsoleKit::UnsupportedBackendError
        nil
      end
    end
  end

  describe '#connect!' do
    context 'with a tenant prefix' do
      before { handler.connect!('acme') }

      it 'sets the process-wide index name prefix' do
        expect(Elasticsearch::Model.index_name_prefix).to eq('acme')
      end

      it 'records the prefix in the registry' do
        expect(registry.current).to eq('acme')
      end

      it 'mirrors the prefix onto the legacy thread-local key' do
        expect(Thread.current[:console_kit_elasticsearch_prefix]).to eq('acme')
      end

      it 'reports the effective prefix' do
        expect(handler.effective_prefix).to eq('acme')
      end
    end

    context 'when resetting to no prefix' do
      before do
        handler.connect!('acme')
        handler.connect!(nil)
      end

      it 'clears the process-wide index name prefix' do
        expect(Elasticsearch::Model.index_name_prefix).to be_nil
      end

      it 'clears the registry entry' do
        expect(registry.current).to be_nil
      end

      it 'clears the legacy thread-local key' do
        expect(Thread.current[:console_kit_elasticsearch_prefix]).to be_nil
      end
    end

    context 'with a blank prefix' do
      before { handler.connect!('') }

      it 'treats blank as no prefix' do
        expect(Elasticsearch::Model.index_name_prefix).to be_nil
      end
    end

    context 'when Elasticsearch::Model cannot set a prefix' do
      before { stub_const('Elasticsearch::Model', Elasticsearch::ModelWithoutPrefix) }

      it 'raises instead of silently succeeding' do
        expect { handler.connect!('acme') }.to raise_error(ConsoleKit::UnsupportedBackendError)
      end
    end

    describe 'repeated switching' do
      before do
        handler.connect!('acme')
        handler.connect!('globex')
        handler.connect!('acme')
      end

      it 'ends on the last applied prefix' do
        expect(handler.effective_prefix).to eq('acme')
      end

      it 'verifies against the last applied prefix' do
        expect { handler.verify!('acme') }.not_to raise_error
      end
    end
  end

  describe '#snapshot' do
    context 'when a prefix is already applied' do
      before { handler.connect!('previous') }

      it 'captures the global prefix' do
        expect(handler.snapshot[:global]).to eq('previous')
      end

      it 'captures the ConsoleKit per-thread prefix' do
        expect(handler.snapshot[:thread]).to eq('previous')
      end

      it 'does not mutate the global prefix' do
        handler.snapshot
        expect(Elasticsearch::Model.index_name_prefix).to eq('previous')
      end

      it 'does not mutate the registry' do
        handler.snapshot
        expect(registry.current).to eq('previous')
      end
    end

    context 'when no prefix is applied' do
      it 'captures a nil global prefix' do
        expect(handler.snapshot[:global]).to be_nil
      end

      it 'captures a nil per-thread prefix' do
        expect(handler.snapshot[:thread]).to be_nil
      end
    end
  end

  describe '#restore' do
    context 'when there was a previous prefix' do
      let(:snapshot) { handler.snapshot }

      before do
        handler.connect!('previous')
        snapshot
        handler.connect!('other')
        handler.restore(snapshot)
      end

      it 'puts the global prefix back' do
        expect(Elasticsearch::Model.index_name_prefix).to eq('previous')
      end

      it 'puts the registry entry back' do
        expect(registry.current).to eq('previous')
      end
    end

    context 'when there was no previous prefix' do
      let(:snapshot) { handler.snapshot }

      before do
        snapshot
        handler.connect!('acme')
        handler.restore(snapshot)
      end

      it 'restores the global prefix to nil' do
        expect(Elasticsearch::Model.index_name_prefix).to be_nil
      end

      it 'restores the registry entry to nil' do
        expect(registry.current).to be_nil
      end

      it 'restores the legacy thread-local key to nil' do
        expect(Thread.current[:console_kit_elasticsearch_prefix]).to be_nil
      end
    end
  end

  describe '#verify!' do
    it 'passes when the effective prefix matches the target' do
      handler.connect!('acme')
      expect { handler.verify!('acme') }.not_to raise_error
    end

    it 'passes when no prefix is expected and none is set' do
      expect(handler.verify!(nil)).to be(true)
    end

    context 'when a foreign writer changed the effective prefix' do
      let(:error) do
        handler.verify!('acme')
      rescue ConsoleKit::ConnectionVerificationError => e
        e
      end

      before do
        handler.connect!('acme')
        Elasticsearch::Model.index_name_prefix = 'intruder'
      end

      it 'raises ConnectionVerificationError' do
        expect { handler.verify!('acme') }.to raise_error(ConsoleKit::ConnectionVerificationError)
      end

      it 'populates the expected prefix on the error' do
        expect(error.expected).to eq('acme')
      end

      it 'populates the actual prefix on the error' do
        expect(error.actual).to eq('intruder')
      end
    end

    context 'when a prefix lingers but none is expected' do
      before { handler.connect!('acme') }

      it 'raises ConnectionVerificationError' do
        expect { handler.verify!(nil) }.to raise_error(ConsoleKit::ConnectionVerificationError)
      end
    end
  end

  describe 'a failure while applying the prefix' do
    let(:exploding_model) do
      Module.new do
        class << self
          attr_reader :index_name_prefix

          def client = nil

          def index_name_prefix=(_value)
            raise 'es exploded'
          end
        end
      end
    end

    it 'propagates the failure instead of swallowing it' do
      stub_const('Elasticsearch::Model', exploding_model)
      expect { handler.connect!('boom') }.to raise_error('es exploded')
    end

    context 'when the prefix could not be applied' do
      before do
        handler.connect!('previous')
        stub_const('Elasticsearch::Model', exploding_model)
        handler.connect!('boom')
      rescue RuntimeError
        nil
      end

      it 'leaves the previous ConsoleKit prefix recorded so restore can undo it' do
        expect(registry.current).to eq('previous')
      end
    end
  end

  # Pins the documented :process_global behaviour: no isolation, but the
  # disagreement is detected and reported rather than hidden.
  describe 'two threads switching concurrently' do
    let(:gate) { { started: Queue.new, release: Queue.new, observed: Queue.new } }
    let(:worker) do
      Thread.new do
        alpha = described_class.new(context)
        alpha.connect!('alpha')
        gate[:started] << :ready
        gate[:release].pop
        gate[:observed] << alpha.effective_prefix
      end
    end

    before do
      worker
      gate[:started].pop
      handler.connect!('beta')
    end

    after do
      gate[:release] << :done
      worker.join
    end

    it 'leaks beta into the alpha thread, because the setter is process-wide' do
      gate[:release] << :done
      expect(gate[:observed].pop).to eq('beta')
    end

    it 'still records the prefix the other thread asked for' do
      expect(registry.conflicts('beta')).to eq(['alpha'])
    end

    it 'warns naming both the incoming and the conflicting prefix' do
      expect(ConsoleKit::Output).to have_received(:print_warning).with(/wants "beta".*hold "alpha"/)
    end

    it 'does not repeat the same warning on an unchanged conflict' do
      handler.connect!('beta')
      expect(ConsoleKit::Output).to have_received(:print_warning).once
    end
  end

  describe '#diagnostics' do
    let(:cluster) { ElasticsearchMocks::Cluster.new }
    let(:client) { ElasticsearchMocks::Client.new(cluster: cluster) }

    context 'when level is :basic' do
      before do
        Elasticsearch::Model.client = client
        allow(Elasticsearch::Model).to receive(:client).and_call_original
        handler.connect!('acme')
      end

      it 'never asks for a client' do
        handler.diagnostics(level: :basic)
        expect(Elasticsearch::Model).not_to have_received(:client)
      end

      it 'never pings' do
        handler.diagnostics(level: :basic)
        expect(client.ping_calls).to eq(0)
      end

      it 'never reads cluster health' do
        handler.diagnostics(level: :basic)
        expect(cluster.health_calls).to eq(0)
      end

      it 'returns name Elasticsearch' do
        expect(handler.diagnostics(level: :basic)[:name]).to eq('Elasticsearch')
      end

      it 'returns status :connected' do
        expect(handler.diagnostics(level: :basic)[:status]).to eq(:connected)
      end

      it 'returns nil latency_ms' do
        expect(handler.diagnostics(level: :basic)[:latency_ms]).to be_nil
      end

      it 'reports the resolved prefix' do
        expect(handler.diagnostics(level: :basic)[:details][:prefix]).to eq('acme')
      end

      it 'reports the isolation model' do
        expect(handler.diagnostics(level: :basic)[:details][:isolation]).to eq(:process_global)
      end
    end

    context 'when level is :full' do
      before { Elasticsearch::Model.client = client }

      it 'returns name Elasticsearch' do
        expect(handler.diagnostics(level: :full)[:name]).to eq('Elasticsearch')
      end

      it 'returns status :connected' do
        expect(handler.diagnostics(level: :full)[:status]).to eq(:connected)
      end

      it 'returns a numeric latency_ms' do
        expect(handler.diagnostics(level: :full)[:latency_ms]).to be_a(Numeric)
      end

      it 'returns details with prefix, cluster and health keys' do
        expect(handler.diagnostics(level: :full)[:details]).to include(:prefix, :cluster, :health)
      end

      it 'includes the cluster name in details' do
        expect(handler.diagnostics(level: :full)[:details][:cluster]).to eq('test-cluster')
      end

      it 'includes the cluster health status in details' do
        expect(handler.diagnostics(level: :full)[:details][:health]).to eq('green')
      end
    end

    context 'when the cluster cannot be pinged' do
      let(:client) { ElasticsearchMocks::Client.new(cluster: cluster, ping_error: 'no route') }

      before { Elasticsearch::Model.client = client }

      it 'returns status :error rather than reporting a healthy connection' do
        expect(handler.diagnostics(level: :full)[:status]).to eq(:error)
      end

      it 'does not go on to read cluster health' do
        handler.diagnostics(level: :full)
        expect(cluster.health_calls).to eq(0)
      end

      it 'includes the unreachable message in details' do
        expect(handler.diagnostics(level: :full)[:details][:error]).to include('unreachable')
      end
    end

    context 'when Elasticsearch::Model does not respond to client' do
      before { stub_const('Elasticsearch::Model', Module.new) }

      it 'returns status :unavailable' do
        expect(handler.diagnostics[:status]).to eq(:unavailable)
      end

      it 'returns name Elasticsearch' do
        expect(handler.diagnostics[:name]).to eq('Elasticsearch')
      end
    end

    context 'when Elasticsearch is not defined' do
      before { hide_const('Elasticsearch') }

      it 'returns status :unavailable' do
        expect(handler.diagnostics[:status]).to eq(:unavailable)
      end

      it 'returns name Elasticsearch' do
        expect(handler.diagnostics[:name]).to eq('Elasticsearch')
      end

      it 'returns nil latency_ms' do
        expect(handler.diagnostics[:latency_ms]).to be_nil
      end

      it 'returns empty details' do
        expect(handler.diagnostics[:details]).to eq({})
      end
    end

    # A bug inside ConsoleKit must reach the operator as the bug it is. The
    # handler's own rescue used to catch it first, so `Runner.failed_row` never
    # got the chance to re-raise it and the row described a healthy backend as
    # broken instead.
    context 'when :full diagnostics hit a bug rather than an unreachable cluster' do
      before do
        allow(Elasticsearch::Model).to receive(:client).and_raise(NoMethodError, "undefined method 'client'")
      end

      it 'surfaces the bug instead of laundering it into an error row' do
        expect { handler.diagnostics(level: :full) }.to raise_error(NoMethodError)
      end
    end

    context 'when the connection raises an error' do
      before do
        allow(Elasticsearch::Model).to receive(:client).and_raise(StandardError, 'connection timeout')
      end

      it 'returns status :error' do
        expect(handler.diagnostics(level: :full)[:status]).to eq(:error)
      end

      it 'returns name Elasticsearch' do
        expect(handler.diagnostics(level: :full)[:name]).to eq('Elasticsearch')
      end

      it 'returns nil latency_ms' do
        expect(handler.diagnostics(level: :full)[:latency_ms]).to be_nil
      end

      it 'includes the error message in details' do
        expect(handler.diagnostics(level: :full)[:details][:error]).to include('connection timeout')
      end
    end
  end

  # An elasticsearch-model too old to expose index_name_prefix can still be
  # reset to "no prefix", and ConsoleKit's own record is then the only account
  # of what this thread asked for.
  describe 'a library version that exposes no index_name_prefix' do
    before { stub_const('Elasticsearch::Model', Elasticsearch::ModelWithoutPrefix) }

    it 'falls back to the prefix ConsoleKit recorded for this thread' do
      registry.record('acme')
      expect(handler.effective_prefix).to eq('acme')
    end

    it 'resets to no prefix without raising' do
      expect { handler.connect!(nil) }.not_to raise_error
    end

    it 'verifies that reset' do
      handler.connect!(nil)
      expect(handler.verify!(nil)).to be(true)
    end
  end

  describe 'context attribute access' do
    it 'reads tenant_elasticsearch_prefix from context' do
      expect(handler.send(:context_attribute, :tenant_elasticsearch_prefix)).to eq('acme')
    end
  end

  describe 'the shared connection handler contract' do
    include_context 'with the Elasticsearch handler contract'

    it_behaves_like 'a connection handler'
  end
end
