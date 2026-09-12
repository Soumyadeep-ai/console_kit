# frozen_string_literal: true

require_relative '../mocks/active_record'
require_relative '../mocks/redis'

# Backends wired the way the real client libraries behave, for the invariant
# specs (concurrency, failure injection, sequences, nesting).
#
# The suite's shared mocks are built for single-threaded handler specs, so two
# of them store state on the class where the real library stores it per thread.
# Reusing them for a concurrency proof would fake away the only isolation
# ConsoleKit actually relies on, so the per-thread shapes are rebuilt here:
#
#   ShardedBase       - `connected_to_stack` per thread, as Rails 6.1+ keeps it.
#   ThreadedMongoid   - `Mongoid::Threaded` overrides per thread, as Mongoid does.
#   isolated_context_class - a context object that stores its attributes per thread.
#
# Everything else is deliberately left process-global, because that is what the
# real thing is: `establish_connection` replaces a process-wide pool,
# `Redis.current` is a process-wide singleton and `Elasticsearch::Model
# .index_name_prefix` is one process-wide attribute.
module TenantBackends
  ENV_NAME = 'test'
  OWNER = 'ApplicationRecord'
  CONFIGS = %w[primary shard_acme shard_globex shard_initech].freeze

  ATTRIBUTES = %i[partner_identifier tenant_shard tenant_mongo_db tenant_redis_db
                  tenant_elasticsearch_prefix].freeze

  TENANTS = {
    'acme' => { constants: { shard: 'shard_acme', mongo_db: 'acme_db', partner_code: 'ACME',
                             redis_db: 2, elasticsearch_prefix: 'acme_es' } },
    'globex' => { constants: { shard: 'shard_globex', mongo_db: 'globex_db', partner_code: 'GBX',
                               redis_db: 3, elasticsearch_prefix: 'globex_es' } },
    'initech' => { constants: { shard: 'shard_initech', mongo_db: 'initech_db', partner_code: 'INI',
                                redis_db: 4, elasticsearch_prefix: 'initech_es' } }
  }.freeze

  # Identities every backend reads back when no tenant is applied.
  DEFAULT_IDENTITIES = { sql: 'default', mongo: nil, redis: 0, elasticsearch: nil }.freeze

  # A shard-aware base class whose `connected_to_stack` is per thread, which is
  # where Rails 6.1+ keeps it. ActiveRecordMock::Base keeps it in a class ivar.
  class ShardedBase < ActiveRecordMock::Base
    STACK_KEY = :tenant_backends_connected_to_stack

    class << self
      # A THREAD variable, which is where Rails keeps `:ar_connected_to_stack`.
      # `Thread.current[]` would be fiber-local and would fake away the scope
      # ConsoleKit's own bookkeeping has to agree with.
      def connected_to_stack
        Thread.current.thread_variable_get(STACK_KEY) || Thread.current.thread_variable_set(STACK_KEY, [])
      end
    end
  end

  # `Redis.current` stand-in that counts the commands only :full diagnostics
  # issue, so :basic can be proven network-free.
  class CountingRedis < RedisFakes::DbReader
    attr_reader :commands

    def initialize(db = 0)
      super
      @commands = 0
    end

    def ping
      @commands += 1
      super
    end

    def info
      @commands += 1
      super
    end
  end

  # Mongoid stand-in that keeps its overrides per thread, the way the real
  # Mongoid::Threaded does, and counts the database commands the handler issues.
  module ThreadedMongoid
    CLIENT_KEY = :tenant_backends_mongo_client
    DATABASE_KEY = :tenant_backends_mongo_database

    # Mongo database stand-in counting every command sent to it.
    class Database
      class << self
        attr_accessor :commands
      end
      self.commands = 0

      attr_reader :name

      def initialize(name) = @name = name

      def command(*)
        self.class.commands += 1
        [{ 'version' => '7.0.0' }]
      end
    end

    # Mongo client stand-in exposing the effective client and database names.
    class Client
      attr_reader :name, :database

      def initialize(name, database_name)
        @name = name.to_s
        @database = Database.new(database_name.to_s)
      end
    end

    # Per-thread override slots.
    module Threaded
      class << self
        def client_override = Thread.current[CLIENT_KEY]

        def client_override=(value)
          Thread.current[CLIENT_KEY] = value
        end

        def database_override = Thread.current[DATABASE_KEY]

        def database_override=(value)
          Thread.current[DATABASE_KEY] = value
        end
      end
    end

    # Named-client registry, consulted by MongoConnectionHandler#named_client?.
    module Config
      class << self
        attr_accessor :clients
      end
      self.clients = {}
    end

    class << self
      def override_client(name)
        Threaded.client_override = name
      end

      def override_database(name)
        Threaded.database_override = name
      end

      def default_client
        Client.new(Threaded.client_override || 'default',
                   Threaded.database_override || Threaded.client_override || 'default')
      end

      def reset!
        Threaded.client_override = nil
        Threaded.database_override = nil
        Config.clients = {}
        Database.commands = 0
      end
    end
  end

  # A Mongoid predating client/database overrides. Its per-thread slots stay
  # readable, so a spec can still prove a rejected #prepare mutated nothing.
  module OverridelessMongoid
    Threaded = ThreadedMongoid::Threaded
    Config = ThreadedMongoid::Config
  end

  class << self
    # A shard-aware base class with every configuration in CONFIGS registered
    # both as a database configuration and as a native shard.
    def sharded_base
      klass = Class.new(ShardedBase)
      klass.env_name = ENV_NAME
      klass.configurations = ActiveRecordMock.configurations(CONFIGS, ENV_NAME)
      klass.connection_handler = ActiveRecordMock::ConnectionHandler.new
      klass.connection_specification_name = OWNER
      register_pools(klass)
      klass
    end

    # A context object of the shape almost every application ships: plain
    # class-level accessors, and therefore PROCESS-GLOBAL.
    def shared_context_class
      Class.new do
        class << self
          attr_accessor :partner_identifier, :tenant_shard, :tenant_mongo_db,
                        :tenant_redis_db, :tenant_elasticsearch_prefix
        end
      end
    end

    # A context object that stores its attributes per thread, which is what an
    # application has to do for ConsoleKit's context to be tenant-isolated.
    def isolated_context_class
      Class.new do
        class << self
          TenantBackends::ATTRIBUTES.each do |attr|
            key = :"tenant_backends_ctx_#{attr}"
            define_method(attr) { Thread.current[key] }
            define_method(:"#{attr}=") { |value| Thread.current[key] = value }
          end
        end
      end
    end

    # The live identity of every backend, read without mutating anything.
    def live_identities(base_class)
      {
        sql: base_class.current_shard.to_s,
        mongo: ::Mongoid::Threaded.database_override,
        redis: ::Redis.current.db_index,
        elasticsearch: ::Elasticsearch::Model.index_name_prefix
      }
    end

    # What every backend must read back once `key` is fully applied.
    def expected_identities(key)
      return DEFAULT_IDENTITIES if key.nil?

      constants = TENANTS.fetch(key)[:constants]
      { sql: constants[:shard], mongo: constants[:mongo_db],
        redis: constants[:redis_db], elasticsearch: constants[:elasticsearch_prefix] }
    end

    def live_context(context_class)
      ATTRIBUTES.to_h { |attr| [attr, context_class.public_send(attr)] }
    end

    def expected_context(key)
      return ATTRIBUTES.to_h { |attr| [attr, nil] } if key.nil?

      constants = TENANTS.fetch(key)[:constants]
      ConsoleKit::TenantConfigurator.context_mapping.transform_values { |name| constants[name] }
    end

    # Every piece of per-thread state these fakes keep. Threads die with their
    # own copies; the thread running the example needs it cleared by hand.
    def reset!
      Thread.current.thread_variable_set(ShardedBase::STACK_KEY, nil)
      ThreadedMongoid.reset!
      ATTRIBUTES.each { |attr| Thread.current[:"tenant_backends_ctx_#{attr}"] = nil }
    end

    private

    def register_pools(klass)
      configs = klass.configurations.configs_for(env_name: ENV_NAME)
      CONFIGS.each do |name|
        shard = name == CONFIGS.first ? :default : name.to_sym
        klass.connection_handler.register(OWNER, configs.find { |cfg| cfg.name == name },
                                          role: :writing, shard: shard)
      end
    end
  end
end
