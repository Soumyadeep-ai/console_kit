# lib/console_kit/connections/shard_resolver.rb
# frozen_string_literal: true

module ConsoleKit
  module Connections
    # Resolves the shard name for a given tenant key by reading the
    # tenant's `:constants -> :shard` value, falling back to the
    # configured `default_shard` when no shard mapping is found.
    class ShardResolver
      def initialize(config)
        @config = config
      end

      def resolve(tenant_key)
        @config.tenants&.dig(tenant_key, :constants, :shard) || @config.default_shard
      end
    end
  end
end
