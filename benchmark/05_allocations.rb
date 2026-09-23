# frozen_string_literal: true

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
  ConsoleKit.switch_tenant('acme')

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
