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
  subject(:handler) { described_class.new(context) }

  let(:base_class) { ActiveRecordMock.sharded_base(configs: config_names, shards: %w[shard_one shard_two]) }
  let(:shard) { 'shard_one' }
  let(:context) { instance_double(DummyContext, tenant_shard: shard) }

  def config_names = %w[primary shard_one shard_two legacy_db]
  def pool_handler = base_class.connection_handler

  before do
    stub_const('ApplicationRecord', base_class)
    ConsoleKit::Output.silent = true
  end

  describe '#available?' do
    it 'is true when the configured base class exists' do
      expect(handler).to be_available
    end

    it 'is false when the configured base class does not exist' do
      ConsoleKit.configuration.sql_base_class = 'NotARealRecord'
      expect(handler).not_to be_available
    end

    it 'raises a ConfigurationError when a missing base class is actually used' do
      ConsoleKit.configuration.sql_base_class = 'NotARealRecord'
      expect { handler.connect!('shard_one') }.to raise_error(ConsoleKit::ConfigurationError, /could not be found/)
    end
  end

  # A configured base class that does not resolve drops SQL out of the switch,
  # the verify, the snapshot and the rollback. That is indistinguishable from
  # "ActiveRecord is not loaded" unless the handler says which of the two it is,
  # which is what the reason is for - the switch records it as a dropped backend.
  describe '#unavailable_reason' do
    before { allow(ConsoleKit::Output).to receive(:print_warning) }

    context 'when the operator configured the class name explicitly' do
      before { ConsoleKit.configuration.sql_base_class = 'Legacy::NotARealRecord' }

      it 'names the class that could not be resolved' do
        expect(handler.unavailable_reason).to include('Legacy::NotARealRecord')
      end

      it 'still answers false rather than raising out of the switch' do
        expect(handler).not_to be_available
      end

      it 'prints nothing itself, so a repeated dashboard render cannot bury the table' do
        handler.available?
        expect(ConsoleKit::Output).not_to have_received(:print_warning)
      end
    end

    context 'when the application simply has no ActiveRecord' do
      before { hide_const('ApplicationRecord') }

      it 'gives no reason, because the default base class is allowed to be absent' do
        expect(handler.unavailable_reason).to be_nil
      end

      it 'answers false' do
        expect(handler).not_to be_available
      end
    end

    context 'when the base class resolves' do
      it 'gives no reason' do
        expect(handler.unavailable_reason).to be_nil
      end
    end
  end

  describe '#prepare' do
    it 'accepts a natively registered shard' do
      expect { handler.prepare('shard_one') }.not_to raise_error
    end

    it 'accepts a plain database configuration name' do
      expect { handler.prepare('legacy_db') }.not_to raise_error
    end

    it 'accepts a nil target' do
      expect { handler.prepare(nil) }.not_to raise_error
    end

    it 'raises ConfigurationError for a shard that resolves to nothing' do
      expect { handler.prepare('nowhere') }.to raise_error(ConsoleKit::ConfigurationError, /not a registered shard/)
    end

    it 'leaves the current shard untouched' do
      handler.prepare('shard_one')
      expect(base_class.current_shard).to eq(:default)
    end

    it 'establishes no connection' do
      handler.prepare('shard_one')
      expect(pool_handler.disconnects).to eq(0)
    end

    it 'mutates nothing when it raises' do
      prepare_ignoring_errors('nowhere')
      expect(base_class.connection_pool.db_config.name).to eq('primary')
    end

    def prepare_ignoring_errors(target)
      handler.prepare(target)
    rescue ConsoleKit::ConfigurationError
      nil
    end

    # A tenant constant can hold a whole database URI, and #prepare runs before
    # the transaction, so this rejection escapes switch_tenant unwrapped and
    # reaches the logs with whatever the constant held.
    context 'with an unresolved shard that carries a credential' do
      let(:uri) { 'postgres://app:s3cr3t@db.internal:5432/acme' }
      let(:message) do
        handler.prepare(uri)
        nil
      rescue ConsoleKit::ConfigurationError => e
        e.message
      end

      it 'redacts the value out of the rejection' do
        expect(message).to include('[redacted]')
      end

      it 'never leaks the password' do
        expect(message).not_to include('s3cr3t')
      end
    end

    context 'when the base class cannot switch connections at all' do
      let(:base_class) { Class.new }

      it 'raises UnsupportedBackendError' do
        expect { handler.prepare('shard_one') }.to raise_error(ConsoleKit::UnsupportedBackendError)
      end
    end
  end

  describe '#connect! on the native shard path' do
    before { handler.connect!('shard_one') }

    it 'points the base class at the requested shard' do
      expect(base_class.current_shard).to eq(:shard_one)
    end

    it 'pushes exactly one entry onto the connected_to stack' do
      expect(base_class.connected_to_stack.size).to eq(1)
    end

    it 'preserves the current role' do
      expect(base_class.current_role).to eq(:writing)
    end

    it 'never churns a connection pool' do
      expect(pool_handler.disconnects).to eq(0)
    end

    it 'keeps the default pool connected' do
      expect(pool_handler.retrieve_connection_pool('ApplicationRecord', role: :writing, shard: :default).disconnects)
        .to eq(0)
    end
  end

  describe '#connect! on the establish_connection fallback path' do
    before { handler.connect!('legacy_db') }

    it 'repoints the pool at the requested configuration' do
      expect(base_class.connection_pool.db_config.name).to eq('legacy_db')
    end

    it 'replaces the previous pool exactly once' do
      expect(pool_handler.disconnects).to eq(1)
    end

    it 'leaves the shard stack alone' do
      expect(base_class.connected_to_stack).to be_empty
    end
  end

  describe '#connect! repeated switching' do
    it 'lands on the last requested shard' do
      %w[shard_one shard_two shard_one shard_two].each { |name| handler.connect!(name) }
      expect(base_class.current_shard).to eq(:shard_two)
    end

    it 'never churns pools while alternating between native shards' do
      %w[shard_one shard_two shard_one shard_two].each { |name| handler.connect!(name) }
      expect(pool_handler.disconnects).to eq(0)
    end

    it 'does not re-establish when asked for the same fallback configuration twice' do
      3.times { handler.connect!('legacy_db') }
      expect(pool_handler.disconnects).to eq(1)
    end

    it 'still resolves to the same configuration after repeated fallback switches' do
      3.times { handler.connect!('legacy_db') }
      expect(base_class.connection_pool.db_config.name).to eq('legacy_db')
    end

    it 'does not touch the pool when the default is already live' do
      handler.connect!(nil)
      expect(pool_handler.disconnects).to eq(0)
    end
  end

  # `connecting_to` pushes onto the fiber-local shard stack and Rails offers no
  # matching pop, so every committed switch used to leave a frame behind. Rails
  # walks that stack on every `current_shard` lookup, i.e. on every query, and
  # the Railtie re-applies the tenant on every `reload!`.
  describe '#connect! stack growth' do
    it 'holds the stack at one frame across five successive switches' do
      %w[shard_one shard_two shard_one shard_two shard_one].each { |name| handler.connect!(name) }
      expect(base_class.connected_to_stack.size).to eq(1)
    end

    it 'holds the stack at one frame when the same shard is applied four times' do
      4.times { handler.connect!('shard_one') }
      expect(base_class.connected_to_stack.size).to eq(1)
    end

    it 'still churns no pool while the same shard is re-applied' do
      4.times { handler.connect!('shard_one') }
      expect(pool_handler.disconnects).to eq(0)
    end

    it 'does not grow the stack when resetting to the default' do
      handler.connect!('shard_one')
      handler.connect!(nil)
      expect(base_class.connected_to_stack.size).to eq(1)
    end

    it 'lands on the default shard after a reset' do
      handler.connect!('shard_one')
      handler.connect!(nil)
      expect(base_class.current_shard).to eq(:default)
    end

    it 'leaves a frame the application pushed itself alone' do
      base_class.connecting_to(shard: :shard_two, role: :writing)
      handler.connect!('shard_one')
      expect(base_class.connected_to_stack.size).to eq(2)
    end

    it 'restores the enclosing shard without growing the stack' do
      handler.connect!('shard_one')
      state = handler.snapshot
      handler.connect!('shard_two')
      handler.restore(state)
      expect(base_class.connected_to_stack.size).to eq(1)
    end

    it 'restores the exact depth after a failed switch is rolled back' do
      state = handler.snapshot
      handler.connect!('shard_one')
      handler.restore(state)
      expect(base_class.connected_to_stack.size).to eq(state[:stack_depth])
    end
  end

  describe '#connect! with the context target' do
    it 'applies the shard resolved from the context' do
      handler.connect!(handler.target)
      expect(base_class.current_shard).to eq(:shard_one)
    end

    context 'when the context carries no shard' do
      let(:shard) { nil }

      it 'leaves the connection on the default configuration' do
        handler.connect!(handler.target)
        expect(base_class.connection_pool.db_config.name).to eq('primary')
      end
    end
  end

  describe '#snapshot and #restore' do
    it 'captures the live shard' do
      expect(handler.snapshot[:shard]).to eq(:default)
    end

    it 'captures the live database configuration name' do
      expect(handler.snapshot[:db_config_name]).to eq('primary')
    end

    it 'mutates nothing' do
      handler.snapshot
      expect(pool_handler.disconnects).to eq(0)
    end

    it 'round-trips the native path back to the original shard' do
      state = handler.snapshot
      handler.connect!('shard_one')
      handler.restore(state)
      expect(base_class.current_shard).to eq(:default)
    end

    it 'leaves no stack residue after restoring the native path' do
      state = handler.snapshot
      handler.connect!('shard_one')
      handler.restore(state)
      expect(base_class.connected_to_stack).to be_empty
    end

    it 'round-trips the fallback path back to the original configuration' do
      state = handler.snapshot
      handler.connect!('legacy_db')
      handler.restore(state)
      expect(base_class.connection_pool.db_config.name).to eq('primary')
    end

    it 'restores from a nested native switch back to the enclosing shard' do
      handler.connect!('shard_one')
      state = handler.snapshot
      handler.connect!('shard_two')
      handler.restore(state)
      expect(base_class.current_shard).to eq(:shard_one)
    end

    it 'restores cleanly when there was no previous shard' do
      state = handler.snapshot
      handler.connect!('shard_one')
      handler.restore(state)
      expect(handler.snapshot).to eq(state)
    end

    it 'is a no-op when nothing was applied' do
      handler.restore(handler.snapshot)
      expect(pool_handler.disconnects).to eq(0)
    end
  end

  describe '#verify!' do
    it 'passes when the live shard matches the native target' do
      handler.connect!('shard_one')
      expect(handler.verify!('shard_one')).to be(true)
    end

    it 'passes when the live configuration matches the fallback target' do
      handler.connect!('legacy_db')
      expect(handler.verify!('legacy_db')).to be(true)
    end

    it 'passes for a nil target on an untouched connection' do
      expect(handler.verify!(nil)).to be(true)
    end

    it 'raises ConnectionVerificationError when the live shard is another shard' do
      handler.connect!('shard_one')
      expect { handler.verify!('shard_two') }.to raise_error(ConsoleKit::ConnectionVerificationError)
    end

    it 'reports the shard it expected' do
      handler.connect!('shard_one')
      expect { handler.verify!('shard_two') }.to raise_error(/Expected :shard_two/)
    end

    it 'reports the shard it actually found' do
      handler.connect!('shard_one')
      expect { handler.verify!('shard_two') }.to raise_error(/got :shard_one/)
    end

    it 'raises when the live configuration is another database configuration' do
      handler.connect!('legacy_db')
      expect { handler.verify!('primary') }.to raise_error(ConsoleKit::ConnectionVerificationError)
    end
  end

  describe '#connect! failure handling' do
    let(:state) { handler.snapshot }

    before do
      state
      allow(base_class).to receive(:connecting_to).and_raise(StandardError, 'shard registry exploded')
    end

    it 'lets the failure surface' do
      expect { handler.connect!('shard_one') }.to raise_error(StandardError, 'shard registry exploded')
    end

    it 'leaves the handler restorable to the captured shard' do
      attempt_failing_connect
      handler.restore(state)
      expect(base_class.current_shard).to eq(:default)
    end

    it 'leaves the handler restorable to the captured configuration' do
      attempt_failing_connect
      handler.restore(state)
      expect(base_class.connection_pool.db_config.name).to eq('primary')
    end

    def attempt_failing_connect
      handler.connect!('shard_one')
    rescue StandardError
      nil
    end
  end

  describe '#diagnostics with level: :basic' do
    subject(:result) { handler.diagnostics(level: :basic) }

    before { allow(base_class).to receive(:connection).and_call_original }

    it 'never asks the base class for a connection' do
      result
      expect(base_class).not_to have_received(:connection)
    end

    it 'runs no statement against the database' do
      result
      expect(base_class.connection.statements).to be_empty
    end

    it 'is named SQL' do
      expect(result[:name]).to eq('SQL')
    end

    it 'reports the connection as connected' do
      expect(result[:status]).to eq(:connected)
    end

    it 'reports no latency' do
      expect(result[:latency_ms]).to be_nil
    end

    it 'reports the resolved adapter' do
      expect(result[:details][:adapter]).to eq('postgresql')
    end

    it 'reports the pool size' do
      expect(result[:details][:pool_size]).to eq(5)
    end

    it 'reports the resolved configuration name' do
      expect(result[:details][:config]).to eq('primary')
    end

    it 'reports the resolved shard' do
      expect(result[:details][:shard]).to eq(:default)
    end

    it 'follows a native switch' do
      handler.connect!('shard_one')
      expect(result[:details][:shard]).to eq(:shard_one)
    end
  end

  describe '#diagnostics with level: :full' do
    subject(:result) { handler.diagnostics(level: :full) }

    it 'is named SQL' do
      expect(result[:name]).to eq('SQL')
    end

    it 'reports the connection as connected' do
      expect(result[:status]).to eq(:connected)
    end

    it 'measures a latency' do
      expect(result[:latency_ms]).to be_a(Numeric)
    end

    it 'exposes the adapter, pool size and version details' do
      expect(result[:details]).to include(:adapter, :pool_size, :version)
    end

    it 'reports the adapter name' do
      expect(result[:details][:adapter]).to eq('PostgreSQL')
    end

    it 'reports the pool size' do
      expect(result[:details][:pool_size]).to eq(5)
    end

    it 'reports the server version' do
      expect(result[:details][:version]).to eq('PostgreSQL 16.1 on aarch64')
    end

    it 'issues the availability probe' do
      result
      expect(base_class.connection.statements).to include('SELECT 1')
    end
  end

  describe '#diagnostics when unavailable' do
    subject(:result) { handler.diagnostics }

    before { ConsoleKit.configuration.sql_base_class = 'NotARealRecord' }

    it 'is named SQL' do
      expect(result[:name]).to eq('SQL')
    end

    it 'reports the backend as unavailable' do
      expect(result[:status]).to eq(:unavailable)
    end

    it 'reports no latency' do
      expect(result[:latency_ms]).to be_nil
    end

    it 'reports no details' do
      expect(result[:details]).to eq({})
    end
  end

  describe '#diagnostics when the connection fails' do
    subject(:result) { handler.diagnostics(level: :full) }

    before { allow(base_class).to receive(:connection).and_raise(StandardError, 'connection refused') }

    it 'reports an error status' do
      expect(result[:status]).to eq(:error)
    end

    it 'is still named SQL' do
      expect(result[:name]).to eq('SQL')
    end

    it 'reports no latency' do
      expect(result[:latency_ms]).to be_nil
    end

    it 'includes the failure message' do
      expect(result[:details][:error]).to include('connection refused')
    end
  end

  describe 'a base class without native shard APIs' do
    let(:base_class) { ActiveRecordMock.plain_base(configs: config_names) }

    it 'falls back to establish_connection' do
      handler.connect!('legacy_db')
      expect(base_class.connection_pool.db_config.name).to eq('legacy_db')
    end

    it 'verifies through the pool configuration name' do
      handler.connect!('legacy_db')
      expect(handler.verify!('legacy_db')).to be(true)
    end

    it 'raises on a mismatch' do
      handler.connect!('legacy_db')
      expect { handler.verify!('shard_one') }.to raise_error(ConsoleKit::ConnectionVerificationError)
    end

    it 'does not re-establish when the configuration is unchanged' do
      handler.connect!('legacy_db')
      pool = base_class.connection_pool
      handler.connect!('legacy_db')
      expect(base_class.connection_pool).to be(pool)
    end

    it 'restores the previous configuration' do
      state = handler.snapshot
      handler.connect!('legacy_db')
      handler.restore(state)
      expect(base_class.connection_pool.db_config.name).to eq('primary')
    end
  end

  # Rails connects lazily, so the first console command after boot runs against
  # an ActiveRecord that has never resolved a pool: `connection_pool` raises
  # until something establishes one.
  describe 'a base class that has not connected to anything yet' do
    let(:base_class) { ActiveRecordMock.unconnected_sharded_base(configs: config_names) }

    it 'accepts a real shard instead of rejecting it as unregistered' do
      expect { handler.prepare('shard_one') }.not_to raise_error
    end

    it 'lands the first switch on the requested configuration' do
      handler.connect!('shard_one')
      expect(base_class.connection_pool.db_config.name).to eq('shard_one')
    end

    it 'verifies that first switch' do
      handler.connect!('shard_one')
      expect(handler.verify!('shard_one')).to be(true)
    end

    it 'reports the connection as :unknown on the dashboard rather than as an error' do
      expect(handler.diagnostics(level: :basic)[:status]).to eq(:unknown)
    end

    it 'reports no details, because none can be read without a pool' do
      expect(handler.diagnostics(level: :basic)[:details]).to eq({})
    end
  end

  # `SELECT version()` is a courtesy detail, not the point of the probe.
  describe '#diagnostics when the version query fails' do
    subject(:result) { handler.diagnostics(level: :full) }

    let(:conn) { base_class.connection }

    context 'when the database refuses the query' do
      before { allow(conn).to receive(:select_value).and_raise(StandardError, 'function version() does not exist') }

      it 'still reports the connection as connected' do
        expect(result[:status]).to eq(:connected)
      end

      it 'reports an empty version rather than failing the whole probe' do
        expect(result[:details][:version]).to eq('')
      end
    end

    # The handler's own rescue used to catch this first, so `Runner.failed_row`
    # never got the chance to re-raise it and a bug inside ConsoleKit came back
    # as an ordinary :error row describing a backend that is perfectly healthy.
    context 'when the failure is a bug rather than a database refusal' do
      before { allow(conn).to receive(:select_value).and_raise(NameError, 'undefined local variable sql') }

      it 'surfaces the bug instead of laundering it into an error row' do
        expect { result }.to raise_error(NameError)
      end
    end
  end

  describe 'the shared connection handler contract' do
    include_context 'with the SQL handler contract'

    it_behaves_like 'a connection handler'
  end
end
