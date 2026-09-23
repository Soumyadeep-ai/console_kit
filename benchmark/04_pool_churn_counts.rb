# frozen_string_literal: true

require_relative 'support/setup'
require_relative 'support/report'

ROW = '  %<label>-46s %<count>d'

native = ConsoleKitBenchmark::Fakes::Sql::NativeBase
fallback = ConsoleKitBenchmark::Fakes::Sql::FallbackBase

def native_churn(base, label)
  before = base.connection_handler.disconnects
  yield
  puts format(ROW, label: label, count: base.connection_handler.disconnects - before)
end

def fallback_churn(base, label)
  pool = base.connection_pool
  yield
  puts format(ROW, label: label, count: pool.disconnects)
end

ConsoleKit::Output.silence do
  ConsoleKitBenchmark::Setup.configure_native!
  ConsoleKit.switch_tenant('acme')

  ConsoleKitBenchmark::Report.title('Native shard path (SqlStrategy#apply_native, via connecting_to): pools replaced')
  native_churn(native, 'repeat switch to SAME shard (acme -> acme)') { ConsoleKit.switch_tenant('acme') }
  native_churn(native, 'switch to a DIFFERENT shard (acme -> globex)') { ConsoleKit.switch_tenant('globex') }
  native_churn(native, 'reset to default (globex -> nil)') { ConsoleKit.switch_tenant(nil) }
  puts format('  connected_to stack after those 3 switches: %<depth>d frame(s), current shard %<shard>p',
              depth: native.connected_to_stack.size, shard: native.current_shard)

  ConsoleKitBenchmark::Setup.configure_fallback!
  ConsoleKit.switch_tenant('acme')

  ConsoleKitBenchmark::Report.title('Fallback path (SqlStrategy#apply_fallback, via establish_connection): ' \
                                    'pools replaced')
  fallback_churn(fallback, 'repeat switch to SAME shard (acme -> acme)') { ConsoleKit.switch_tenant('acme') }
  fallback_churn(fallback, 'switch to a DIFFERENT shard (acme -> globex)') { ConsoleKit.switch_tenant('globex') }
  fallback_churn(fallback, 'reset to default (globex -> nil)') { ConsoleKit.switch_tenant(nil) }
end
