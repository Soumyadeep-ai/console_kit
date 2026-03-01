# frozen_string_literal: true

require 'spec_helper'

# Dummy context object for connection handler specs
class DummyContext
  attr_reader :tenant_mongo_db

  def initialize(tenant_mongo_db: nil)
    @tenant_mongo_db = tenant_mongo_db
  end
end

RSpec.describe ConsoleKit::Connections::MongoConnectionHandler do
  let(:context) { instance_double(DummyContext, tenant_mongo_db: 'mongo_foo') }
  let(:handler) { described_class.new(context) }

  before do
    stub_const('Mongoid', Class.new { def self.override_client(*); end })
    allow(Mongoid).to receive(:override_client)
  end

  describe '#connect' do
    it 'calls override_client with correct DB' do
      handler.connect
      expect(Mongoid).to have_received(:override_client).with('mongo_foo')
    end

    context 'when tenant_mongo_db is empty' do
      let(:context) { instance_double(DummyContext, tenant_mongo_db: '') }

      it 'calls override_client with nil' do
        handler.connect
        expect(Mongoid).to have_received(:override_client).with(nil)
      end
    end

    it 'raises error on connection issues' do
      allow(Mongoid).to receive(:override_client).and_raise('mongo error')
      expect { handler.connect }.to raise_error('mongo error')
    end

    context 'when Mongoid does not support override_client' do
      before do
        mongo_class = Class.new
        allow(mongo_class).to receive(:respond_to?).with(:override_client).and_return(false)
        stub_const('Mongoid', mongo_class)
      end

      it 'prints a warning but does not raise error' do
        allow(ConsoleKit::Output).to receive(:print_warning)

        handler.connect

        expect(ConsoleKit::Output).to have_received(:print_warning).with(/override_client/)
      end
    end
  end

  describe '#available?' do
    it 'returns true when Mongoid is defined' do
      expect(handler).to be_available
    end

    it 'returns false when Mongoid is not defined' do
      hide_const('Mongoid')
      expect(handler).not_to be_available
    end
  end

  describe 'delegation' do
    it 'delegates tenant_mongo_db to context' do
      expect(handler.tenant_mongo_db).to eq('mongo_foo')
    end
  end
end
