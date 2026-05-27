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
      bench = build_benchmarker
      bench.start_memory_tracking
      run_steps(bench) || finish(bench)
    end

    private

    def build_benchmarker
      @ctx.config.benchmark ? Benchmarker.new : NullBenchmarker.new
    end

    def run_steps(bench)
      @ctx.config.pipeline_steps.each do |step_class|
        name   = step_class.name&.split('::')&.last || step_class.to_s
        result = bench.wrap(name) { step_class.new(@ctx).call }
        return Result.new(success: false, error: result.error) if result.failure?
      end
      nil
    end

    def finish(bench)
      resolved = @ctx.resolved_tenant
      bench.report(resolved)
      Result.new(success: true, tenant: resolved)
    end
  end
end
