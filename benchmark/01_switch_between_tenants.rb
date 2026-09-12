# frozen_string_literal: true

# WHAT: throughput of ConsoleKit.switch_tenant alternating between two
# different, fully-configured tenants (all four backends), on the native SQL
# shard path.
#
# WHY: this is the everyday console workflow - an operator hopping between
# tenants to reproduce something - and the brief requires it be measured, not
# guessed. Timings here are indicative only (single laptop, no warmup
# isolation from other processes); run this file more than once and compare
# variance before trusting any specific number.

require 'benchmark/ips'
require_relative 'support/setup'

ConsoleKitBenchmark::Setup.configure_native!
tenants = %w[acme globex].cycle

ConsoleKit::Output.silence do
  Benchmark.ips do |x|
    x.config(time: 2, warmup: 1)
    x.report('switch_tenant (alternating acme/globex, native shard path)') do
      ConsoleKit.switch_tenant(tenants.next)
    end
  end
end
