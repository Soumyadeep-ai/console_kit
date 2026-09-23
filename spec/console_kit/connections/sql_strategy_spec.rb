# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ConsoleKit::Connections::SqlStrategy do
  subject(:strategy) { described_class.new(base_class) }

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

    it 'removes the pool it established when the switch is rolled back' do
      state = strategy.snapshot
      strategy.apply(:shard_one)
      strategy.restore(state)
      expect { base_class.connection_pool }.to raise_error(ActiveRecordMock::ConnectionNotEstablished)
    end
  end

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

  describe '#restore with no snapshot' do
    let(:base_class) { ActiveRecordMock.sharded_base(configs: %w[primary]) }

    it 'is a no-op rather than a NoMethodError on nil' do
      expect { strategy.restore(nil) }.not_to raise_error
    end
  end

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

  describe 'a base class that is not ActiveRecord at all' do
    let(:base_class) { Class.new }

    it 'describes no pool instead of raising NoMethodError' do
      expect(strategy.pool_details).to eq({})
    end
  end
end
