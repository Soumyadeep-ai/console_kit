# frozen_string_literal: true

require_relative '../../spec/support/mocks/active_record'
require_relative 'counters'

module ConsoleKitBenchmark
  module Fakes
    module Sql
      CONFIGS = %w[primary shard_acme shard_globex shard_initech].freeze

      NativeBase = ActiveRecordMock.sharded_base(configs: CONFIGS, shards: CONFIGS.drop(1))

      FallbackBase = ActiveRecordMock.plain_base(configs: CONFIGS)
    end

    module MongoFake
      class Database
        attr_reader :name

        def initialize(name) = @name = name

        def command(*)
          Counters[:mongo_command] += 1
          [{ 'version' => '7.0.0' }]
        end
      end

      class Client
        attr_reader :name, :database

        def initialize(name, database_name)
          @name = name.to_s
          @database = Database.new(database_name.to_s)
        end
      end
    end

    module RedisFake
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

    module ElasticsearchFake
      class Cluster
        def health
          Counters[:es_cluster_health] += 1
          { 'cluster_name' => 'bench-cluster', 'status' => 'green' }
        end
      end

      class Client
        def cluster = @cluster ||= Cluster.new
        def ping = Counters[:es_ping] += 1
      end
    end

    class << self
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
