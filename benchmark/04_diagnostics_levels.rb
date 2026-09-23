# frozen_string_literal: true

# WHAT: `dashboard` / `Diagnostics.run` at `level: :basic` vs `level: :full`,
# each cold (cache forced empty every call) and cached (warmed once, then
# read back within the 2-second TTL - see Diagnostics::CACHE_TTL_SECONDS).
#
# WHY: 1.5.0's whole diagnostics pitch is "basic never touches the network,
# and a cache protects `full` from being hammered". This is where that claim
# either holds up or doesn't. The "cached" cases deliberately do NOT use
# benchmark-ips' auto-scaling duration: ips can run for several seconds,
# which would silently cross the 2s TTL mid-measurement and turn a "cached"
# run into a mix of cached and cold calls. Instead they run a small, fixed
# iteration count timed with Benchmark.realtime, comfortably inside the TTL
# window (printed below so that isn't just asserted).
#
# Network-op counts (SQL statements, mongo_command, redis_ping/info, es_ping/
# es_cluster_health) prove the cache claim directly: a cached call must add
# ZERO to them.

require 'benchmark'
require 'benchmark/ips'
require_relative 'support/setup'
require_relative 'support/report'

NETWORK_KEYS = %i[mongo_command redis_ping redis_info es_ping es_cluster_health].freeze
CACHED_ITERATIONS = 2_000
STATEMENTS = ConsoleKitBenchmark::Fakes::Sql::NativeBase.connection.statements

ConsoleKitBenchmark::Setup.configure_native!
ConsoleKit::Output.silence { ConsoleKit.switch_tenant('acme') }

dashboard = ConsoleKit::Connections::Dashboard
diagnostics = ConsoleKit::Diagnostics

ConsoleKitBenchmark::Report.title('Timing: cold (cache cleared every call)')
ConsoleKit::Output.silence do
  Benchmark.ips do |x|
    x.config(time: 2, warmup: 1)
    x.report(':basic, cold') do
      diagnostics.clear_cache!
      dashboard.display(level: :basic)
    end
    x.report(':full, cold') do
      diagnostics.clear_cache!
      dashboard.display(level: :full)
    end
  end
end

ConsoleKitBenchmark::Report.title('Timing: cached (warmed once, read back inside the 2s TTL)')
ConsoleKit::Output.silence do
  diagnostics.clear_cache!
  dashboard.display(level: :basic) # warm
  elapsed = Benchmark.realtime { CACHED_ITERATIONS.times { dashboard.display(level: :basic) } }
  puts format('  :basic, cached  %<ips>10.0f ips  (%<n>d calls in %<secs>.4fs, TTL is 2.0s)',
              ips: CACHED_ITERATIONS / elapsed, n: CACHED_ITERATIONS, secs: elapsed)

  diagnostics.clear_cache!
  dashboard.display(level: :full) # warm
  elapsed = Benchmark.realtime { CACHED_ITERATIONS.times { dashboard.display(level: :full) } }
  puts format('  :full, cached   %<ips>10.0f ips  (%<n>d calls in %<secs>.4fs, TTL is 2.0s)',
              ips: CACHED_ITERATIONS / elapsed, n: CACHED_ITERATIONS, secs: elapsed)
end

ConsoleKitBenchmark::Report.title('Network-op calls per `dashboard`, cold vs cached (headline: cached must add zero)')
ConsoleKit::Output.silence do
  diagnostics.clear_cache!
  ConsoleKitBenchmark::Report.count_delta('level: :basic, cold call', NETWORK_KEYS,
                                          statements: STATEMENTS) { dashboard.display(level: :basic) }
  ConsoleKitBenchmark::Report.count_delta('level: :basic, cached call (repeat, same tenant)', NETWORK_KEYS,
                                          statements: STATEMENTS) { dashboard.display(level: :basic) }

  diagnostics.clear_cache!
  ConsoleKitBenchmark::Report.count_delta('level: :full, cold call', NETWORK_KEYS,
                                          statements: STATEMENTS) { dashboard.display(level: :full) }
  ConsoleKitBenchmark::Report.count_delta('level: :full, cached call (repeat, same tenant)', NETWORK_KEYS,
                                          statements: STATEMENTS) { dashboard.display(level: :full) }
end
