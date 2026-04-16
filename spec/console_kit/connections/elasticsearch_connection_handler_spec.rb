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

  after do
    Thread.current[:console_kit_elasticsearch_prefix] = nil
  end

  describe '#connect' do
    it 'sets the thread-local prefix' do
      handler.connect
      expect(Thread.current[:console_kit_elasticsearch_prefix]).to eq('acme')
    end

    context 'when Elasticsearch::Model is defined' do
      before do
        es_model = Module.new do
          class << self
            attr_accessor :index_name_prefix
          end
        end
        stub_const('Elasticsearch::Model', es_model)
      end

      it 'sets index_name_prefix on Elasticsearch::Model' do
        handler.connect
        expect(Elasticsearch::Model.index_name_prefix).to eq('acme')
      end
    end

    context 'when Elasticsearch::Model does not support index_name_prefix=' do
      before do
        stub_const('Elasticsearch::Model', Module.new)
      end

      it 'does not raise an error' do
        expect { handler.connect }.not_to raise_error
      end
    end

    context 'when tenant_elasticsearch_prefix is empty' do
      let(:context) { instance_double(DummyContext, tenant_elasticsearch_prefix: '') }

      it 'sets thread-local prefix to nil' do
        handler.connect
        expect(Thread.current[:console_kit_elasticsearch_prefix]).to be_nil
      end
    end

    context 'when tenant_elasticsearch_prefix is nil' do
      let(:context) { instance_double(DummyContext, tenant_elasticsearch_prefix: nil) }

      it 'sets thread-local prefix to nil' do
        handler.connect
        expect(Thread.current[:console_kit_elasticsearch_prefix]).to be_nil
      end
    end
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

  describe '#diagnostics' do
    context 'when Elasticsearch::Model is available with a client' do
      let(:cluster) { double(health: { 'cluster_name' => 'my-cluster', 'status' => 'green' }) }
      let(:es_client) { double(ping: true, cluster: cluster) }

      before do
        the_client = es_client
        es_model = Module.new do
          define_singleton_method(:client) { the_client }
        end
        stub_const('Elasticsearch::Model', es_model)
      end

      it 'returns name Elasticsearch' do
        expect(handler.diagnostics[:name]).to eq('Elasticsearch')
      end

      it 'returns status :connected' do
        expect(handler.diagnostics[:status]).to eq(:connected)
      end

      it 'returns a numeric latency_ms' do
        expect(handler.diagnostics[:latency_ms]).to be_a(Numeric)
      end

      it 'returns details with prefix, cluster, and health keys' do
        expect(handler.diagnostics[:details]).to include(:prefix, :cluster, :health)
      end

      it 'includes the cluster name in details' do
        expect(handler.diagnostics[:details][:cluster]).to eq('my-cluster')
      end

      it 'includes the cluster health status in details' do
        expect(handler.diagnostics[:details][:health]).to eq('green')
      end
    end

    context 'when Elasticsearch::Model does not respond to client' do
      before do
        stub_const('Elasticsearch::Model', Module.new)
      end

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

    context 'when the connection raises an error' do
      before do
        es_model = Module.new do
          def self.client
            raise StandardError, 'connection timeout'
          end
        end
        stub_const('Elasticsearch::Model', es_model)
      end

      it 'returns status :error' do
        expect(handler.diagnostics[:status]).to eq(:error)
      end

      it 'returns name Elasticsearch' do
        expect(handler.diagnostics[:name]).to eq('Elasticsearch')
      end

      it 'returns nil latency_ms' do
        expect(handler.diagnostics[:latency_ms]).to be_nil
      end

      it 'includes the error message in details' do
        expect(handler.diagnostics[:details][:error]).to include('connection timeout')
      end
    end
  end

  describe 'context attribute access' do
    it 'reads tenant_elasticsearch_prefix from context' do
      expect(handler.send(:context_attribute, :tenant_elasticsearch_prefix)).to eq('acme')
    end
  end
end
