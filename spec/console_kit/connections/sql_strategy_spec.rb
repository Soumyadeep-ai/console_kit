# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ConsoleKit::Connections::SqlStrategy do
  subject(:strategy) { described_class.new(base_class) }

  # Rails connects lazily. An application that has booted but has not run a
  # query yet has no pool registered at all, so every read through
  # `connection_pool` raises ConnectionNotEstablished. That is the shape of the
  # very first console command after boot, and none of it is a failure.
  describe 'a base class that has never been connected' do
    let(:base_class) { ActiveRecordMock.unconnected_sharded_base(configs: %w[primary shard_one]) }

    it 'claims no database configuration identity' do
      expect(strategy.snapshot[:db_config_name]).to be_nil
    end

    it 'still captures the shard, which needs no pool' do
      expect(strategy.snapshot[:shard]).to eq(:default)
    end

    it 'describes no pool to the dashboard instead of raising' do
      expect(strategy.pool_details).to eq({})
    end

    it 'does not declare a real shard unresolvable just because nothing is connected' do
      expect(strategy).to be_resolvable(:shard_one)
    end

    it 'reports the shard as not natively reachable, since no pool is registered for it' do
      expect(strategy).not_to be_native(:shard_one)
    end

    it 'establishes the requested configuration on the first switch' do
      strategy.apply(:shard_one)
      expect(base_class.connection_pool.db_config.name).to eq('shard_one')
    end

    it 'resolves the identity of that first switch' do
      strategy.apply(:shard_one)
      expect(strategy.identity(:shard_one)).to eq(%w[shard_one shard_one])
    end

    # "There was no pool" is a state a rollback has to be able to reach: leaving
    # the pool the switch established keeps the failed tenant's database connected.
    it 'removes the pool it established when the switch is rolled back' do
      state = strategy.snapshot
      strategy.apply(:shard_one)
      strategy.restore(state)
      expect { base_class.connection_pool }.to raise_error(ActiveRecordMock::ConnectionNotEstablished)
    end
  end

  # A base class with no shard API at all: the only route back to "no pool" is
  # removing the connection the fallback established.
  describe 'a plain base class that has never been connected' do
    let(:base_class) { ActiveRecordMock.unconnected_plain_base(configs: %w[primary shard_one]) }

    it 'records that there was no pool to go back to' do
      expect(strategy.snapshot[:pool_absent]).to be(true)
    end

    it 'removes the pool it established when the switch is rolled back' do
      state = strategy.snapshot
      strategy.apply(:shard_one)
      strategy.restore(state)
      expect(base_class.connection_pool).to be_nil
    end
  end

  # The other half of the same rule: a base class that DID have a pool is put
  # back onto its previous configuration, never left without one.
  describe 'restoring a base class that was already connected' do
    let(:base_class) { ActiveRecordMock.sharded_base(configs: %w[primary shard_one]) }

    it 'records that a pool was present' do
      expect(strategy.snapshot[:pool_absent]).to be(false)
    end

    it 'puts the previous configuration back instead of removing the pool' do
      state = strategy.snapshot
      strategy.apply(:shard_one)
      strategy.restore(state)
      expect(base_class.connection_pool.db_config.name).to eq('primary')
    end
  end

  # #pool_details is the resilience boundary of this file: a dead database must
  # degrade to "no details", while a bug in ConsoleKit itself must not be
  # laundered into one.
  describe '#pool_details when the pool chain raises' do
    let(:base_class) { ActiveRecordMock.sharded_base(configs: %w[primary]) }

    it 'absorbs a genuine connection failure into an empty description' do
      allow(base_class).to receive(:connection_pool).and_raise(StandardError, 'could not connect to server')
      expect(strategy.pool_details).to eq({})
    end

    it 'lets a NameError out, because that is a bug rather than a dead database' do
      allow(base_class).to receive(:connection_pool).and_raise(NameError, 'uninitialized constant TrilogyAdapter')
      expect { strategy.pool_details }.to raise_error(NameError)
    end

    it 'lets an ArgumentError out for the same reason' do
      allow(base_class).to receive(:connection_pool).and_raise(ArgumentError, 'wrong number of arguments')
      expect { strategy.pool_details }.to raise_error(ArgumentError)
    end

    it 'lets a programming error out of #snapshot rather than recording a nil identity' do
      allow(base_class).to receive(:connection_pool).and_raise(NameError, 'uninitialized constant TrilogyAdapter')
      expect { strategy.snapshot }.to raise_error(NameError)
    end
  end

  # A backend the snapshot never captured - one that became available only
  # after the snapshot was taken - has no state to put back.
  describe '#restore with no snapshot' do
    let(:base_class) { ActiveRecordMock.sharded_base(configs: %w[primary]) }

    it 'is a no-op rather than a NoMethodError on nil' do
      expect { strategy.restore(nil) }.not_to raise_error
    end
  end

  # The native path is chosen by feature detection, never by Rails version, and
  # it needs EVERY method it is about to call. A base class carrying only part
  # of the shard API - a version check would happily call this one "6.1+" - has
  # to fall back instead of calling a method that is not there.
  describe 'a base class that carries only part of the native shard API' do
    let(:base_class) do
      ActiveRecordMock.sharded_base(configs: %w[primary shard_one], shards: %w[shard_one]).tap do |klass|
        klass.singleton_class.send(:undef_method, :connecting_to)
      end
    end

    it 'does not claim the shard is natively reachable' do
      expect(strategy).not_to be_native(:shard_one)
    end

    it 'falls back to establish_connection rather than calling the method it lacks' do
      strategy.apply(:shard_one)
      expect(base_class.connection_pool.db_config.name).to eq('shard_one')
    end
  end

  # `sql_base_class` can be pointed at a class that resolves but is not an
  # ActiveRecord base, in which case there is nothing to describe.
  describe 'a base class that is not ActiveRecord at all' do
    let(:base_class) { Class.new }

    it 'describes no pool instead of raising NoMethodError' do
      expect(strategy.pool_details).to eq({})
    end
  end
end
