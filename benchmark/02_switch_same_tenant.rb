# frozen_string_literal: true

# WHAT: cost of switching to the SAME tenant repeatedly, at two layers:
#
#   1. `ConsoleKit::TenantConfigurator.configure_tenant(key)` - the
#      console-facing entry point. It short-circuits with
#      `return true if key == current_tenant_key && configuration_success`,
#      so a repeat call does no work at all beyond one equality check. This
#      is the actual "memoized/no-op path" the brief means.
#   2. `ConsoleKit.switch_tenant(key)` - the raising, programmatic API. It
#      calls TenantSwitch directly and has NO such short-circuit: every call
#      re-runs validate -> snapshot -> prepare -> apply context -> connect ->
#      verify -> commit, even for a tenant that is already current. Any
#      "no-op" behaviour on this path comes only from each backend handler's
#      own internal skip (e.g. SqlStrategy's fallback path skips
#      `establish_connection` when already on the target config; Redis skips
#      `select` when already on the target DB).
#
# WHY: the brief explicitly asks for the "same tenant, memoized/no-op path"
# to be measured. Reporting only #1 would overstate how cheap a repeat
# `switch_tenant` call is; reporting only #2 would hide that a real no-op
# path exists one layer up. Both numbers matter.

require 'benchmark/ips'
require_relative 'support/setup'

ConsoleKitBenchmark::Setup.configure_native!

ConsoleKit::Output.silence do
  ConsoleKit.switch_tenant('acme') # land on acme once before timing repeats

  Benchmark.ips do |x|
    x.config(time: 2, warmup: 1)
    x.report('TenantConfigurator.configure_tenant (same tenant, short-circuited)') do
      ConsoleKit::TenantConfigurator.configure_tenant('acme')
    end
    x.report('ConsoleKit.switch_tenant (same tenant, full transaction every call)') do
      ConsoleKit.switch_tenant('acme')
    end
    x.compare!
  end
end
