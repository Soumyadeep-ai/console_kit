# frozen_string_literal: true

require_relative 'tenant_backends'

# Drivers for the shared 'a connection handler' examples: one per shipped
# backend, each exposing the same network-free probes.
#
# A subject owns its own fakes so the contract can also assert that switching
# one backend leaves the other three alone.
module HandlerContract
  # Shared plumbing: a fresh shard-aware base class and a fresh context object,
  # plus the identities of the three backends this subject does NOT own.
  class Subject
    attr_reader :handler, :base_class, :context_class

    def initialize
      @base_class = TenantBackends.sharded_base
      @context_class = TenantBackends.shared_context_class
      @handler = handler_class.new(@context_class)
    end

    def unrelated_identities
      TenantBackends.live_identities(base_class).except(handler.backend_key)
    end
  end

  # SQL, driven through Rails' native shard stack.
  class Sql < Subject
    def handler_class = ConsoleKit::Connections::SqlConnectionHandler
    def target = :shard_acme
    def previous_target = :shard_globex
    def default_identity = :default
    def identity = base_class.current_shard
    def network_calls = base_class.connection.statements.size
    def corrupt! = base_class.connecting_to(shard: :shard_initech, role: :writing)

    def mutation_probe
      [base_class.current_shard, base_class.connected_to_stack.size,
       base_class.connection_handler.disconnects]
    end
  end

  # MongoDB, driven through Mongoid's per-thread database override.
  class Mongo < Subject
    def handler_class = ConsoleKit::Connections::MongoConnectionHandler
    def target = 'acme_db'
    def previous_target = 'globex_db'
    def default_identity = 'default'
    def identity = ::Mongoid.default_client.database.name
    def network_calls = TenantBackends::ThreadedMongoid::Database.commands
    def corrupt! = ::Mongoid.override_database('foreign_db')

    def mutation_probe
      [::Mongoid::Threaded.client_override, ::Mongoid::Threaded.database_override]
    end
  end

  # Redis, driven through SELECT on the process-wide client.
  class Redis < Subject
    def handler_class = ConsoleKit::Connections::RedisConnectionHandler
    def target = 2
    def previous_target = 3
    def default_identity = 0
    def identity = ::Redis.current.db_index
    def network_calls = ::Redis.current.commands
    def corrupt! = ::Redis.current.select(9)
    def mutation_probe = ::Redis.current.selects.dup
  end

  # Elasticsearch, driven through the process-wide index name prefix.
  class Elasticsearch < Subject
    def handler_class = ConsoleKit::Connections::ElasticsearchConnectionHandler
    def target = 'acme_es'
    def previous_target = 'globex_es'
    def default_identity = nil
    def identity = ::Elasticsearch::Model.index_name_prefix
    def corrupt! = ::Elasticsearch::Model.index_name_prefix = 'foreign_es'

    def network_calls
      client = ::Elasticsearch::Model.client
      client.ping_calls + client.cluster.health_calls
    end

    def mutation_probe
      [::Elasticsearch::Model.index_name_prefix,
       ConsoleKit::Connections::ElasticsearchPrefixRegistry.current]
    end
  end
end

# Installs every backend fake, so a handler contract can prove it touched only
# its own backend.
RSpec.shared_context 'with every backend fake installed' do
  before do
    stub_const('ApplicationRecord', contract.base_class)
    stub_const('Mongoid', TenantBackends::ThreadedMongoid)
    Redis.current = TenantBackends::CountingRedis.new
    ConsoleKit::Output.silent = true
    ConsoleKit.configuration.sql_base_class = 'ApplicationRecord'
  end

  after { TenantBackends.reset! }
end

RSpec.shared_context 'with the SQL handler contract' do
  include_context 'with every backend fake installed'

  let(:contract) { HandlerContract::Sql.new }

  def prepare_invalid_target = :nowhere

  def hide_contract_dependency!
    ConsoleKit.configuration.sql_base_class = 'NoSuchBaseClass'
  end
end

RSpec.shared_context 'with the MongoDB handler contract' do
  include_context 'with every backend fake installed'

  let(:contract) { HandlerContract::Mongo.new }

  # Mongoid validates no database name, so the target it cannot apply is any
  # target on a Mongoid version without the override API.
  def prepare_invalid_target
    stub_const('Mongoid', TenantBackends::OverridelessMongoid)
    contract.target
  end

  def hide_contract_dependency!
    hide_const('Mongoid')
  end
end

RSpec.shared_context 'with the Redis handler contract' do
  include_context 'with every backend fake installed'

  let(:contract) { HandlerContract::Redis.new }

  def prepare_invalid_target = -1

  def hide_contract_dependency!
    hide_const('Redis')
  end
end

RSpec.shared_context 'with the Elasticsearch handler contract' do
  include_context 'with every backend fake installed'

  let(:contract) { HandlerContract::Elasticsearch.new }

  def prepare_invalid_target = 'Acme'

  def hide_contract_dependency!
    hide_const('Elasticsearch')
  end
end
