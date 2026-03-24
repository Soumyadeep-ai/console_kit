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
    stub_const('Mongoid', Class.new { def self.override_database(*); end })
    allow(Mongoid).to receive(:override_database)
  end

  describe '#connect' do
    it 'calls override_database with correct DB' do
      handler.connect
      expect(Mongoid).to have_received(:override_database).with('mongo_foo')
    end

    context 'when tenant_mongo_db is empty' do
      let(:context) { instance_double(DummyContext, tenant_mongo_db: '') }

      it 'calls override_database with nil' do
        handler.connect
        expect(Mongoid).to have_received(:override_database).with(nil)
      end
    end

    it 'raises error on connection issues' do
      allow(Mongoid).to receive(:override_database).and_raise('mongo error')
      expect { handler.connect }.to raise_error('mongo error')
    end

    context 'when Mongoid does not support override_database' do
      before do
        mongo_class = Class.new
        allow(mongo_class).to receive(:respond_to?).with(:override_database).and_return(false)
        stub_const('Mongoid', mongo_class)
      end

      it 'prints a warning but does not raise error' do
        allow(ConsoleKit::Output).to receive(:print_warning)

        handler.connect

        expect(ConsoleKit::Output).to have_received(:print_warning).with(/override_database/)
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

  describe '#diagnostics' do
    context 'when MongoDB is available' do
      let(:database) do
        double(
          name: 'mongo_foo',
          command: double('mock')
        )
      end
      let(:client) { double(use: double(database: database), database: database) }
      let(:build_info_result) { [{ 'version' => '6.0.0' }] }

      before do
        stub_const('Mongoid', Class.new do
          def self.override_database(*); end
          def self.default_client; end
        end)
        allow(database).to receive(:command).with(ping: 1)
        allow(database).to receive(:command).with(buildInfo: 1).and_return(build_info_result)
        allow(Mongoid).to receive(:default_client).and_return(client)
      end

      it 'returns name MongoDB' do
        expect(handler.diagnostics[:name]).to eq('MongoDB')
      end

      it 'returns status :connected' do
        expect(handler.diagnostics[:status]).to eq(:connected)
      end

      it 'returns a numeric latency_ms' do
        expect(handler.diagnostics[:latency_ms]).to be_a(Numeric)
      end

      it 'returns details with database and version keys' do
        expect(handler.diagnostics[:details]).to include(:database, :version)
      end

      it 'includes the database name in details' do
        expect(handler.diagnostics[:details][:database]).to eq('mongo_foo')
      end

      it 'includes the server version in details' do
        expect(handler.diagnostics[:details][:version]).to eq('6.0.0')
      end
    end

    context 'when Mongoid is not defined' do
      before { hide_const('Mongoid') }

      it 'returns status :unavailable' do
        expect(handler.diagnostics[:status]).to eq(:unavailable)
      end

      it 'returns name MongoDB' do
        expect(handler.diagnostics[:name]).to eq('MongoDB')
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
        stub_const('Mongoid', Class.new do
          def self.override_database(*); end
          def self.default_client; end
        end)
        allow(Mongoid).to receive(:default_client).and_raise(StandardError, 'auth failed')
      end

      it 'returns status :error' do
        expect(handler.diagnostics[:status]).to eq(:error)
      end

      it 'returns name MongoDB' do
        expect(handler.diagnostics[:name]).to eq('MongoDB')
      end

      it 'returns nil latency_ms' do
        expect(handler.diagnostics[:latency_ms]).to be_nil
      end

      it 'includes the error message in details' do
        expect(handler.diagnostics[:details][:error]).to include('auth failed')
      end
    end
  end

  describe 'context attribute access' do
    it 'reads tenant_mongo_db from context' do
      expect(handler.send(:context_attribute, :tenant_mongo_db)).to eq('mongo_foo')
    end
  end
end
