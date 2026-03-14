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
    stub_const('Redis', Class.new { def self.current; end })
    allow(Redis).to receive(:current).and_return(redis_instance)
  end

  describe '#connect' do
    it 'calls select with correct DB' do
      handler.connect
      expect(redis_instance).to have_received(:select).with(2)
    end

    context 'when tenant_redis_db is nil' do
      let(:context) { instance_double(DummyContext, tenant_redis_db: nil) }

      it 'does not call select' do
        handler.connect
        expect(redis_instance).not_to have_received(:select)
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
