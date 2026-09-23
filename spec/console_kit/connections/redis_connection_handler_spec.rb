# frozen_string_literal: true

require 'spec_helper'

class DummyContext
  attr_reader :tenant_redis_db

  def initialize(tenant_redis_db: nil)
    @tenant_redis_db = tenant_redis_db
  end
end

RSpec.describe ConsoleKit::Connections::RedisConnectionHandler do
  subject(:handler) { described_class.new(context) }

  let(:context) { instance_double(DummyContext, tenant_redis_db: 2) }
  let(:client) { Redis.current }

  before do
    described_class.isolation_warned = false
    allow(ConsoleKit::Output).to receive(:print_info)
    allow(ConsoleKit::Output).to receive(:print_warning)
  end

  describe '#available?' do
    it 'returns true when Redis is defined' do
      expect(handler).to be_available
    end

    it 'returns true when only RedisClient is defined' do
      hide_const('Redis')
      stub_const('RedisClient', RedisFakes::ConfigReader)
      expect(handler).to be_available
    end

    it 'returns false when no Redis client is defined at all' do
      hide_const('Redis')
      expect(handler).not_to be_available
    end
  end

  describe '#isolation_model' do
    context 'with the redis-rb 4.x process-global Redis.current singleton' do
      it 'reports :process_global' do
        expect(handler.isolation_model).to eq(:process_global)
      end

      it 'is not thread isolated' do
        expect(handler).not_to be_thread_isolated
      end
    end

    context 'with an application that hands out a per-thread client' do
      before { stub_const('Redis', RedisFakes::ThreadLocalRedis) }

      it 'reports :scoped' do
        expect(handler.isolation_model).to eq(:scoped)
      end

      it 'is thread isolated' do
        expect(handler).to be_thread_isolated
      end
    end

    context 'with redis-rb 5.x, where Redis.current was removed' do
      before { stub_const('Redis', RedisFakes::V5) }

      it 'reports :none' do
        expect(handler.isolation_model).to eq(:none)
      end

      it 'is not thread isolated' do
        expect(handler).not_to be_thread_isolated
      end
    end

    context 'with only RedisClient present' do
      before do
        hide_const('Redis')
        stub_const('RedisClient', RedisFakes::ConfigReader)
      end

      it 'reports :none, because redis-client has no process-wide registry' do
        expect(handler.isolation_model).to eq(:none)
      end
    end

    context 'when Redis.current builds a fresh client on every call' do
      before { stub_const('Redis', RedisFakes::EphemeralRedis) }

      it 'reports :none, because no SELECT could ever persist' do
        expect(handler.isolation_model).to eq(:none)
      end
    end
  end

  describe 'the isolation probe across repeated switches' do
    let(:spawned) { [0] }

    before do
      allow(Thread).to receive(:new).and_wrap_original do |original, *args, &block|
        spawned[0] += 1
        original.call(*args, &block)
      end
    end

    it 'spawns one probe thread however many switches run' do
      5.times { |db| described_class.new(context).connect!(db + 1) }
      expect(spawned.first).to eq(1)
    end

    it 'probes again when the application hands back a different client' do
      described_class.new(context).isolation_model
      Redis.reset!
      described_class.new(context).isolation_model
      expect(spawned.first).to eq(2)
    end
  end

  describe '#isolation_model when the probe itself fails' do
    context 'when resolving the client raises a programming error' do
      before { allow(Redis).to receive(:current).and_raise(NoMethodError, "undefined method 'db' for nil") }

      it 'surfaces the programming error instead of answering with an isolation model' do
        expect { handler.isolation_model }.to raise_error(NoMethodError)
      end

      it 'surfaces it from #prepare instead of rejecting the DB as unsupported' do
        expect { handler.prepare(2) }.to raise_error(NoMethodError)
      end
    end

    context 'when the probe thread hits a programming error' do
      before do
        resolves = [0]
        allow(Redis).to receive(:current).and_wrap_original do |original|
          resolves[0] += 1
          raise NoMethodError, "undefined method 'db' for nil" if resolves.first > 2

          original.call
        end
      end

      it 'surfaces the programming error instead of answering :unknown' do
        expect { handler.isolation_model }.to raise_error(NoMethodError)
      end
    end

    context 'when the probe fails for a reason that is not a bug' do
      before { allow(Thread).to receive(:new).and_raise(ThreadError, 'cannot create thread') }

      it 'reports :unknown rather than asserting :process_global' do
        expect(handler.isolation_model).to eq(:unknown)
      end

      it 'is not thread isolated' do
        expect(handler).not_to be_thread_isolated
      end
    end

    context 'when the client is simply unreachable' do
      before { allow(Redis).to receive(:current).and_raise(RedisFakes::CannotConnectError, 'connection refused') }

      it 'still reports :none' do
        expect(handler.isolation_model).to eq(:none)
      end

      it 'still rejects a non-default DB it cannot select and verify' do
        expect { handler.prepare(2) }.to raise_error(ConsoleKit::UnsupportedBackendError)
      end
    end
  end

  describe '#prepare' do
    it 'accepts a non-negative integer DB index' do
      expect { handler.prepare(2) }.not_to raise_error
    end

    it 'accepts a string of digits' do
      expect { handler.prepare('2') }.not_to raise_error
    end

    it 'accepts a nil target, meaning the default DB' do
      expect { handler.prepare(nil) }.not_to raise_error
    end

    it 'mutates nothing: no SELECT is issued' do
      handler.prepare(2)
      expect(client.selects).to be_empty
    end

    it 'raises ConfigurationError for a negative index' do
      expect { handler.prepare(-1) }.to raise_error(ConsoleKit::ConfigurationError)
    end

    it 'names the bad value in the negative index message' do
      expect { handler.prepare(-1) }.to raise_error(/-1/)
    end

    it 'raises ConfigurationError for a non-numeric string' do
      expect { handler.prepare('primary') }.to raise_error(ConsoleKit::ConfigurationError)
    end

    it 'names the bad value in the non-numeric string message' do
      expect { handler.prepare('primary') }.to raise_error(/"primary"/)
    end

    it 'raises ConfigurationError for a float' do
      expect { handler.prepare(1.5) }.to raise_error(ConsoleKit::ConfigurationError)
    end

    it 'raises ConfigurationError for a whole-number float' do
      expect { handler.prepare(2.0) }.to raise_error(ConsoleKit::ConfigurationError)
    end

    context 'when no client handle is reachable (redis-rb 5.x)' do
      before { stub_const('Redis', RedisFakes::V5) }

      it 'raises UnsupportedBackendError for a non-default DB' do
        expect { handler.prepare(2) }.to raise_error(ConsoleKit::UnsupportedBackendError)
      end

      it 'names the isolation model in the message' do
        expect { handler.prepare(2) }.to raise_error(/isolation model: none/)
      end

      it 'allows the default DB, which needs no SELECT' do
        expect { handler.prepare(nil) }.not_to raise_error
      end
    end

    context 'when the client cannot report its own DB index' do
      before { Redis.current = RedisFakes::Opaque.new }

      it 'raises UnsupportedBackendError for a non-default DB rather than pretending' do
        expect { handler.prepare(2) }.to raise_error(ConsoleKit::UnsupportedBackendError)
      end

      it 'names the isolation model it did detect' do
        expect { handler.prepare(2) }.to raise_error(/isolation model: process_global/)
      end

      it 'refuses an explicitly requested default DB too, which SELECT 0 would also move' do
        expect { handler.prepare(0) }.to raise_error(ConsoleKit::UnsupportedBackendError)
      end

      it 'still accepts a nil target, which asks for no DB at all' do
        expect { handler.prepare(nil) }.not_to raise_error
      end
    end
  end

  describe 'a client that can SELECT but cannot report its DB' do
    before { Redis.current = RedisFakes::Opaque.new(7) }

    it 'issues no SELECT for a reset it could not undo' do
      handler.connect!(nil)
      expect(client.selects).to be_empty
    end

    it 'leaves the connection on the DB the application chose' do
      handler.connect!(nil)
      expect(client.db_index).to eq(7)
    end
  end

  describe '#connect!' do
    it 'selects the tenant DB index' do
      handler.connect!(2)
      expect(client.selects).to eq([2])
    end

    it 'leaves the client on the tenant DB index' do
      handler.connect!(2)
      expect { handler.verify!(2) }.not_to raise_error
    end

    it 'coerces a string DB index' do
      handler.connect!('7')
      expect(client.selects).to eq([7])
    end

    it 'resets to the default DB when the target is nil' do
      handler.connect!(5)
      handler.connect!(nil)
      expect(client.selects).to eq([5, 0])
    end

    it 'switches between multiple tenants in order' do
      handler.connect!(2)
      handler.connect!(5)
      expect(client.selects).to eq([2, 5])
    end

    it 'ends on tenant A after switching A -> B -> A' do
      handler.connect!(2)
      handler.connect!(5)
      handler.connect!(2)
      expect { handler.verify!(2) }.not_to raise_error
    end

    it 'records every hop of an A -> B -> A switch' do
      handler.connect!(2)
      handler.connect!(5)
      handler.connect!(2)
      expect(client.selects).to eq([2, 5, 2])
    end

    it 'does not re-select when the client is already on the target DB' do
      handler.connect!(2)
      handler.connect!(2)
      expect(client.selects).to eq([2])
    end

    it 'does not select at all when the target is already the current DB' do
      handler.connect!(0)
      expect(client.selects).to be_empty
    end

    context 'with an invalid index that carries a credential' do
      let(:message) do
        handler.connect!('rediss://app:s3cr3t@cache.internal:6379/2')
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

    it 'raises ConfigurationError for an invalid index' do
      expect { handler.connect!(-3) }.to raise_error(ConsoleKit::ConfigurationError)
    end

    context 'when Redis is unreachable' do
      let(:failure) do
        handler.connect!(2)
        nil
      rescue ConsoleKit::ConnectionError => e
        e
      end

      before { client.reachable = false }

      it 'raises ConnectionError instead of printing a warning' do
        expect { handler.connect!(2) }.to raise_error(ConsoleKit::ConnectionError)
      end

      it 'reports the backend on the error' do
        expect(failure.backend).to eq('Redis')
      end

      it 'scrubs the Redis URL out of the failure message' do
        expect(failure.message).to include('[redacted]')
      end

      it 'never leaks the password from the client error' do
        expect(failure.message).not_to include('s3cr3t')
      end

      it 'leaves the client on its previous DB, so the snapshot still restores' do
        failure
        expect(handler.snapshot).to eq(db: 0)
      end
    end

    context 'when no client handle is reachable' do
      before { stub_const('Redis', RedisFakes::V5) }

      it 'is a no-op for the default DB rather than a fake success' do
        expect { handler.connect!(nil) }.not_to raise_error
      end
    end

    context 'when the isolation model is process-global' do
      it 'warns that DB selection is not thread isolated' do
        handler.connect!(2)
        expect(ConsoleKit::Output).to have_received(:print_warning).with(/NOT isolated per thread/)
      end

      it 'warns only once per process, not on every switch' do
        handler.connect!(2)
        described_class.new(context).connect!(5)
        expect(ConsoleKit::Output).to have_received(:print_warning).once
      end
    end

    context 'when the isolation model is scoped' do
      before { stub_const('Redis', RedisFakes::ThreadLocalRedis) }

      it 'emits no process-global warning' do
        handler.connect!(2)
        expect(ConsoleKit::Output).not_to have_received(:print_warning)
      end
    end
  end

  describe '#connect! with the context target' do
    it 'applies the DB index resolved from the context' do
      handler.connect!(handler.target)
      expect(client.selects).to eq([2])
    end
  end

  describe '#snapshot' do
    it 'captures the current DB index' do
      handler.connect!(5)
      expect(handler.snapshot).to eq(db: 5)
    end

    it 'issues no SELECT of its own' do
      handler.snapshot
      expect(client.selects).to be_empty
    end

    it 'captures nil when the client cannot report its DB' do
      Redis.current = RedisFakes::Opaque.new
      expect(handler.snapshot).to eq(db: nil)
    end
  end

  describe '#restore' do
    it 'round-trips back to the DB index captured before the switch' do
      handler.connect!(5)
      snap = handler.snapshot
      handler.connect!(9)
      handler.restore(snap)
      expect { handler.verify!(5) }.not_to raise_error
    end

    it 'restores back to the default DB' do
      snap = handler.snapshot
      handler.connect!(9)
      handler.restore(snap)
      expect { handler.verify!(nil) }.not_to raise_error
    end

    it 'issues a SELECT back to the previous index' do
      handler.connect!(9)
      handler.restore(db: 0)
      expect(client.selects).to eq([9, 0])
    end

    it 'does not re-select when the client is already on the snapshot DB' do
      handler.restore(db: 0)
      expect(client.selects).to be_empty
    end

    it 'does nothing when the snapshot could not capture a DB index' do
      handler.restore(db: nil)
      expect(client.selects).to be_empty
    end

    context 'when the client has no SELECT to drive' do
      let(:command_only) { RedisFakes::CommandOnly.new }

      before { Redis.current = command_only }

      it 'is a silent no-op rather than a NoMethodError' do
        expect { handler.restore(db: 5) }.not_to raise_error
      end

      it 'sends the client no command at all' do
        handler.restore(db: 5)
        expect(command_only.calls).to be_empty
      end
    end
  end

  describe '#verify!' do
    it 'succeeds when the live DB matches the target' do
      handler.connect!(2)
      expect { handler.verify!(2) }.not_to raise_error
    end

    it 'raises ConnectionVerificationError when the live DB differs from the target' do
      handler.connect!(2)
      expect { handler.verify!(5) }.to raise_error(ConsoleKit::ConnectionVerificationError)
    end

    it 'raises when the client never moved off the default DB' do
      expect { handler.verify!(2) }.to raise_error(ConsoleKit::ConnectionVerificationError)
    end

    it 'reports the expected DB index on the error' do
      expect { handler.verify!(2) }.to raise_error(an_object_having_attributes(expected: 2))
    end

    it 'reports the actual DB index on the error' do
      expect { handler.verify!(2) }.to raise_error(an_object_having_attributes(actual: 0))
    end

    it 'issues no SELECT to find out where the connection is' do
      handler.verify!(nil)
      expect(client.selects).to be_empty
    end

    it 'reads the DB through a RedisClient-style config object' do
      Redis.current = RedisFakes::ConfigReader.new(4)
      expect { handler.verify!(4) }.not_to raise_error
    end

    context 'when the client cannot report its DB' do
      before { Redis.current = RedisFakes::Opaque.new }

      it 'passes for the default DB, the only one #prepare allows through' do
        expect(handler.verify!(nil)).to be(true)
      end

      it 'still refuses to confirm a non-default DB' do
        expect { handler.verify!(2) }.to raise_error(ConsoleKit::ConnectionVerificationError)
      end
    end
  end

  describe 'concurrent tenant switches' do
    context 'when the isolation model is process-global (documented leakage, NOT isolation)' do
      before { handler.connect!(3) }

      it 'lets another thread move the DB this thread is using' do
        Thread.new { described_class.new(context).connect!(7) }.join
        expect { handler.verify!(3) }.to raise_error(ConsoleKit::ConnectionVerificationError)
      end

      it 'shares one logical DB between both threads' do
        Thread.new { described_class.new(context).connect!(7) }.join
        expect(handler.snapshot).to eq(db: 7)
      end
    end

    context 'when the isolation model is scoped' do
      before do
        stub_const('Redis', RedisFakes::ThreadLocalRedis)
        handler.connect!(3)
      end

      it 'keeps this thread on its own DB when another thread switches' do
        Thread.new { described_class.new(context).connect!(7) }.join
        expect { handler.verify!(3) }.not_to raise_error
      end

      it 'gives the other thread its own DB' do
        other = Thread.new { described_class.new(context).tap { |h| h.connect!(7) }.snapshot }.value
        expect(other).to eq(db: 7)
      end
    end
  end

  describe '#diagnostics' do
    context 'when level is :basic' do
      before do
        allow(client).to receive(:ping).and_call_original
        allow(client).to receive(:info).and_call_original
      end

      it 'issues no ping' do
        handler.diagnostics(level: :basic)
        expect(client).not_to have_received(:ping)
      end

      it 'issues no info command' do
        handler.diagnostics(level: :basic)
        expect(client).not_to have_received(:info)
      end

      it 'returns name Redis' do
        expect(handler.diagnostics(level: :basic)[:name]).to eq('Redis')
      end

      it 'returns status :connected' do
        expect(handler.diagnostics(level: :basic)[:status]).to eq(:connected)
      end

      it 'returns nil latency_ms' do
        expect(handler.diagnostics(level: :basic)[:latency_ms]).to be_nil
      end

      it 'reports the live DB index' do
        handler.connect!(2)
        expect(handler.diagnostics(level: :basic)[:details][:db]).to eq(2)
      end

      it 'reports the isolation model' do
        expect(handler.diagnostics(level: :basic)[:details][:isolation]).to eq(:process_global)
      end
    end

    context 'when level is :basic and no client is reachable' do
      before { stub_const('Redis', RedisFakes::V5) }

      it 'returns status :unknown' do
        expect(handler.diagnostics(level: :basic)[:status]).to eq(:unknown)
      end

      it 'falls back to the configured DB index' do
        expect(handler.diagnostics(level: :basic)[:details][:db]).to eq(2)
      end
    end

    context 'when :full diagnostics hit a bug rather than an unreachable server' do
      before { allow(client).to receive(:info).and_return(nil) }

      it 'surfaces the bug instead of laundering it into an error row' do
        expect { handler.diagnostics(level: :full) }.to raise_error(NoMethodError)
      end
    end

    context 'when level is :full and no client is reachable' do
      before { stub_const('Redis', RedisFakes::V5) }

      it 'returns status :unknown rather than :connected' do
        expect(handler.diagnostics(level: :full)[:status]).to eq(:unknown)
      end

      it 'measures no latency, because nothing was pinged' do
        expect(handler.diagnostics(level: :full)[:latency_ms]).to be_nil
      end

      it 'reports the isolation model that explains the degradation' do
        expect(handler.diagnostics(level: :full)[:details][:isolation]).to eq(:none)
      end
    end

    context 'when level is :full and only the redis-client gem is loaded' do
      before do
        hide_const('Redis')
        stub_const('RedisClient', RedisFakes::CommandOnly)
      end

      it 'returns status :unknown, because RedisClient exposes no process-wide handle' do
        expect(handler.diagnostics(level: :full)[:status]).to eq(:unknown)
      end

      it 'reports no server version, because nothing was asked for one' do
        expect(handler.diagnostics(level: :full)[:details]).not_to include(:version)
      end
    end

    context 'when level is :full' do
      it 'returns name Redis' do
        expect(handler.diagnostics(level: :full)[:name]).to eq('Redis')
      end

      it 'returns status :connected' do
        expect(handler.diagnostics(level: :full)[:status]).to eq(:connected)
      end

      it 'returns a numeric latency_ms' do
        expect(handler.diagnostics(level: :full)[:latency_ms]).to be_a(Numeric)
      end

      it 'returns details with db, version and memory keys' do
        expect(handler.diagnostics(level: :full)[:details]).to include(:db, :version, :memory)
      end

      it 'includes the redis version in details' do
        expect(handler.diagnostics(level: :full)[:details][:version]).to eq('7.0.0')
      end

      it 'includes used memory in details' do
        expect(handler.diagnostics(level: :full)[:details][:memory]).to eq('1.00M')
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
      before do
        allow(client).to receive(:info)
          .and_raise(StandardError, 'ECONNREFUSED for redis://app:s3cr3t@cache.internal:6379')
      end

      it 'returns status :error' do
        expect(handler.diagnostics(level: :full)[:status]).to eq(:error)
      end

      it 'returns name Redis' do
        expect(handler.diagnostics(level: :full)[:name]).to eq('Redis')
      end

      it 'returns nil latency_ms' do
        expect(handler.diagnostics(level: :full)[:latency_ms]).to be_nil
      end

      it 'includes the error message in details' do
        expect(handler.diagnostics(level: :full)[:details][:error]).to include('ECONNREFUSED')
      end

      it 'replaces the connection URL with a placeholder' do
        expect(handler.diagnostics(level: :full)[:details][:error]).to include('[redacted]')
      end

      it 'never leaks the credentials from the error message' do
        expect(handler.diagnostics(level: :full)[:details][:error]).not_to include('s3cr3t')
      end
    end
  end

  describe 'context attribute access' do
    it 'reads tenant_redis_db from context' do
      expect(handler.send(:context_attribute, :tenant_redis_db)).to eq(2)
    end

    it 'returns nil when context does not support the attribute' do
      bare_handler = described_class.new(Object.new)
      expect(bare_handler.send(:context_attribute, :tenant_redis_db)).to be_nil
    end
  end

  describe 'the shared connection handler contract' do
    include_context 'with the Redis handler contract'

    it_behaves_like 'a connection handler'
  end
end
