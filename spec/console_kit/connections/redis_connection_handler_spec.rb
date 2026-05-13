# frozen_string_literal: true

require 'spec_helper'

# Dummy context object for connection handler specs
class DummyContext
  attr_reader :tenant_redis_db

  def initialize(tenant_redis_db: nil)
    @tenant_redis_db = tenant_redis_db
  end
end

RSpec.describe ConsoleKit::Connections::RedisConnectionHandler do
  let(:context) { instance_double(DummyContext, tenant_redis_db: 2) }
  let(:handler) { described_class.new(context) }
  let(:redis_instance) { instance_double(Redis, select: true) }

  before do
    allow(Redis).to receive(:current).and_return(redis_instance)
  end

  describe '#connect' do
    it 'calls select with correct DB' do
      handler.connect
      expect(redis_instance).to have_received(:select).with(2)
    end

    context 'when tenant_redis_db is nil' do
      let(:context) { instance_double(DummyContext, tenant_redis_db: nil) }

      it 'resets to default DB 0' do
        handler.connect
        expect(redis_instance).to have_received(:select).with(0)
      end
    end

    context 'when Redis.current is not available (v5+)' do
      before do
        allow(Redis).to receive(:current).and_raise(NoMethodError)
      end

      it 'prints a warning but does not raise error' do
        allow(ConsoleKit::Output).to receive(:print_warning)

        handler.connect

        expect(ConsoleKit::Output).to have_received(:print_warning).with(/Redis\.current/)
      end
    end
  end

  describe '#available?' do
    it 'returns true when Redis is defined' do
      expect(handler).to be_available
    end

    it 'returns false when Redis is not defined' do
      hide_const('Redis')
      expect(handler).not_to be_available
    end
  end

  describe '#diagnostics' do
    context 'when Redis is available' do
      let(:redis_info) { { 'redis_version' => '7.0.0', 'used_memory_human' => '1.00M' } }
      let(:redis_client) { double(ping: 'PONG', info: redis_info) }

      before do
        allow(Redis).to receive(:respond_to?).with(:current).and_return(true)
        allow(Redis).to receive(:current).and_return(redis_client)
      end

      it 'returns name Redis' do
        expect(handler.diagnostics[:name]).to eq('Redis')
      end

      it 'returns status :connected' do
        expect(handler.diagnostics[:status]).to eq(:connected)
      end

      it 'returns a numeric latency_ms' do
        expect(handler.diagnostics[:latency_ms]).to be_a(Numeric)
      end

      it 'returns details with db, version, and memory keys' do
        expect(handler.diagnostics[:details]).to include(:db, :version, :memory)
      end

      it 'includes the redis version in details' do
        expect(handler.diagnostics[:details][:version]).to eq('7.0.0')
      end

      it 'includes used memory in details' do
        expect(handler.diagnostics[:details][:memory]).to eq('1.00M')
      end
    end

    context 'when Redis.current is not available' do
      before do
        allow(Redis).to receive(:respond_to?).with(:current).and_return(false)
      end

      it 'returns status :unavailable' do
        expect(handler.diagnostics[:status]).to eq(:unavailable)
      end

      it 'returns name Redis' do
        expect(handler.diagnostics[:name]).to eq('Redis')
      end
    end

    context 'when Redis is not defined' do
      before { hide_const('Redis') }

      it 'returns status :unavailable' do
        expect(handler.diagnostics[:status]).to eq(:unavailable)
      end

      it 'returns name Redis' do
        expect(handler.diagnostics[:name]).to eq('Redis')
      end

      it 'returns nil latency_ms' do
        expect(handler.diagnostics[:latency_ms]).to be_nil
      end

      it 'returns empty details' do
        expect(handler.diagnostics[:details]).to eq({})
      end
    end

    context 'when the connection raises an error' do
      let(:redis_client) { instance_double(Redis) }

      before do
        allow(Redis).to receive(:respond_to?).with(:current).and_return(true)
        allow(Redis).to receive(:current).and_return(redis_client)
        allow(redis_client).to receive(:ping).and_raise(StandardError, 'ECONNREFUSED')
      end

      it 'returns status :error' do
        expect(handler.diagnostics[:status]).to eq(:error)
      end

      it 'returns name Redis' do
        expect(handler.diagnostics[:name]).to eq('Redis')
      end

      it 'returns nil latency_ms' do
        expect(handler.diagnostics[:latency_ms]).to be_nil
      end

      it 'includes the error message in details' do
        expect(handler.diagnostics[:details][:error]).to include('ECONNREFUSED')
      end
    end
  end

  describe 'context attribute access' do
    it 'reads tenant_redis_db from context' do
      expect(handler.send(:context_attribute, :tenant_redis_db)).to eq(2)
    end

    it 'returns nil when context does not support the attribute' do
      bare_context = Object.new
      bare_handler = described_class.new(bare_context)
      expect(bare_handler.send(:context_attribute, :tenant_redis_db)).to be_nil
    end
  end
end
