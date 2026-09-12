# frozen_string_literal: true

require_relative 'counters'

# Stateful, in-process stand-ins for the four backends ConsoleKit talks to.
#
# WHY: the brief requires benchmarks to run with NO real DB/Redis/Mongo/
# Elasticsearch. These fakes model exactly the API surface each connection
# handler touches (see lib/console_kit/connections/*.rb) and nothing else,
# so `available_handlers` finds all four backends "available" without a
# single socket ever opening. Every operation a real client would perform as
# a network round trip (a query, a PING, a cluster health check, a Mongo
# command) increments ConsoleKitBenchmark::Counters so the benchmarks can
# prove how many of those actually happen per switch - the headline claim
# is "zero network calls per switch", and a claim like that is worthless
# unless something is actually counting.
module ConsoleKitBenchmark
  # One fake per backend, plus the top-level constants that make each one
  # "available" to ConsoleKit's connection handlers.
  module Fakes
    # --- SQL ---------------------------------------------------------------
    #
    # Two base classes mirror the two paths SqlStrategy can take:
    #   NativeBase   - responds to connecting_to/connected_to_stack/etc, so
    #                  SqlStrategy prefers the native shard-switching path.
    #   FallbackBase - exposes only establish_connection, forcing the
    #                  database.yml fallback path.
    module Sql
      DbConfig = Struct.new(:env_name, :name, :adapter, keyword_init: true)

      # Stands in for the live JDBC/pg/mysql2 connection. #execute and
      # #select_value are the only two operations SqlConnectionHandler's
      # :full diagnostics perform - a plain switch never calls either.
      class Connection
        attr_reader :adapter_name

        def initialize(adapter_name: 'PostgreSQL')
          @adapter_name = adapter_name
        end

        def execute(_sql)
          Counters.increment(:sql_execute)
        end

        def select_value(_sql)
          Counters.increment(:sql_select_value)
          'PostgreSQL 16.1 on aarch64'
        end
      end

      # Connection pool bound to a single database configuration. Counts
      # every #disconnect! it is asked to perform.
      class Pool
        attr_reader :db_config, :size

        def initialize(db_config, size: 5)
          @db_config = db_config
          @size = size
        end

        def disconnect! = Counters.increment(:sql_disconnect)
      end

      # `database.yml` stand-in supporting the `configs_for(env_name:)` lookup.
      class Configurations
        def initialize(configs) = @configs = configs
        def configs_for(env_name:) = @configs.select { |c| c.env_name == env_name }
      end

      # Pools keyed by [owner, role, shard], exactly as ActiveRecord keys them.
      # Counts every #establish_connection call.
      class ConnectionHandler
        def initialize = @pools = {}

        def retrieve_connection_pool(owner, role:, shard:) = @pools[[owner, role, shard]]

        def register(owner, db_config, role:, shard:) = @pools[[owner, role, shard]] = Pool.new(db_config)

        # Mirrors ActiveRecord: replacing a pool disconnects the old one.
        def establish_connection(owner, db_config, role:, shard:)
          Counters.increment(:sql_establish_connection)
          @pools[[owner, role, shard]]&.disconnect!
          register(owner, db_config, role: role, shard: shard)
        end
      end

      # Shard-aware base class, mirroring Rails 6.1+ ActiveRecord::Base. Counts
      # every #connecting_to call.
      class NativeBase
        class << self
          attr_accessor :configurations, :connection_handler, :connection_specification_name, :env_name

          def default_shard = :default
          def default_role = :writing
          def connected_to_stack = @connected_to_stack ||= []

          def connecting_to(role: default_role, shard: default_shard, prevent_writes: false)
            Counters.increment(:sql_connecting_to)
            connected_to_stack << { role: role, shard: shard, prevent_writes: prevent_writes }
          end

          def current_shard = connected_to_stack.reverse_each.find { |e| e[:shard] }&.fetch(:shard) || default_shard
          def current_role = connected_to_stack.reverse_each.find { |e| e[:role] }&.fetch(:role) || default_role

          def connection_pool
            connection_handler.retrieve_connection_pool(
              connection_specification_name, role: current_role, shard: current_shard
            )
          end

          def establish_connection(config_name = nil)
            connection_handler.establish_connection(
              connection_specification_name, resolve_config(config_name), role: current_role, shard: current_shard
            )
          end

          def connection = @connection ||= Connection.new

          def resolve_config(config_name)
            env_configs = configurations.configs_for(env_name: env_name)
            name = (config_name || env_configs.first&.name).to_s
            env_configs.find { |c| c.name == name }
          end

          def reset_stack! = @connected_to_stack = []
        end
      end

      # A base class exposing none of Rails' native shard APIs, so only the
      # establish_connection fallback is reachable.
      class FallbackBase
        class << self
          attr_accessor :configurations, :env_name
          attr_reader :connection_pool

          def establish_connection(config_name = nil)
            Counters.increment(:sql_establish_connection)
            @connection_pool&.disconnect!
            @connection_pool = Pool.new(resolve_config(config_name))
          end

          def connection = @connection ||= Connection.new

          def resolve_config(config_name)
            env_configs = configurations.configs_for(env_name: env_name)
            name = (config_name || env_configs.first&.name).to_s
            env_configs.find { |c| c.name == name }
          end
        end
      end

      CONFIGS = %w[primary shard_acme shard_globex shard_initech].freeze

      class << self
        # A base class where every CONFIGS entry is registered as BOTH a
        # database.yml config and a native `connects_to shards:` shard, so
        # SqlStrategy takes the `connecting_to` path.
        def native_base
          klass = NativeBase
          klass.env_name = 'test'
          klass.configurations = test_configurations
          klass.connection_handler = ConnectionHandler.new
          klass.connection_specification_name = 'ApplicationRecord'
          klass.reset_stack!
          register_shards(klass)
          klass
        end

        # A base class with no native shard API: every CONFIGS entry is only
        # a database.yml config, so SqlStrategy falls back to
        # establish_connection.
        def fallback_base
          klass = FallbackBase
          klass.env_name = 'test'
          klass.configurations = test_configurations
          klass.establish_connection
          klass
        end

        private

        def test_configurations
          Configurations.new(CONFIGS.map { |name| DbConfig.new(env_name: 'test', name: name, adapter: 'postgresql') })
        end

        def register_shards(klass)
          CONFIGS.each do |name|
            shard = name == CONFIGS.first ? :default : name.to_sym
            klass.connection_handler.register('ApplicationRecord', config_for(klass, name),
                                              role: :writing, shard: shard)
          end
        end

        def config_for(klass, name)
          klass.configurations.configs_for(env_name: klass.env_name).find { |c| c.name == name }
        end
      end
    end

    # --- Mongoid -------------------------------------------------------------
    module MongoFake
      # Counts every #command call - the only network-style operation :full
      # diagnostics perform against Mongo.
      class Database
        attr_reader :name

        def initialize(name) = @name = name

        def command(*)
          Counters.increment(:mongo_command)
          [{ 'version' => '7.0.0' }]
        end
      end

      # Exposes the effective client/database names MongoConnectionHandler
      # reads back to prove a switch landed.
      class Client
        attr_reader :name, :database

        def initialize(name, database_name)
          @name = name.to_s
          @database = Database.new(database_name.to_s)
        end
      end
    end

    # --- Redis -----------------------------------------------------------
    module RedisFake
      # A client with a mutable logical DB (mutated by #select, exactly as a
      # real SELECT would) and counted #ping/#info calls.
      class Client
        attr_reader :db

        def initialize(db: 0)
          @db = db
        end

        def select(index)
          @db = index
          'OK'
        end

        def ping
          Counters.increment(:redis_ping)
          'PONG'
        end

        def info
          Counters.increment(:redis_info)
          { 'redis_version' => '7.0.0', 'used_memory_human' => '1.00M' }
        end
      end
    end

    # --- Elasticsearch -----------------------------------------------------
    module ElasticsearchFake
      # Counts every #health call.
      class Cluster
        def health
          Counters.increment(:es_cluster_health)
          { 'cluster_name' => 'bench-cluster', 'status' => 'green' }
        end
      end

      # Counts every #ping call. Returns the running count rather than a bare
      # boolean; the handler only cares that this does not raise.
      class Client
        def cluster = @cluster ||= Cluster.new
        def ping = Counters.increment(:es_ping)
      end
    end

    class << self
      # Wires up the top-level constants (Mongoid, Redis, Elasticsearch::Model)
      # every handler's #available? checks for. Idempotent.
      def install!
        install_mongoid!
        install_redis!
        install_elasticsearch!
      end

      private

      def install_mongoid!
        return if defined?(::Mongoid)

        Object.const_set(:Mongoid, mongoid_module)
        Mongoid.const_set(:Threaded, mongoid_threaded_module)
        Mongoid.const_set(:Config, mongoid_config_module)
      end

      def mongoid_module
        Module.new do
          class << self
            attr_accessor :client_override, :database_override

            def override_client(name) = self.client_override = name
            def override_database(name) = self.database_override = name

            def default_client
              MongoFake::Client.new(client_override || 'default', database_override || client_override || 'default')
            end
          end
        end
      end

      def mongoid_threaded_module
        Module.new do
          class << self
            def client_override = ::Mongoid.client_override
            def database_override = ::Mongoid.database_override
          end
        end
      end

      def mongoid_config_module
        Module.new { class << self; attr_accessor :clients; end }.tap { |mod| mod.clients = {} }
      end

      def install_redis!
        return if defined?(::Redis)

        redis = Class.new { class << self; attr_accessor :client; end }
        redis.client = RedisFake::Client.new
        redis.define_singleton_method(:current) { client }
        Object.const_set(:Redis, redis)
      end

      def install_elasticsearch!
        return if defined?(::Elasticsearch::Model)

        Object.const_set(:Elasticsearch, Module.new)
        Elasticsearch.const_set(:Model, elasticsearch_model_module)
      end

      def elasticsearch_model_module
        Module.new do
          class << self
            attr_accessor :index_name_prefix

            def client = @client ||= ElasticsearchFake::Client.new
          end
        end
      end
    end
  end
end
