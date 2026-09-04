# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'probe' do
  let(:context_class) do
    Class.new do
      class << self
        attr_accessor :tenant_shard, :tenant_mongo_db, :tenant_redis_db,
                      :tenant_elasticsearch_prefix, :partner_identifier
      end
    end
  end

  before do
    ConsoleKit.configure do |c|
      c.tenants = {
        'acme' => { constants: { shard: 'shard_acme', mongo_db: 'acme_db', partner_code: 'ACME',
                                 redis_db: 2, elasticsearch_prefix: 'acme_es' } }
      }
      c.context_class = context_class
      c.pretty_output = false
    end
    stub_const('ApplicationRecord', ActiveRecordMock.plain_base(configs: %w[primary shard_acme shard_globex]))
    ConsoleKit::Output.silent = true
  end

  it 'probes Object#try' do
    warn "TRY DEFINED: #{StandardError.new('x').respond_to?(:try)}"
    warn "HANDLERS: #{ConsoleKit::Connections::ConnectionManager.available_handlers(context_class).map(&:backend_key).inspect}"
    ConsoleKit.switch_tenant('acme')
    warn "STATE: #{ConsoleKit::StateStore.current.to_h.inspect}"
    warn "CTX: #{context_class.tenant_shard} #{context_class.tenant_mongo_db} #{context_class.tenant_redis_db} #{context_class.tenant_elasticsearch_prefix} #{context_class.partner_identifier}"
    warn "AR: #{ApplicationRecord.connection_pool.db_config.name}"
    warn "REDIS: #{Redis.current.db_index} ES: #{Elasticsearch::Model.index_name_prefix} MONGO: #{Mongoid::Threaded.database_override.inspect}"
  end

  it 'probes snapshot raising (undo nil path)' do
    allow(Mongoid::Threaded).to receive(:database_override).and_raise(ArgumentError, 'boom snapshot')
    err = begin
      ConsoleKit.switch_tenant('acme')
      nil
    rescue StandardError => e
      e
    end
    warn "SNAPSHOT-RAISE => #{err.class}: #{err.message[0, 200]}"
  end

  it 'probes prepare failure class' do
    allow_any_instance_of(ConsoleKit::Connections::MongoConnectionHandler).to receive(:prepare).and_raise(ConsoleKit::UnsupportedBackendError, 'nope')
    err = begin
      ConsoleKit.switch_tenant('acme')
      nil
    rescue StandardError => e
      e
    end
    warn "PREPARE-FAIL => #{err.class}: #{err.message[0, 200]}"
  end

  it 'probes connect failure wrapping' do
    allow_any_instance_of(ConsoleKit::Connections::MongoConnectionHandler).to receive(:connect!).and_raise(ConsoleKit::ConnectionError.new('mongo down', backend: 'MongoDB', operation: :connect))
    err = begin
      ConsoleKit.switch_tenant('acme')
      nil
    rescue StandardError => e
      e
    end
    warn "CONNECT-FAIL => #{err.class}\n#{err.message}"
    warn "ROLLBACK OK? #{err.rollback_succeeded?} FROM=#{err.from_tenant.inspect} TO=#{err.to_tenant.inspect} BACKEND=#{err.backend.inspect}"
    warn "AFTER CTX: #{context_class.tenant_shard.inspect} AR: #{ApplicationRecord.connection_pool.db_config.name}"
  end

  it 'probes rollback failure' do
    allow_any_instance_of(ConsoleKit::Connections::MongoConnectionHandler).to receive(:connect!).and_raise(StandardError, 'root cause here')
    allow_any_instance_of(ConsoleKit::Connections::RedisConnectionHandler).to receive(:restore).and_raise(StandardError, 'restore exploded')
    err = begin
      ConsoleKit.switch_tenant('acme')
      nil
    rescue StandardError => e
      e
    end
    warn "ROLLBACK-FAIL => #{err.class}\n#{err.message}"
    warn "FAILURES: #{err.rollback_failures.inspect}"
  end

  it 'probes handler order' do
    warn "ORDER: #{ConsoleKit::Connections::ConnectionManager.available_handlers(context_class).map(&:display_name).inspect}"
  end
end
