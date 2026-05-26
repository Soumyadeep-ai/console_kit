# lib/console_kit/scoped_switcher.rb
# frozen_string_literal: true

module ConsoleKit
  # Factory that selects the appropriate scoped-switcher implementation based
  # on whether Rails sharding is enabled and available at runtime.
  class ScopedSwitcher
    class << self
      def for(config)
        strategy = Connections::ShardStrategyFactory.build(config)
        if strategy.available?
          ShardedScopedSwitcher.new(config, strategy)
        else
          DefaultScopedSwitcher.new(config)
        end
      end
    end
  end

  # Non-sharded scoped switcher. Pushes the requested tenant onto the context
  # stack, runs the pipeline, yields, then pops the stack unconditionally —
  # even when the block raises — restoring the previous tenant context.
  class DefaultScopedSwitcher < ScopedSwitcher
    def initialize(config)
      super()
      @config = config
    end

    def with(tenant_key, &block)
      Context.push(tenant_key)
      SwitchPipeline.run(tenant_key: tenant_key, scoped: true, config: @config)
      block.call
    ensure
      previous = Context.pop
      SwitchPipeline.run(tenant_key: previous, scoped: true, config: @config) if previous
    end
  end

  # Sharded scoped switcher. Wraps the block inside the shard connection
  # context provided by the strategy, while still managing the tenant stack
  # the same way as DefaultScopedSwitcher.
  class ShardedScopedSwitcher < ScopedSwitcher
    def initialize(config, strategy)
      super()
      @config   = config
      @strategy = strategy
    end

    def with(tenant_key, &block)
      shard = resolve_shard(tenant_key)
      @strategy.wrap(shard, role: @config.shard_role) { scoped_run(tenant_key, &block) }
    end

    private

    def resolve_shard(tenant_key)
      Connections::ShardResolver.new(@config).resolve(tenant_key)
    end

    def scoped_run(tenant_key, &block)
      Context.push(tenant_key)
      SwitchPipeline.run(tenant_key: tenant_key, scoped: true, config: @config)
      block.call
    ensure
      previous = Context.pop
      SwitchPipeline.run(tenant_key: previous, scoped: true, config: @config) if previous
    end
  end
end
