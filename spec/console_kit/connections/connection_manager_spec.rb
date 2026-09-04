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

  # `registry` is `descendants`, which keeps every generation of a handler class
  # alive across a code reload. Two entries then claim one backend_key, and the
  # plan, the undo bundle and the rollback all key on backend_key, so the older
  # duplicate has its snapshot silently discarded while it is still connected
  # and is then rolled back from the other instance's snapshot.
  #
  # These handlers deliberately do not inherit BaseConnectionHandler: the
  # registry is `descendants`, so an anonymous subclass would leak into every
  # later example in the process.
  describe 'de-duplicating the resolved handlers' do
    before { allow(ConsoleKit::Output).to receive(:print_warning) }

    def handler_class(key)
      Class.new do
        define_singleton_method(:backend_key) { key }
        def initialize(context) = @context = context
        def available? = true
      end
    end

    def stub_registry(*classes)
      allow(ConsoleKit::Connections::BaseConnectionHandler).to receive(:registry).and_return(classes)
    end

    context 'when a code reload leaves two generations of one handler class behind' do
      let(:generations) { [handler_class(:reloadable), handler_class(:reloadable)] }

      # Both generations carry the same constant name, exactly as Zeitwerk
      # leaves them; only the second one is what the name still resolves to.
      before do
        generations.each { |klass| stub_const('ReloadedHandler', klass) }
        stub_registry(*generations)
      end

      it 'resolves the backend exactly once' do
        expect(described_class.available_handlers(context).size).to eq(1)
      end

      it 'keeps the generation the constant still resolves to' do
        expect(described_class.available_handlers(context).first.class).to be(generations.last)
      end

      it 'says nothing, because a reload duplicate is expected' do
        described_class.available_handlers(context)
        expect(ConsoleKit::Output).not_to have_received(:print_warning)
      end
    end

    context 'when two differently named classes claim one backend key' do
      before do
        stub_const('AlphaHandler', handler_class(:collided))
        stub_const('BetaHandler', handler_class(:collided))
        stub_registry(AlphaHandler, BetaHandler)
      end

      it 'keeps only one handler for the key' do
        expect(described_class.available_handlers(context).size).to eq(1)
      end

      it 'warns that both classes claim the same backend key' do
        described_class.available_handlers(context)
        expect(ConsoleKit::Output).to have_received(:print_warning).with(a_string_including(':collided'))
      end
    end

    it 'orders handlers by backend key rather than by Class#subclasses order' do
      stub_registry(handler_class(:zed), handler_class(:alpha))
      keys = described_class.available_handlers(context).map { |handler| handler.class.backend_key }
      expect(keys).to eq(%i[alpha zed])
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
        def self.backend_key = :half_implemented
        def initialize(context) = @context = context
        def available? = raise NotImplementedError, 'HalfHandler must implement #available?'
      end
    end

    def not_loaded
      Class.new do
        def self.backend_key = :not_loaded
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
