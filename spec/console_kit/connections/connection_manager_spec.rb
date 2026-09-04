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

  # A dropped handler vanishes from the switch, the verification, the snapshot
  # AND the rollback, so a switch can report itself verified while that backend
  # still serves another tenant. "Half-implemented" has to be loud; "optional gem
  # not loaded" has to stay silent.
  #
  # These handlers deliberately do not inherit BaseConnectionHandler: the
  # registry is `descendants`, so an anonymous subclass would leak into every
  # later example in the process.
  describe 'a handler that cannot answer whether it is available' do
    before { allow(ConsoleKit::Output).to receive(:print_warning) }

    def half_implemented
      Class.new do
        def initialize(context) = @context = context
        def available? = raise NotImplementedError, 'HalfHandler must implement #available?'
      end
    end

    def not_loaded
      Class.new do
        def initialize(context) = @context = context
        def available? = false
      end
    end

    context 'when the handler raises NotImplementedError' do
      before do
        allow(ConsoleKit::Connections::BaseConnectionHandler).to receive(:registry).and_return([half_implemented])
      end

      it 'still drops it from the available handlers' do
        expect(described_class.available_handlers(context)).to be_empty
      end

      it 'warns with the reason the handler gave' do
        described_class.available_handlers(context)
        expect(ConsoleKit::Output)
          .to have_received(:print_warning).with(a_string_including('must implement #available?'))
      end

      it 'warns that the backend will not be rolled back' do
        described_class.available_handlers(context)
        expect(ConsoleKit::Output)
          .to have_received(:print_warning).with(a_string_including('NOT be switched, verified or rolled back'))
      end
    end

    context 'when the handler simply answers false, as an unloaded gem does' do
      before do
        allow(ConsoleKit::Connections::BaseConnectionHandler).to receive(:registry).and_return([not_loaded])
      end

      it 'drops it from the available handlers' do
        expect(described_class.available_handlers(context)).to be_empty
      end

      it 'says nothing about it' do
        described_class.available_handlers(context)
        expect(ConsoleKit::Output).not_to have_received(:print_warning)
      end
    end
  end
end
