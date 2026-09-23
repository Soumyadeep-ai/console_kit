# frozen_string_literal: true

require_relative '../../spec/support/mocks/active_record'
require_relative 'counters'

# Stateful, in-process stand-ins for the backends ConsoleKit talks to.
#
# WHY: the brief requires benchmarks to run with NO real DB/Redis/Mongo/
# Elasticsearch. These fakes model exactly the API surface each connection
# handler touches (see lib/console_kit/connections/*.rb) and nothing else,
# so `available_handlers` finds all four backends "available" without a
# single socket ever opening. Every operation a real client would perform as
# a network round trip (a PING, a cluster health check, a Mongo command)
# increments ConsoleKitBenchmark::Counters so the benchmarks can prove how
# many of those actually happen per switch - the headline claim is "zero
# network calls per switch", and a claim like that is worthless unless
# something is actually counting.
#
# SQL is the exception: the spec suite's ActiveRecord stand-in already keeps
# those counts (`connection.statements`, `pool.disconnects`,
# `handler.disconnects`), so it is reused here and the benchmarks read its
# numbers directly.
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
    #
    # They are named constants because `sql_base_class` is configured by name
    # and resolved with `safe_constantize`.
    module Sql
      CONFIGS = %w[primary shard_acme shard_globex shard_initech].freeze

      # Every CONFIGS entry is both a database.yml config and a native
      # `connects_to shards:` shard, so SqlStrategy takes the connecting_to path.
      NativeBase = ActiveRecordMock.sharded_base(configs: CONFIGS, shards: CONFIGS.drop(1))

      # No native shard API, so only the establish_connection fallback is
      # reachable.
      FallbackBase = ActiveRecordMock.plain_base(configs: CONFIGS)
    end

    # --- Mongoid -------------------------------------------------------------
    module MongoFake
      # Counts every #command call - the only network-style operation :full
      # diagnostics perform against Mongo.
      class Database
        attr_reader :name

        def initialize(name) = @name = name

        def command(*)
          Counters[:mongo_command] += 1
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
          Counters[:redis_ping] += 1
          'PONG'
        end

        def info
          Counters[:redis_info] += 1
          { 'redis_version' => '7.0.0', 'used_memory_human' => '1.00M' }
        end
      end
    end

    # --- Elasticsearch -----------------------------------------------------
    module ElasticsearchFake
      # Counts every #health call.
      class Cluster
        def health
          Counters[:es_cluster_health] += 1
          { 'cluster_name' => 'bench-cluster', 'status' => 'green' }
        end
      end

      # Counts every #ping call. Returns the running count rather than a bare
      # boolean; the handler only cares that this does not raise.
      class Client
        def cluster = @cluster ||= Cluster.new
        def ping = Counters[:es_ping] += 1
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
