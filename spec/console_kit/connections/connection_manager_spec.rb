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
      backend :dummy_a, display_name: 'DummyA', context_attribute: :tenant_dummy_a, constants_key: :dummy_a,
                        detail_label: 'DummyA'

      def connect; end
      def available? = true
      def diagnostics = { name: 'DummyA', status: :connected, latency_ms: 0, details: {} }
    end
  end

  let(:dummy_handler_b) do
    Class.new(ConsoleKit::Connections::BaseConnectionHandler) do
      backend :dummy_b, display_name: 'DummyB', context_attribute: :tenant_dummy_b, constants_key: :dummy_b,
                        detail_label: 'DummyB'

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

  # `backend` registers on HandlerRegistry, which lives for the whole suite
  # rather than being reset per example the way stub_const's own constants
  # are, so a handler declared only for this spec must be removed by hand.
  after do
    ConsoleKit::Connections::HandlerRegistry.remove(dummy_handler_a)
    ConsoleKit::Connections::HandlerRegistry.remove(dummy_handler_b)
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

  # Reload-generation replacement, cross-name collision warnings and
  # declaration ordering are now HandlerRegistry's job, since registration is
  # explicit (a handler joins by declaring `backend`) rather than implicit via
  # `descendants`. See "ConsoleKit::Connections::HandlerRegistry" in
  # base_connection_handler_spec.rb for that coverage; ConnectionManager only
  # has to read the registry it is handed, which ".available_handlers" above
  # already covers.

  # A dropped handler vanishes from the switch, the verification, the snapshot
  # AND the rollback, so a switch can report itself verified while that backend
  # still serves another tenant. "Half-implemented" has to be loud; "optional gem
  # not loaded" has to stay silent.
  #
  # These handlers deliberately do not inherit BaseConnectionHandler and stub
  # `.registry` directly, so they never actually join HandlerRegistry.
  describe 'a handler that cannot answer whether it is available' do
    before { allow(ConsoleKit::Output).to receive(:print_warning) }

    def half_implemented
      Class.new do
        def self.backend_key = :half_implemented
        def initialize(context) = @context = context
        def available? = raise NotImplementedError, 'HalfHandler must implement #available?'
      end
    end

    # The same backend key, half-implemented in a different way: a reload can
    # leave a handler broken for a new reason, and that is news.
    def broken_differently
      Class.new do
        def self.backend_key = :half_implemented
        def initialize(context) = @context = context
        def available? = raise NotImplementedError, 'HalfHandler must implement #snapshot'
      end
    end

    def not_loaded
      Class.new do
        def self.backend_key = :not_loaded
        def initialize(context) = @context = context
        def available? = false
      end
    end

    # Complete, loaded, and pointed at something that is not there: the operator
    # asked for this backend, so its absence is news rather than a supported setup.
    def misconfigured
      Class.new do
        def self.backend_key = :misconfigured
        def initialize(context) = @context = context
        def available? = false
        def unavailable_reason = 'the configured vault_base_class "Nope" could not be resolved'
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

      # A warning alone is lost the moment it scrolls past. The caller that
      # commits tenant state needs the key itself, or nothing downstream can
      # tell that the backend was left behind.
      it 'hands the dropped backend key back to the caller that asked for one' do
        dropped = []
        described_class.available_handlers(context, dropped)
        expect(dropped).to eq([:half_implemented])
      end

      # The dashboard reads the same handler list, so an unchanged broken
      # handler reprinted this on every single render and buried whatever the
      # operator typed `dashboard` to look at.
      it 'says it once rather than on every call' do
        2.times { described_class.available_handlers(context) }
        expect(ConsoleKit::Output).to have_received(:print_warning).once
      end

      it 'still counts every drop, so the metric keeps its rate' do
        2.times { described_class.available_handlers(context) }
        expect(ConsoleKit::Instrumentation.counts['console_kit.handler_dropped']).to eq(2)
      end

      it 'says it again when the reason itself changes' do
        described_class.available_handlers(context)
        allow(ConsoleKit::Connections::BaseConnectionHandler).to receive(:registry).and_return([broken_differently])
        described_class.available_handlers(context)
        expect(ConsoleKit::Output).to have_received(:print_warning).twice
      end
    end

    context 'when the handler answers false and says why' do
      before do
        allow(ConsoleKit::Connections::BaseConnectionHandler).to receive(:registry).and_return([misconfigured])
      end

      it 'drops it from the available handlers' do
        expect(described_class.available_handlers(context)).to be_empty
      end

      it 'hands the backend key back as dropped, since it is not an absent gem' do
        dropped = []
        described_class.available_handlers(context, dropped)
        expect(dropped).to eq([:misconfigured])
      end

      it 'warns with the reason the handler gave' do
        described_class.available_handlers(context)
        expect(ConsoleKit::Output)
          .to have_received(:print_warning).with(a_string_including('could not be resolved'))
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

      it 'does not count it as dropped' do
        dropped = []
        described_class.available_handlers(context, dropped)
        expect(dropped).to be_empty
      end
    end
  end
end
