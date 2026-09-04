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
    allow(Mongoid).to receive(:override_database).and_call_original
    allow(Mongoid).to receive(:override_client).and_call_original
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

  describe '#connect! (regressions)' do
    context 'when target names a configured Mongoid client (Mongoid Wrong Database Bug regression)' do
      before { Mongoid::Config.clients = { 'mongo_foo' => {} } }

      it 'calls override_client with the client name' do
        handler.connect!('mongo_foo')
        expect(Mongoid).to have_received(:override_client).with('mongo_foo')
      end

      it 'does not call override_database' do
        handler.connect!('mongo_foo')
        expect(Mongoid).not_to have_received(:override_database)
      end
    end

    context 'when target is a plain database name' do
      it 'calls override_database with the database name' do
        handler.connect!('mongo_foo')
        expect(Mongoid).to have_received(:override_database).with('mongo_foo')
      end

      it 'does not call override_client' do
        handler.connect!('mongo_foo')
        expect(Mongoid).not_to have_received(:override_client)
      end
    end

    context 'when target is nil (reset)' do
      it 'clears the client override' do
        handler.connect!(nil)
        expect(Mongoid).to have_received(:override_client).with(nil)
      end

      it 'clears the database override' do
        handler.connect!(nil)
        expect(Mongoid).to have_received(:override_database).with(nil)
      end
    end

    it 'propagates a real failure instead of swallowing it into a warning' do
      allow(Mongoid).to receive(:override_database).and_raise('mongo error')
      expect { handler.connect!('mongo_foo') }.to raise_error('mongo error')
    end
  end

  describe '#prepare' do
    context 'when Mongoid does not support client overrides at all' do
      before { stub_const('Mongoid', Class.new) }

      it 'raises UnsupportedBackendError' do
        expect { handler.prepare('mongo_foo') }.to raise_error(ConsoleKit::UnsupportedBackendError)
      end
    end

    context 'when Mongoid supports overrides' do
      it 'does not call override_client' do
        handler.prepare('mongo_foo')
        expect(Mongoid).not_to have_received(:override_client)
      end

      it 'does not call override_database' do
        handler.prepare('mongo_foo')
        expect(Mongoid).not_to have_received(:override_database)
      end
    end
  end

  describe '#snapshot' do
    before do
      Mongoid::Threaded.client_override = 'client_a'
      Mongoid::Threaded.database_override = 'db_a'
    end

    it 'captures both the current client and database overrides' do
      expect(handler.snapshot).to eq(client: 'client_a', database: 'db_a')
    end
  end

  describe '#restore' do
    it 'restores overrides to their previous non-nil values' do
      handler.connect!('mongo_bar')
      handler.restore(client: 'client_a', database: 'db_a')
      expect([Mongoid::Threaded.client_override, Mongoid::Threaded.database_override]).to eq(%w[client_a db_a])
    end

    it 'restores overrides back to nil when the snapshot was nil' do
      handler.connect!('mongo_bar')
      handler.restore(client: nil, database: nil)
      expect([Mongoid::Threaded.client_override, Mongoid::Threaded.database_override]).to eq([nil, nil])
    end

    context 'when already switched to a named client' do
      before do
        Mongoid::Config.clients = { 'client_a' => {} }
        handler.connect!('client_a')
      end

      it 'round-trips: snapshot, connect elsewhere, restore returns to the previous identity' do
        snap = handler.snapshot
        handler.connect!('mongo_other')
        handler.restore(snap)
        expect([Mongoid::Threaded.client_override, Mongoid::Threaded.database_override]).to eq(['client_a', nil])
      end
    end
  end

  describe 'repeated switches' do
    it 'end on the last target identity after A -> B -> A' do
      handler.connect!('mongo_a')
      handler.connect!('mongo_b')
      handler.connect!('mongo_a')
      expect { handler.verify!('mongo_a') }.not_to raise_error
    end
  end

  describe '#verify!' do
    context 'when target names a configured Mongoid client' do
      before { Mongoid::Config.clients = { 'client_a' => {}, 'client_b' => {} } }

      it 'succeeds when the effective client matches the target' do
        handler.connect!('client_a')
        expect { handler.verify!('client_a') }.not_to raise_error
      end

      it 'raises ConnectionVerificationError when the effective client differs from the target' do
        handler.connect!('client_a')
        expect { handler.verify!('client_b') }.to raise_error(ConsoleKit::ConnectionVerificationError)
      end
    end

    context 'when target is a plain database name' do
      it 'succeeds when the effective database matches the target' do
        handler.connect!('mongo_foo')
        expect { handler.verify!('mongo_foo') }.not_to raise_error
      end

      it 'raises ConnectionVerificationError when the effective database differs from the target' do
        handler.connect!('mongo_foo')
        expect { handler.verify!('mongo_bar') }.to raise_error(ConsoleKit::ConnectionVerificationError)
      end
    end
  end

  describe '#diagnostics' do
    context 'when MongoDB is available at level: :basic' do
      let(:database) { instance_double(Mongoid::Database, name: 'mongo_foo') }
      let(:client) { instance_double(Mongoid::Client, database: database) }

      before { allow(Mongoid).to receive(:default_client).and_return(client) }

      it 'performs no network command' do
        allow(database).to receive(:command)
        handler.diagnostics(level: :basic)
        expect(database).not_to have_received(:command)
      end

      it 'returns name MongoDB' do
        expect(handler.diagnostics(level: :basic)[:name]).to eq('MongoDB')
      end

      it 'returns status :connected' do
        expect(handler.diagnostics(level: :basic)[:status]).to eq(:connected)
      end

      it 'returns nil latency_ms' do
        expect(handler.diagnostics(level: :basic)[:latency_ms]).to be_nil
      end

      it 'includes the resolved database identity in details' do
        expect(handler.diagnostics(level: :basic)[:details][:database]).to eq('mongo_foo')
      end
    end

    context 'when MongoDB is available at level: :full' do
      let(:database) { instance_double(Mongoid::Database, name: 'mongo_foo') }
      let(:client) { instance_double(Mongoid::Client, database: database) }

      before do
        allow(Mongoid).to receive(:default_client).and_return(client)
        allow(database).to receive(:command).with(ping: 1)
        allow(database).to receive(:command).with(buildInfo: 1).and_return([{ 'version' => '6.0.0' }])
      end

      it 'returns name MongoDB' do
        expect(handler.diagnostics(level: :full)[:name]).to eq('MongoDB')
      end

      it 'returns status :connected' do
        expect(handler.diagnostics(level: :full)[:status]).to eq(:connected)
      end

      it 'returns a numeric latency_ms' do
        expect(handler.diagnostics(level: :full)[:latency_ms]).to be_a(Numeric)
      end

      it 'includes the database name in details' do
        expect(handler.diagnostics(level: :full)[:details][:database]).to eq('mongo_foo')
      end

      it 'includes the server version in details' do
        expect(handler.diagnostics(level: :full)[:details][:version]).to eq('6.0.0')
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
        allow(Mongoid).to receive(:default_client).and_raise(StandardError, 'auth failed')
      end

      it 'returns status :error' do
        expect(handler.diagnostics(level: :full)[:status]).to eq(:error)
      end

      it 'returns name MongoDB' do
        expect(handler.diagnostics(level: :full)[:name]).to eq('MongoDB')
      end

      it 'returns nil latency_ms' do
        expect(handler.diagnostics(level: :full)[:latency_ms]).to be_nil
      end

      it 'includes the error message in details' do
        expect(handler.diagnostics(level: :full)[:details][:error]).to include('auth failed')
      end
    end
  end

  describe 'context attribute access' do
    it 'reads tenant_mongo_db from context' do
      expect(handler.send(:context_attribute, :tenant_mongo_db)).to eq('mongo_foo')
    end
  end

  describe 'the shared connection handler contract' do
    include_context 'with the MongoDB handler contract'

    it_behaves_like 'a connection handler'
  end
end
