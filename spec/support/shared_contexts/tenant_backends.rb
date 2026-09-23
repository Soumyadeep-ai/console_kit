# frozen_string_literal: true

require_relative '../mocks/active_record'
require_relative '../mocks/redis'

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

  DEFAULT_IDENTITIES = { sql: 'default', mongo: nil, redis: 0, elasticsearch: nil }.freeze

  class ShardedBase < ActiveRecordMock::Base
    STACK_KEY = :tenant_backends_connected_to_stack

    class << self
      def connected_to_stack
        Thread.current.thread_variable_get(STACK_KEY) || Thread.current.thread_variable_set(STACK_KEY, [])
      end
    end
  end

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

  module ThreadedMongoid
    CLIENT_KEY = :tenant_backends_mongo_client
    DATABASE_KEY = :tenant_backends_mongo_database

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

    class Client
      attr_reader :database

      def initialize(_name, database_name)
        @database = Database.new(database_name.to_s)
      end
    end

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

  module OverridelessMongoid
    Threaded = ThreadedMongoid::Threaded
    Config = ThreadedMongoid::Config
  end

  class << self
    def sharded_base
      klass = Class.new(ShardedBase)
      klass.env_name = ENV_NAME
      klass.configurations = ActiveRecordMock.configurations(CONFIGS, ENV_NAME)
      klass.connection_handler = ActiveRecordMock::ConnectionHandler.new
      klass.connection_specification_name = OWNER
      register_pools(klass)
      klass
    end

    def shared_context_class
      Class.new do
        class << self
          attr_accessor :partner_identifier, :tenant_shard, :tenant_mongo_db,
                        :tenant_redis_db, :tenant_elasticsearch_prefix
        end
      end
    end

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

    def live_identities(base_class)
      {
        sql: base_class.current_shard.to_s,
        mongo: ::Mongoid::Threaded.database_override,
        redis: ::Redis.current.db_index,
        elasticsearch: ::Elasticsearch::Model.index_name_prefix
      }
    end

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
