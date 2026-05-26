# lib/console_kit/steps/shard_connector.rb
# frozen_string_literal: true

require_relative 'base'

module ConsoleKit
  module Steps
    # Pipeline step that resolves and stores the shard strategy for the
    # current tenant. When Rails sharding is disabled or unavailable the
    # step is a no-op and simply returns success.
    class ShardConnector < Base
      register priority: 60

      def call
        strategy = Connections::ShardStrategyFactory.build(config)
        return success unless strategy.available?

        apply_shard(strategy)
      end

      private

      def apply_shard(strategy)
        shard = Connections::ShardResolver.new(config).resolve(ctx.resolved_tenant)
        ctx.shard_strategy = strategy
        ctx.resolved_shard = shard
        Output.print_info("Shard resolved: #{shard}")
        success
      end
    end
  end
end
