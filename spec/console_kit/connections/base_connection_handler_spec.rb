# frozen_string_literal: true

require 'spec_helper'

class DummyContext
  attr_reader :tenant_shard, :tenant_mongo_db, :partner_identifier

  def initialize(tenant_shard: nil, tenant_mongo_db: nil, partner_identifier: nil)
    @tenant_shard = tenant_shard
    @tenant_mongo_db = tenant_mongo_db
    @partner_identifier = partner_identifier
  end
end

RSpec.describe ConsoleKit::Connections::BaseConnectionHandler do
  let(:context) { instance_double(DummyContext) }
  let(:handler) { described_class.new(context) }

  describe '.registry' do
    it 'includes the known handlers' do
      expect(described_class.registry).to include(
        ConsoleKit::Connections::MongoConnectionHandler,
        ConsoleKit::Connections::SqlConnectionHandler
      )
    end

    it 'does not include a bare subclass that never declares a backend' do
      subclass = Class.new(described_class)
      expect(described_class.registry).not_to include(subclass)
    end
  end

  describe '.backend' do
    let(:handler_class) { stub_const('TestOnlyHandler', Class.new(described_class)) }

    after { ConsoleKit::Connections::HandlerRegistry.remove(handler_class) }

    def declare(klass, key)
      klass.backend(key, display_name: 'Test', context_attribute: :tenant_test, constants_key: :test,
                         detail_label: 'Test')
    end

    it 'registers the class in the registry' do
      declare(handler_class, :test_only)
      expect(described_class.registry).to include(handler_class)
    end

    it 'records the declared backend_key' do
      declare(handler_class, :test_only)
      expect(handler_class.backend_key).to eq(:test_only)
    end
  end

  describe ConsoleKit::Connections::HandlerRegistry do
    def declare(name, key)
      klass = stub_const(name, Class.new(ConsoleKit::Connections::BaseConnectionHandler))
      klass.backend(key, display_name: name, context_attribute: :"tenant_#{key}", constants_key: key,
                         detail_label: name)
      klass
    end

    describe 'declaration order' do
      let(:second) { declare('SecondTestHandler', :second_test_key) }
      let(:first) { declare('FirstTestHandler', :first_test_key) }

      after do
        described_class.remove(second)
        described_class.remove(first)
      end

      it 'preserves the order backends were declared in, not key order' do
        second
        first
        keys = described_class.all.map(&:backend_key)
        expect(keys.index(:second_test_key)).to be < keys.index(:first_test_key)
      end
    end

    describe 'a reload generation replacing itself' do
      let(:first_generation) { declare('ReloadTestHandler', :reload_test_key) }
      let(:second_generation) { declare('ReloadTestHandler', :reload_test_key) }

      before { allow(ConsoleKit::Output).to receive(:print_warning) }
      after { described_class.remove(second_generation) }

      it 'keeps the newest generation under the shared key' do
        first_generation
        second_generation
        expect(described_class.all).to include(second_generation)
      end

      it 'drops the earlier generation' do
        first_generation
        second_generation
        expect(described_class.all).not_to include(first_generation)
      end

      it 'says nothing, because a reload duplicate is expected' do
        first_generation
        second_generation
        expect(ConsoleKit::Output).not_to have_received(:print_warning)
      end
    end

    describe 'two differently named classes claiming one key' do
      let(:alpha) { declare('AlphaTestHandler', :collided_test_key) }
      let(:beta) { declare('BetaTestHandler', :collided_test_key) }

      before { allow(ConsoleKit::Output).to receive(:print_warning) }
      after { described_class.remove(beta) }

      it 'keeps the second declaration under the shared key' do
        alpha
        beta
        expect(described_class.all).to include(beta)
      end

      it 'drops the first declaration' do
        alpha
        beta
        expect(described_class.all).not_to include(alpha)
      end

      it 'warns that both classes claim the same backend key' do
        alpha
        beta
        expect(ConsoleKit::Output).to have_received(:print_warning).with(a_string_including(':collided_test_key'))
      end
    end

    describe '.remove' do
      let(:handler_class) { declare('RemovableTestHandler', :removable_test_key) }

      it 'takes a spec-only handler back out of the registry' do
        handler_class
        described_class.remove(handler_class)
        expect(described_class.all).not_to include(handler_class)
      end
    end
  end

  describe '#connect!' do
    it 'raises NotImplementedError' do
      expect { handler.connect!(nil) }.to raise_error(NotImplementedError)
    end

    it 'includes the class name in the error message' do
      expect { handler.connect!(nil) }
        .to raise_error(NotImplementedError, /BaseConnectionHandler must implement #connect!/)
    end
  end

  describe '#unavailable_reason' do
    it 'is nil unless a handler says otherwise' do
      expect(handler.unavailable_reason).to be_nil
    end
  end

  describe '#target when the context attribute is blank' do
    let(:handler_class) do
      stub_const('BlankTargetHandler', Class.new(described_class) do
        backend :blank_target, display_name: 'Blank', context_attribute: :tenant_blank,
                               constants_key: :blank, detail_label: 'Blank'
      end)
    end
    let(:blank_context) { Struct.new(:tenant_blank).new(value) }

    after { ConsoleKit::Connections::HandlerRegistry.remove(handler_class) }

    context 'with an empty string' do
      let(:value) { '' }

      it 'reads as no target at all' do
        expect(handler_class.new(blank_context).target).to be_nil
      end
    end

    context 'with whitespace only' do
      let(:value) { '   ' }

      it 'reads as no target at all' do
        expect(handler_class.new(blank_context).target).to be_nil
      end
    end
  end

  describe '#prepare rejecting a target that carries a credential' do
    let(:handler_class) do
      stub_const('CredentialTargetHandler', Class.new(described_class) do
        def self.target_error(_value) = 'expected a shard name'

        def prepare(target) = validate_target!(target)
      end)
    end

    let(:secret_target) { 'mongodb://admin:s3cr3t@db.internal/acme' }

    it 'redacts the credential out of the message' do
      expect { handler_class.new(context).prepare(secret_target) }
        .to raise_error(ConsoleKit::ConfigurationError, /\[redacted\]/)
    end

    it 'still says why the value was rejected' do
      expect { handler_class.new(context).prepare(secret_target) }
        .to raise_error(ConsoleKit::ConfigurationError, /expected a shard name/)
    end
  end

  describe '#available?' do
    it 'raises NotImplementedError by default' do
      expect { handler.available? }.to raise_error(NotImplementedError, /must implement #available?/)
    end
  end

  describe '#diagnostics' do
    it 'raises NotImplementedError when the handler cannot even say whether it is available' do
      expect { handler.diagnostics }.to raise_error(NotImplementedError, /must implement #available?/)
    end

    it 'raises NotImplementedError when the handler implements no diagnostic level' do
      available = Class.new(described_class) { def available? = true }.new(context)
      expect { available.diagnostics }.to raise_error(NotImplementedError, /must implement #basic_diagnostics/)
    end
  end

  describe '#safe_diagnostics' do
    let(:handler_class) do
      stub_const('SafeDiagnosticsHandler', Class.new(described_class) do
        def available? = false
        def diagnostics(level: :basic) = { name: 'Safe', status: :connected, latency_ms: nil, details: { level: } }
      end)
    end
    let(:safe_handler) { handler_class.new(context) }

    it 'returns the handler row' do
      expect(safe_handler.safe_diagnostics[:status]).to eq(:connected)
    end

    it 'defaults to the cheap basic level' do
      expect(safe_handler.safe_diagnostics[:details][:level]).to eq(:basic)
    end

    it 'passes an explicit level through' do
      expect(safe_handler.safe_diagnostics(level: :full)[:details][:level]).to eq(:full)
    end

    it 'rejects an unknown level' do
      expect { safe_handler.safe_diagnostics(level: :deep) }.to raise_error(ConsoleKit::ConfigurationError)
    end
  end

  describe 'initialization' do
    it 'assigns the context' do
      expect(handler.context).to eq(context)
    end
  end
end
