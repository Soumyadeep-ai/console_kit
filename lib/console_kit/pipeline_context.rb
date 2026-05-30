# lib/console_kit/pipeline_context.rb
# frozen_string_literal: true

module ConsoleKit
  # Value object passed through every step in the switch pipeline.
  class PipelineContext
    # Groups shard-related state to reduce the number of instance variables on PipelineContext.
    ShardState = Struct.new(:strategy, :resolved_shard, :active, keyword_init: true)

    # Groups immutable switch options to reduce the number of instance variables on PipelineContext.
    SwitchOptions = Struct.new(:config, :scoped, keyword_init: true)

    attr_accessor :resolved_tenant, :skip_selector

    def initialize(config:, requested_tenant: nil, scoped: false)
      @options = SwitchOptions.new(config: config, scoped: scoped)
      @resolved_tenant = requested_tenant
      @skip_selector = requested_tenant ? true : false
      @shard_state = ShardState.new(strategy: nil, resolved_shard: nil, active: false)
    end

    def config
      @options.config
    end

    def config=(val)
      @options.config = val
    end

    def scoped
      @options.scoped
    end

    def scoped=(val)
      @options.scoped = val
    end

    def shard_strategy
      @shard_state.strategy
    end

    def shard_strategy=(val)
      @shard_state.strategy = val
    end

    def resolved_shard
      @shard_state.resolved_shard
    end

    def resolved_shard=(val)
      @shard_state.resolved_shard = val
    end

    def shard_active
      @shard_state.active
    end

    def shard_active=(val)
      @shard_state.active = val
    end
  end
end
