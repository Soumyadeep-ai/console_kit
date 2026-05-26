# lib/console_kit/switch_pipeline.rb
# frozen_string_literal: true

require_relative 'pipeline_context'
require_relative 'steps/base'

module ConsoleKit
  # Orchestrates the ordered execution of configured pipeline steps,
  # halting at the first failing step.
  class SwitchPipeline
    # Final outcome of a pipeline run.
    Result = Struct.new(:success, :tenant, :error, keyword_init: true) do
      def success? = success
      def failure? = !success
    end

    class << self
      def run(tenant_key: nil, scoped: false, config: ConsoleKit.configuration)
        new(tenant_key: tenant_key, scoped: scoped, config: config).call
      end
    end

    def initialize(tenant_key:, scoped:, config:)
      @ctx = PipelineContext.new(
        config: config,
        requested_tenant: tenant_key,
        scoped: scoped
      )
    end

    def call
      @ctx.config.pipeline_steps.each do |step_class|
        result = step_class.new(@ctx).call
        return Result.new(success: false, error: result.error) if result.failure?
      end
      Result.new(success: true, tenant: @ctx.resolved_tenant)
    end
  end
end
