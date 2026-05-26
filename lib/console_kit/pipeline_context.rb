# lib/console_kit/pipeline_context.rb
# frozen_string_literal: true

module ConsoleKit
  # Value object passed through every step in the switch pipeline.
  class PipelineContext
    attr_accessor :resolved_tenant, :skip_selector, :scoped,
                  :shard_strategy, :resolved_shard, :shard_active,
                  :config

    def initialize(config:, requested_tenant: nil, scoped: false)
      @config          = config
      @resolved_tenant = requested_tenant
      @skip_selector   = !requested_tenant.nil?
      @scoped          = scoped
      @shard_strategy  = nil
      @resolved_shard  = nil
      @shard_active    = false
    end
  end
end
