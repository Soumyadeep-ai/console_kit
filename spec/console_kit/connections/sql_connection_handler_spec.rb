# frozen_string_literal: true

require 'spec_helper'

# Dummy context object for connection handler specs
class DummyContext
  attr_reader :tenant_shard

  def initialize(tenant_shard: nil)
    @tenant_shard = tenant_shard
  end
end

RSpec.describe ConsoleKit::Connections::SqlConnectionHandler do
  let(:pool_class) do
    Class.new do
      def disconnect!; end
    end
  end
  let(:context) { instance_double(DummyContext, tenant_shard: 'shard_foo') }
  let(:handler) { described_class.new(context) }
  let(:connection_pool) { instance_double(pool_class, disconnect!: true) }

  before do
    stub_const('ApplicationRecord', Class.new do
      def self.establish_connection(*); end
      def self.connection_pool; end
    end)
    allow(ApplicationRecord).to receive(:establish_connection)
    allow(ApplicationRecord).to receive(:connection_pool).and_return(connection_pool)
  end

  describe '#connect' do
    it 'calls establish_connection with correct shard' do
      handler.connect
      expect(ApplicationRecord).to have_received(:establish_connection).with(:shard_foo)
    end

    it 'disconnects the old connection pool before establishing a new one' do
      handler.connect
      expect(connection_pool).to have_received(:disconnect!)
    end

    # rubocop:disable RSpec/MultipleExpectations, RSpec/MessageSpies
    it 'disconnects before establishing a new connection' do
      expect(connection_pool).to receive(:disconnect!).ordered
      expect(ApplicationRecord).to receive(:establish_connection).with(:shard_foo).ordered
      handler.connect
    end
    # rubocop:enable RSpec/MultipleExpectations, RSpec/MessageSpies

    context 'with a custom base class' do
      let(:custom_pool) { instance_double(pool_class, disconnect!: true) }

      before do
        stub_const('MyBaseRecord', Class.new do
          def self.establish_connection(*); end
          def self.connection_pool; end
        end)
        allow(MyBaseRecord).to receive(:establish_connection)
        allow(MyBaseRecord).to receive(:connection_pool).and_return(custom_pool)
        ConsoleKit.configuration.sql_base_class = 'MyBaseRecord'
      end

      after { ConsoleKit.configuration.sql_base_class = 'ApplicationRecord' }

      it 'calls establish_connection on the custom base class' do
        handler.connect
        expect(MyBaseRecord).to have_received(:establish_connection).with(:shard_foo)
      end

      it 'disconnects the custom base class pool' do
        handler.connect
        expect(custom_pool).to have_received(:disconnect!)
      end

      it 'does not call establish_connection on ApplicationRecord' do
        handler.connect
        expect(ApplicationRecord).not_to have_received(:establish_connection)
      end
    end

    context 'when tenant_shard is nil' do
      let(:context) { instance_double(DummyContext, tenant_shard: nil) }

      it 'calls establish_connection with no arguments' do
        handler.connect
        expect(ApplicationRecord).to have_received(:establish_connection).with(no_args)
      end

      it 'still disconnects the old pool' do
        handler.connect
        expect(connection_pool).to have_received(:disconnect!)
      end
    end

    context 'when connection_pool is not available' do
      before do
        allow(ApplicationRecord).to receive(:respond_to?).and_call_original
        allow(ApplicationRecord).to receive(:respond_to?).with(:connection_pool).and_return(false)
      end

      it 'skips disconnect and still establishes connection' do
        handler.connect
        expect(ApplicationRecord).to have_received(:establish_connection).with(:shard_foo)
      end
    end

    it 'raises errors to be handled upstream' do
      allow(ApplicationRecord).to receive(:establish_connection).and_raise('SQL ERROR')
      expect { handler.connect }.to raise_error('SQL ERROR')
    end
  end

  describe '#available?' do
    it 'returns true when ApplicationRecord is defined' do
      expect(handler).to be_available
    end

    it 'returns true when custom base class is defined' do
      stub_const('MyBaseRecord', Class.new)
      ConsoleKit.configuration.sql_base_class = 'MyBaseRecord'
      expect(handler).to be_available
    ensure
      ConsoleKit.configuration.sql_base_class = 'ApplicationRecord'
    end

    it 'returns false when base class is not defined' do
      ConsoleKit.configuration.sql_base_class = 'NonExistent'
      expect(handler).not_to be_available
    ensure
      ConsoleKit.configuration.sql_base_class = 'ApplicationRecord'
    end
  end

  describe '#diagnostics' do
    context 'when SQL is available' do
      before do
        stub_const('ApplicationRecord', Class.new do
          def self.establish_connection(*); end
          def self.connection; end
          def self.connection_pool; end
        end)
        allow(ApplicationRecord).to receive_messages(
          connection: double(adapter_name: 'PostgreSQL', execute: true, select_value: 'PostgreSQL 14.0'),
          connection_pool: double(size: 5)
        )
      end

      it 'returns a hash with name SQL' do
        result = handler.diagnostics
        expect(result[:name]).to eq('SQL')
      end

      it 'returns status :connected' do
        result = handler.diagnostics
        expect(result[:status]).to eq(:connected)
      end

      it 'returns a numeric latency_ms' do
        result = handler.diagnostics
        expect(result[:latency_ms]).to be_a(Numeric)
      end

      it 'returns details with adapter, pool_size, and version keys' do
        result = handler.diagnostics
        expect(result[:details]).to include(:adapter, :pool_size, :version)
      end

      it 'includes the adapter name in details' do
        result = handler.diagnostics
        expect(result[:details][:adapter]).to eq('PostgreSQL')
      end

      it 'includes the pool size in details' do
        result = handler.diagnostics
        expect(result[:details][:pool_size]).to eq(5)
      end
    end

    context 'when SQL is unavailable' do
      before do
        ConsoleKit.configuration.sql_base_class = 'NonExistent'
      end

      after { ConsoleKit.configuration.sql_base_class = 'ApplicationRecord' }

      it 'returns status :unavailable' do
        expect(handler.diagnostics[:status]).to eq(:unavailable)
      end

      it 'returns name SQL' do
        expect(handler.diagnostics[:name]).to eq('SQL')
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
        stub_const('ApplicationRecord', Class.new do
          def self.establish_connection(*); end
          def self.connection; end
        end)
        allow(ApplicationRecord).to receive(:connection).and_raise(StandardError, 'connection refused')
      end

      it 'returns status :error' do
        expect(handler.diagnostics[:status]).to eq(:error)
      end

      it 'returns name SQL' do
        expect(handler.diagnostics[:name]).to eq('SQL')
      end

      it 'returns nil latency_ms' do
        expect(handler.diagnostics[:latency_ms]).to be_nil
      end

      it 'includes the error message in details' do
        expect(handler.diagnostics[:details][:error]).to include('connection refused')
      end
    end
  end
end
