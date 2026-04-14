# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ConsoleKit::Connections::ConnectionManager do
  let(:dummy_context_class) do
    Class.new do
      def tenant_shard; end
      def tenant_mongo_db; end
    end
  end

  let(:dummy_handler_a) do
    Class.new(ConsoleKit::Connections::BaseConnectionHandler) do
      def connect; end
      def available? = true
      def diagnostics = { name: 'DummyA', status: :connected, latency_ms: 0, details: {} }
    end
  end

  let(:dummy_handler_b) do
    Class.new(ConsoleKit::Connections::BaseConnectionHandler) do
      def connect; end
      def available? = false
      def diagnostics = { name: 'DummyB', status: :unavailable, latency_ms: nil, details: {} }
    end
  end

  let(:context) { instance_double(dummy_context_class) }

  before do
    stub_const('DummyContext', dummy_context_class)
    stub_const('ConsoleKit::Connections::DummyHandlerA', dummy_handler_a)
    stub_const('ConsoleKit::Connections::DummyHandlerB', dummy_handler_b)
  end

  describe '.available_handlers' do
    subject(:handlers) { described_class.available_handlers(context) }

    it 'returns only instances of BaseConnectionHandler' do
      expect(handlers).to all(be_a(ConsoleKit::Connections::BaseConnectionHandler))
    end

    it 'includes available handlers' do
      expect(handlers.map(&:class)).to include(dummy_handler_a)
    end

    it 'excludes unavailable handlers' do
      expect(handlers.map(&:class)).not_to include(dummy_handler_b)
    end

    it 'passes the context to initialized handlers' do
      expect(handlers.first.context).to eq(context)
    end

    it 'returns an empty array when all handlers are unavailable' do
      allow(ConsoleKit::Connections::BaseConnectionHandler).to receive(:registry).and_return([dummy_handler_b])
      expect(described_class.available_handlers(context)).to be_empty
    end

    it 'uses BaseConnectionHandler.registry to discover handlers' do
      allow(ConsoleKit::Connections::BaseConnectionHandler).to receive(:registry).and_call_original
      described_class.available_handlers(context)
      expect(ConsoleKit::Connections::BaseConnectionHandler).to have_received(:registry)
    end
  end
end
