# frozen_string_literal: true

# WHAT: exact call counts, per switch, for three things the brief calls out
# as suspects: `String#safe_constantize` frequency, how many times
# `ContextWrapper.for_context` runs (which is where `ctx.public_methods` gets
# scanned - see ContextWrapper.detect_attributes), and how many times
# connection handlers get instantiated. Measured via `Module#prepend` call
# counters installed only in this process (support/call_counting.rb) - lib/
# is never modified.
#
# WHY: the brief asks "worth fixing or not" - that requires the actual count,
# not a guess from reading the source. TenantSwitch memoizes both
# `@context_wrapper` and each handler instance for the lifetime of one
# switch, so the expectation going in is "once per switch, not once per
# backend or per internal call site". This either confirms that or finds a
# regression.

require_relative 'support/setup'
require_relative 'support/report'
require_relative 'support/call_counting'

ConsoleKitBenchmark::CallCounting.install!
ConsoleKitBenchmark::Setup.configure_native!

keys = %i[safe_constantize context_wrapper_for_context tenant_hash_lookup handler_instantiation
          available_handlers_call]

ConsoleKit::Output.silence do
  ConsoleKitBenchmark::Report.title('First switch ever (nil -> acme)')
  ConsoleKitBenchmark::Report.count_delta('ConsoleKit.switch_tenant("acme")', keys) { ConsoleKit.switch_tenant('acme') }

  ConsoleKitBenchmark::Report.title('Switch to a DIFFERENT tenant (acme -> globex)')
  ConsoleKitBenchmark::Report.count_delta('ConsoleKit.switch_tenant("globex")', keys) { ConsoleKit.switch_tenant('globex') }

  ConsoleKitBenchmark::Report.title('Repeat switch to the SAME tenant (globex -> globex)')
  ConsoleKitBenchmark::Report.count_delta('ConsoleKit.switch_tenant("globex")', keys) { ConsoleKit.switch_tenant('globex') }
end

puts
puts 'handler_instantiation is expected to equal the number of AVAILABLE backends (4 here) per switch:'
puts 'one BaseConnectionHandler subclass instance per backend, created once by ConnectionManager.available_handlers'
puts 'and reused for prepare/connect!/verify!/rollback within that same switch - never re-instantiated mid-switch.'
