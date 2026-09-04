# frozen_string_literal: true

# WHAT: `ContextWrapper.for_context` (attribute detection, which scans
# `ctx.public_methods` and probes each handler's `#available?`) and
# `ContextWrapper#assign` (writing tenant constants onto the context object),
# in isolation from the rest of a tenant switch.
#
# WHY: `TenantSwitch` memoizes one ContextWrapper per switch (`@context_wrapper
# ||=`), so this is the cost of that first, memoized construction plus one
# assignment - i.e. the floor under every switch's "apply context" step,
# with connection work excluded.

require 'benchmark/ips'
require_relative 'support/setup'

ConsoleKitBenchmark::Setup.configure_native!

ctx = ConsoleKitBenchmark::Setup.context_class
constants = ConsoleKitBenchmark::Setup::TENANTS.fetch('acme')[:constants]
mapping = ConsoleKit::TenantConfigurator::CONTEXT_MAPPING

ConsoleKit::Output.silence do
  Benchmark.ips do |x|
    x.config(time: 2, warmup: 1)
    x.report('ContextWrapper.for_context (attribute detection only)') do
      ConsoleKit::TenantConfigurator::ContextWrapper.for_context(ctx)
    end
    x.report('for_context + assign (full context-setup step)') do
      ConsoleKit::TenantConfigurator::ContextWrapper.for_context(ctx).assign(constants, mapping)
    end
    x.compare!
  end
end
