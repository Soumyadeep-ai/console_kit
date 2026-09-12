# frozen_string_literal: true

# WHAT: object allocations per switch, measured via
# `GC.stat(:total_allocated_objects)` deltas over N iterations (a monotonic
# counter unaffected by collection, unlike ObjectSpace.count_objects) -
# alternating between two tenants, and repeating the same tenant.
#
# WHY: the brief asks for allocation pressure to be measured directly rather
# than inferred from timings. GC noise averages out over enough iterations;
# it does not average out over one.

require_relative 'support/setup'

ITERATIONS = 5_000

def allocations_per_call(iterations, &)
  GC.start
  before = GC.stat(:total_allocated_objects)
  iterations.times(&)
  after = GC.stat(:total_allocated_objects)
  (after - before) / iterations.to_f
end

ConsoleKitBenchmark::Setup.configure_native!

ConsoleKit::Output.silence do
  ConsoleKit.switch_tenant('acme') # warm constant/method caches before measuring

  tenants = %w[acme globex].cycle
  alternating = allocations_per_call(ITERATIONS) { ConsoleKit.switch_tenant(tenants.next) }

  same_tenant = allocations_per_call(ITERATIONS) { ConsoleKit.switch_tenant('acme') }

  puts
  puts "Allocations per switch, averaged over #{ITERATIONS} iterations:"
  puts format('  %<label>-46s %<count>.1f objects/switch',
              label: 'alternating between two tenants', count: alternating)
  puts format('  %<label>-46s %<count>.1f objects/switch',
              label: 'repeated switch to the SAME tenant', count: same_tenant)
end
