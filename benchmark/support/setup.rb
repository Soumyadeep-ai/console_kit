# frozen_string_literal: true

require 'active_support/core_ext/object/try'
require 'console_kit'
require_relative 'fakes'
require_relative 'counters'
require_relative 'call_counting'

# Shared ConsoleKit configuration for every benchmark file. Every backend runs
# against the fakes in support/fakes.rb - no real DB/Redis/Mongo/Elasticsearch
# is ever touched.
module ConsoleKitBenchmark
  # Builds a ConsoleKit configuration wired against the fakes.
  module Setup
    TENANTS = {
      'acme' => { constants: { shard: 'shard_acme', mongo_db: 'acme_db', partner_code: 'ACME',
                               redis_db: 2, elasticsearch_prefix: 'acme_es' } },
      'globex' => { constants: { shard: 'shard_globex', mongo_db: 'globex_db', partner_code: 'GBX',
                                 redis_db: 3, elasticsearch_prefix: 'globex_es' } },
      'initech' => { constants: { shard: 'shard_initech', mongo_db: 'initech_db', partner_code: 'INI',
                                  redis_db: 4, elasticsearch_prefix: 'initech_es' } }
    }.freeze

    CONTEXT_ATTRIBUTES = %i[partner_identifier tenant_shard tenant_mongo_db
                            tenant_redis_db tenant_elasticsearch_prefix].freeze

    class << self
      # Default fixture: all four backends available, SQL on the native
      # `connecting_to` shard path. Used by benchmarks 1, 2, 4 and 5.
      def configure_native!(tenants: TENANTS)
        Fakes.install!
        Fakes::Sql.native_base
        apply(tenants, 'ConsoleKitBenchmark::Fakes::Sql::NativeBase')
      end

      # Same four backends, SQL forced onto the `establish_connection`
      # fallback path (the base class exposes no native shard API).
      def configure_fallback!(tenants: TENANTS)
        Fakes.install!
        Fakes::Sql.fallback_base
        apply(tenants, 'ConsoleKitBenchmark::Fakes::Sql::FallbackBase')
      end

      # SQL only: Mongoid/Redis/Elasticsearch::Model are deliberately never
      # defined in this process, so ConnectionManager.available_handlers finds
      # only the SQL backend. Used to isolate one backend's marginal cost from
      # the four-backends-together case in benchmark 3. Must run in its own
      # process (a script that never requires support/fakes' Mongo/Redis/ES
      # installers), since those constants cannot be "uninstalled" once defined.
      def configure_sql_only!(tenants: TENANTS)
        Fakes::Sql.native_base
        ConsoleKit.configure do |config|
          config.tenants = tenants
          config.context_class = sql_only_context_class
          config.sql_base_class = 'ConsoleKitBenchmark::Fakes::Sql::NativeBase'
          config.pretty_output = false
        end
        reset_tenant_state!
      end

      def context_class
        @context_class ||= build_context_class(CONTEXT_ATTRIBUTES)
      end

      def sql_only_context_class
        @sql_only_context_class ||= build_context_class(%i[partner_identifier tenant_shard])
      end

      def reset_tenant_state!
        ConsoleKit::StateStore.clear!
        ConsoleKit::Diagnostics.clear_cache!
        Counters.reset!
      end

      private

      def build_context_class(attrs)
        klass = Class.new
        klass.singleton_class.attr_accessor(*attrs)
        klass
      end

      def apply(tenants, sql_base_class)
        ConsoleKit.configure do |config|
          config.tenants = tenants
          config.context_class = context_class
          config.sql_base_class = sql_base_class
          config.pretty_output = false
        end
        reset_tenant_state!
      end
    end
  end
end
