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
  let(:context) { instance_double(DummyContext, tenant_shard: 'shard_foo') }
  let(:handler) { described_class.new(context) }

  before do
    stub_const('ApplicationRecord', Class.new { def self.establish_connection(*); end })
    allow(ApplicationRecord).to receive(:establish_connection)
  end

  describe '#connect' do
    it 'calls establish_connection with correct shard' do
      handler.connect
      expect(ApplicationRecord).to have_received(:establish_connection).with(:shard_foo)
    end

    context 'when tenant_shard is nil' do
      let(:context) { instance_double(DummyContext, tenant_shard: nil) }

      it 'does not call establish_connection' do
        handler.connect
        expect(ApplicationRecord).not_to have_received(:establish_connection)
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
  end
end
