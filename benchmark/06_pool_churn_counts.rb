# frozen_string_literal: true

# WHAT: actual pool churn per switch - how many connection pools a switch
# disconnects and replaces - for the native shard path and the
# establish_connection fallback path, including a repeat switch to the SAME
# shard and a reset to default. These are exact counts kept by the
# ActiveRecord stand-in itself (ConnectionHandler#disconnects, Pool#disconnects)
# - not timings, and not sampled.
#
# WHY: 1.5.0's CHANGELOG claims "switching to the shard already in use
# performs no pool work" and that the native path "touches no connection
# pool" at all. Counts, not timings, are the only honest way to prove or
# disprove a claim like that - a millisecond difference on a laptop proves
# nothing, an extra replaced pool is unambiguous. THIS is the headline result
# of the whole benchmark suite.

require_relative 'support/setup'
require_relative 'support/report'

ROW = '  %<label>-46s %<count>d'

native = ConsoleKitBenchmark::Fakes::Sql::NativeBase
fallback = ConsoleKitBenchmark::Fakes::Sql::FallbackBase

# The native path never replaces a pool, so the handler's own count of the
# pools it replaced (each replacement disconnects the old one) is the whole
# story.
def native_churn(base, label)
  before = base.connection_handler.disconnects
  yield
  puts format(ROW, label: label, count: base.connection_handler.disconnects - before)
end

# The fallback path disconnects the live pool and swaps in a new one, so the
# pool held before the switch counts its own replacement.
def fallback_churn(base, label)
  pool = base.connection_pool
  yield
  puts format(ROW, label: label, count: pool.disconnects)
end

ConsoleKit::Output.silence do
  # --- Native shard path (connecting_to) ----------------------------------
  ConsoleKitBenchmark::Setup.configure_native!
  ConsoleKit.switch_tenant('acme') # land on acme; not measured, just a starting point

  ConsoleKitBenchmark::Report.title('Native shard path (SqlStrategy#apply_native, via connecting_to): pools replaced')
  native_churn(native, 'repeat switch to SAME shard (acme -> acme)') { ConsoleKit.switch_tenant('acme') }
  native_churn(native, 'switch to a DIFFERENT shard (acme -> globex)') { ConsoleKit.switch_tenant('globex') }
  native_churn(native, 'reset to default (globex -> nil)') { ConsoleKit.switch_tenant(nil) }
  puts format('  connected_to stack after those 3 switches: %<depth>d frame(s), current shard %<shard>p',
              depth: native.connected_to_stack.size, shard: native.current_shard)

  # --- establish_connection fallback path ---------------------------------
  ConsoleKitBenchmark::Setup.configure_fallback!
  ConsoleKit.switch_tenant('acme') # land on acme via the fallback path

  ConsoleKitBenchmark::Report.title('Fallback path (SqlStrategy#apply_fallback, via establish_connection): ' \
                                    'pools replaced')
  fallback_churn(fallback, 'repeat switch to SAME shard (acme -> acme)') { ConsoleKit.switch_tenant('acme') }
  fallback_churn(fallback, 'switch to a DIFFERENT shard (acme -> globex)') { ConsoleKit.switch_tenant('globex') }
  fallback_churn(fallback, 'reset to default (globex -> nil)') { ConsoleKit.switch_tenant(nil) }
end
