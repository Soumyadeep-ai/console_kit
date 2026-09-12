# frozen_string_literal: true

# WHAT: actual `establish_connection` / `disconnect!` / `connecting_to` call
# COUNTS per switch, for the native shard path and the establish_connection
# fallback path, including a repeat switch to the SAME shard and a reset to
# default. These are exact counts from the fake's ConnectionHandler/Pool -
# not timings, and not sampled.
#
# WHY: 1.5.0's CHANGELOG claims "switching to the shard already in use
# performs no pool work" and that the native path "touches no connection
# pool" at all. Counts, not timings, are the only honest way to prove or
# disprove a claim like that - a millisecond difference on a laptop proves
# nothing, an extra `establish_connection` call is unambiguous. THIS is the
# headline result of the whole benchmark suite.

require_relative 'support/setup'
require_relative 'support/report'

KEYS = %i[sql_connecting_to sql_establish_connection sql_disconnect].freeze

ConsoleKit::Output.silence do
  # --- Native shard path (connecting_to) ----------------------------------
  ConsoleKitBenchmark::Setup.configure_native!
  ConsoleKit.switch_tenant('acme') # land on acme; not measured, just a starting point

  ConsoleKitBenchmark::Report.title('Native shard path (SqlStrategy#apply_native, via connecting_to)')
  ConsoleKitBenchmark::Report.count_delta('repeat switch to SAME shard (acme -> acme)', KEYS) do
    ConsoleKit.switch_tenant('acme')
  end
  ConsoleKitBenchmark::Report.count_delta('switch to a DIFFERENT shard (acme -> globex)', KEYS) do
    ConsoleKit.switch_tenant('globex')
  end
  ConsoleKitBenchmark::Report.count_delta('reset to default (globex -> nil)', KEYS) do
    ConsoleKit.switch_tenant(nil)
  end

  # --- establish_connection fallback path ---------------------------------
  ConsoleKitBenchmark::Setup.configure_fallback!
  ConsoleKit.switch_tenant('acme') # land on acme via the fallback path

  ConsoleKitBenchmark::Report.title('Fallback path (SqlStrategy#apply_fallback, via establish_connection)')
  ConsoleKitBenchmark::Report.count_delta('repeat switch to SAME shard (acme -> acme)', KEYS) do
    ConsoleKit.switch_tenant('acme')
  end
  ConsoleKitBenchmark::Report.count_delta('switch to a DIFFERENT shard (acme -> globex)', KEYS) do
    ConsoleKit.switch_tenant('globex')
  end
  ConsoleKitBenchmark::Report.count_delta('reset to default (globex -> nil)', KEYS) do
    ConsoleKit.switch_tenant(nil)
  end
end
