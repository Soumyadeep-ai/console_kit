# frozen_string_literal: true

require 'spec_helper'

# Dummy context object for connection handler specs
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
    it 'includes its subclasses' do
      subclass = Class.new(described_class)
      expect(described_class.registry).to include(subclass)
    end
  end

  describe '#connect' do
    it 'raises NotImplementedError' do
      expect { handler.connect }.to raise_error(NotImplementedError)
    end

    it 'includes the class name in the error message' do
      expect { handler.connect }.to raise_error(NotImplementedError, /BaseConnectionHandler must implement #connect/)
    end
  end

  describe '#available?' do
    it 'raises NotImplementedError by default' do
      expect { handler.available? }.to raise_error(NotImplementedError, /must implement #available?/)
    end
  end

  describe '#diagnostics' do
    it 'raises NotImplementedError' do
      expect { handler.diagnostics }.to raise_error(NotImplementedError, /must implement #diagnostics/)
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

    after { ConsoleKit::Diagnostics::Runner.shutdown! }

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

    it 'starts no thread for the basic level' do
      safe_handler.safe_diagnostics
      expect(ConsoleKit::Diagnostics::Runner.live_thread_count).to eq(0)
    end
  end

  describe 'initialization' do
    it 'assigns the context' do
      expect(handler.context).to eq(context)
    end
  end

  describe 'subclassing behavior' do
    it 'registers subclasses automatically upon definition' do
      stub_const('MyNewHandler', Class.new(described_class))
      expect(described_class.registry).to include(MyNewHandler)
    end

    it 'includes the known handlers' do
      expect(described_class.registry).to include(
        ConsoleKit::Connections::MongoConnectionHandler,
        ConsoleKit::Connections::SqlConnectionHandler
      )
    end
  end
end
