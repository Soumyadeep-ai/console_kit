# frozen_string_literal: true

require 'spec_helper'

# What "thread safe" actually means for ConsoleKit, proved rather than claimed.
#
# ConsoleKit invents no isolation of its own. It keeps its own bookkeeping per
# thread and then writes through whatever handle the application's client
# library hands it, so a backend is tenant-isolated exactly as far as that
# library is. These examples prove both halves: the isolation that is real, and
# the leakage that is real and documented.
#
# Every hand-off between threads is a Queue pop, never a sleep, and every thread
# is joined inside the example that started it.
module Concurrency
end

RSpec.describe Concurrency do
  include_context 'with a four-backend tenant setup'

  let(:switcher) { InterleavedSwitch.new { observable_state } }
  let(:readings) { switcher.run(switch_to('acme'), switch_to('globex')) }

  def switch_to(key) = -> { ConsoleKit.switch_tenant(key) }

  describe 'ConsoleKit bookkeeping, which is per thread' do
    it 'leaves thread A reporting its own tenant key' do
      expect(readings[:a][:tenant]).to eq('acme')
    end

    it 'leaves thread B reporting its own tenant key' do
      expect(readings[:b][:tenant]).to eq('globex')
    end

    it 'gives thread A its own committed TenantState' do
      expect(readings[:a][:tenant]).not_to eq(readings[:b][:tenant])
    end

    it 'leaves the thread that never switched with no tenant at all' do
      readings
      expect(ConsoleKit.current_tenant).to be_nil
    end

    it 'leaves the thread that never switched unconfigured' do
      readings
      expect(ConsoleKit::StateStore).not_to be_configured
    end

    it 'leaves no switching thread alive' do
      readings
      expect(switcher.threads.map(&:alive?)).to eq([false, false])
    end
  end

  describe 'SQL on the native shard path, which Rails keeps per thread' do
    it 'keeps thread A on its own shard' do
      expect(readings[:a][:identities][:sql]).to eq('shard_acme')
    end

    it 'keeps thread B on its own shard' do
      expect(readings[:b][:identities][:sql]).to eq('shard_globex')
    end

    it 'still verifies thread A against its own shard afterwards' do
      readings
      expect(ConsoleKit::Connections::SqlConnectionHandler.new(context_class).verify!(nil)).to be(true)
    end
  end

  describe 'SQL on the establish_connection path, which Rails keeps per process' do
    let(:base_class) { ActiveRecordMock.plain_base(configs: TenantBackends::CONFIGS) }
    let(:switcher) { InterleavedSwitch.new { base_class.connection_pool.db_config.name } }

    it 'moves thread B onto its own configuration' do
      expect(readings[:b]).to eq('shard_globex')
    end

    it 'leaks the last writer into thread A, because the pool is process-wide' do
      expect(readings[:a]).to eq('shard_globex')
    end
  end

  describe 'Mongoid overrides, which Mongoid keeps per thread' do
    it 'keeps thread A on its own database' do
      expect(readings[:a][:identities][:mongo]).to eq('acme_db')
    end

    it 'keeps thread B on its own database' do
      expect(readings[:b][:identities][:mongo]).to eq('globex_db')
    end

    it 'leaves the thread that never switched with no override' do
      readings
      expect(Mongoid::Threaded.database_override).to be_nil
    end
  end

  describe 'Redis with a process-global client (documented leakage, NOT isolation)' do
    it 'reports the isolation model honestly' do
      expect(ConsoleKit::Connections::RedisConnectionHandler.new(context_class).isolation_model)
        .to eq(:process_global)
    end

    it 'refuses to claim thread isolation' do
      expect(ConsoleKit::Connections::RedisConnectionHandler.new(context_class)).not_to be_thread_isolated
    end

    it 'moves thread B onto its own DB' do
      expect(readings[:b][:identities][:redis]).to eq(3)
    end

    it 'leaks thread B\'s DB into thread A, which shares the one client' do
      expect(readings[:a][:identities][:redis]).to eq(3)
    end
  end

  describe 'Redis with a per-thread client, where isolation is real' do
    before { stub_const('Redis', RedisFakes::ThreadLocalRedis) }

    it 'reports the isolation model as scoped' do
      expect(ConsoleKit::Connections::RedisConnectionHandler.new(context_class).isolation_model).to eq(:scoped)
    end

    it 'keeps thread A on its own DB' do
      expect(readings[:a][:identities][:redis]).to eq(2)
    end

    it 'keeps thread B on its own DB' do
      expect(readings[:b][:identities][:redis]).to eq(3)
    end
  end

  describe 'Elasticsearch, which is process-global by construction' do
    it 'reports the isolation model honestly' do
      expect(ConsoleKit::Connections::ElasticsearchConnectionHandler.new(context_class).isolation_model)
        .to eq(:process_global)
    end

    it 'refuses to claim thread isolation' do
      expect(ConsoleKit::Connections::ElasticsearchConnectionHandler.new(context_class)).not_to be_thread_isolated
    end

    it 'moves thread B onto its own prefix' do
      expect(readings[:b][:identities][:elasticsearch]).to eq('globex_es')
    end

    it 'leaks thread B\'s prefix into thread A, because the setter is process-wide' do
      expect(readings[:a][:identities][:elasticsearch]).to eq('globex_es')
    end

    it 'still records what thread A asked for, so the conflict is detectable' do
      expect(readings[:a][:tenant]).to eq('acme')
    end
  end

  describe 'a context object with class-level attributes (process-global)' do
    it 'moves thread B onto its own shard value' do
      expect(readings[:b][:context][:tenant_shard]).to eq('shard_globex')
    end

    it 'leaks thread B\'s value into thread A, which shares the one object' do
      expect(readings[:a][:context][:tenant_shard]).to eq('shard_globex')
    end
  end

  describe 'a context object that stores its attributes per thread' do
    let(:context_class) { TenantBackends.isolated_context_class }

    it 'keeps thread A on its own partner code' do
      expect(readings[:a][:context][:partner_identifier]).to eq('ACME')
    end

    it 'keeps thread B on its own partner code' do
      expect(readings[:b][:context][:partner_identifier]).to eq('GBX')
    end

    it 'keeps thread A on its own shard value' do
      expect(readings[:a][:context][:tenant_shard]).to eq('shard_acme')
    end

    it 'leaves the thread that never switched with an untouched context' do
      readings
      expect(context_values).to eq(expected_context(nil))
    end
  end

  describe 'a failed switch on one thread' do
    let(:readings) { switcher.run(switch_to('acme'), -> { failed_switch('nonexistent') }) }

    it 'leaves the failing thread with no tenant' do
      expect(readings[:b][:tenant]).to be_nil
    end

    it 'leaves the succeeding thread on its own tenant' do
      expect(readings[:a][:tenant]).to eq('acme')
    end

    it 'never moves the succeeding thread off its own shard' do
      expect(readings[:a][:identities][:sql]).to eq('shard_acme')
    end
  end
end
