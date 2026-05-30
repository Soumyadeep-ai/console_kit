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

  describe '#safe_diagnostics' do
    let(:working_handler_class) do
      Class.new(described_class) do
        def self.name = 'TestConnectionHandler'
        def available? = true
        def diagnostics = { name: 'Test', status: :connected, latency_ms: 1.0, details: {} }
      end
    end
    let(:working_handler) { working_handler_class.new(context) }

    it 'returns diagnostics when they complete within timeout' do
      result = working_handler.safe_diagnostics(timeout: 2)
      expect(result[:name]).to eq('Test')
    end

    it 'returns status :connected when completed' do
      result = working_handler.safe_diagnostics(timeout: 2)
      expect(result[:status]).to eq(:connected)
    end

    context 'when diagnostics times out' do
      let(:slow_handler) do
        Class.new(described_class) do
          def self.name = 'SlowConnectionHandler'
          def available? = true

          def diagnostics
            sleep(0.5)
            { name: 'Slow', status: :connected, latency_ms: 1.0, details: {} }
          end
        end.new(context)
      end

      it 'returns timeout diagnostics' do
        result = slow_handler.safe_diagnostics(timeout: 0.05)
        expect(result[:status]).to eq(:timeout)
      end

      it 'includes the timeout message in details' do
        result = slow_handler.safe_diagnostics(timeout: 0.05)
        expect(result[:details][:error]).to include('Timed out')
      end
    end

    context 'when diagnostics raises an error' do
      let(:error_handler) do
        Class.new(described_class) do
          def self.name = 'ErrorConnectionHandler'
          def available? = true

          def diagnostics
            raise StandardError, 'connection failed'
          end
        end.new(context)
      end

      it 'returns error diagnostics' do
        result = error_handler.safe_diagnostics(timeout: 2)
        expect(result[:status]).to eq(:error)
      end

      it 'includes the error message in details' do
        result = error_handler.safe_diagnostics(timeout: 2)
        expect(result[:details][:error]).to include('connection failed')
      end
    end
  end

  describe '#measure_latency' do
    let(:concrete_handler_class) do
      Class.new(described_class) do
        def available? = true
        def diagnostics = nil

        def test_measure_latency(&block)
          measure_latency(&block)
        end
      end
    end
    let(:concrete_handler) { concrete_handler_class.new(context) }

    it 'returns a numeric latency in milliseconds' do
      latency = concrete_handler.test_measure_latency { sleep(0.001) }
      expect(latency).to be_a(Numeric)
    end

    it 'returns a positive value' do
      latency = concrete_handler.test_measure_latency { nil }
      expect(latency).to be >= 0
    end
  end

  describe '#context_attribute' do
    let(:ctx) do
      obj = Object.new
      obj.define_singleton_method(:my_attr) { 'my_value' }
      obj
    end
    let(:handler_with_ctx) { described_class.new(ctx) }

    it 'reads an attribute from context via try' do
      expect(handler_with_ctx.send(:context_attribute, :my_attr)).to eq('my_value')
    end

    it 'returns nil for missing attribute' do
      expect(handler_with_ctx.send(:context_attribute, :nonexistent)).to be_nil
    end
  end

  describe '#unavailable_diagnostics' do
    it 'returns a hash with :unavailable status' do
      result = handler.send(:unavailable_diagnostics, 'TestDB')
      expect(result[:status]).to eq(:unavailable)
    end

    it 'returns the name' do
      result = handler.send(:unavailable_diagnostics, 'TestDB')
      expect(result[:name]).to eq('TestDB')
    end

    it 'returns nil latency_ms' do
      result = handler.send(:unavailable_diagnostics, 'TestDB')
      expect(result[:latency_ms]).to be_nil
    end

    it 'returns empty details hash' do
      result = handler.send(:unavailable_diagnostics, 'TestDB')
      expect(result[:details]).to eq({})
    end
  end
end
