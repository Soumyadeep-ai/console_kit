# lib/console_kit/connections/shard_strategy_factory.rb
# frozen_string_literal: true

require_relative 'shard_strategy'

module ConsoleKit
  module Connections
    # Builds the appropriate ShardStrategy implementation based on the
    # current configuration. Returns a NullShardStrategy whenever Rails
    # sharding is disabled or unavailable at runtime.
    class ShardStrategyFactory
      class << self
        def build(config)
          return NullShardStrategy.new unless config.use_rails_sharding

          strategy = RailsConnectedToStrategy.new
          strategy.available? ? strategy : NullShardStrategy.new
        end
      end
    end
  end
end
