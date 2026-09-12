# frozen_string_literal: true

# WHAT: network-style operation counts DURING a tenant switch - the queries,
# pings, and health/version checks a :full diagnostics probe would issue
# (SQL execute/select_value, Mongo `command`, Redis ping/info, Elasticsearch
# ping/cluster.health). These are the fakes' stand-ins for a real round trip;
# see support/fakes.rb.
#
# WHY: 1.5.0's design claim is that TenantSwitch never asks a handler for
# diagnostics - `dashboard`/`Diagnostics.run` are entirely separate call
# paths (see lib/console_kit/diagnostics.rb's module comment). This is not
# about connection-establishment commands like Redis SELECT or
# `connecting_to`/`establish_connection`, which a switch legitimately must
# issue to move the tenant (those are covered, and counted, in
# 06_pool_churn_counts.rb) - it is specifically about the probe-style
# operations that only :full diagnostics should ever trigger. The expected
# number here is zero, for every one of these counters, on every switch.

require_relative 'support/setup'
require_relative 'support/report'

KEYS = %i[sql_execute sql_select_value mongo_command redis_ping redis_info es_ping es_cluster_health].freeze

ConsoleKitBenchmark::Setup.configure_native!

ConsoleKit::Output.silence do
  ConsoleKitBenchmark::Report.title('Diagnostic-style network ops during a switch (expected: 0 for every key)')
  ConsoleKitBenchmark::Report.count_delta('first switch (nil -> acme)', KEYS) { ConsoleKit.switch_tenant('acme') }
  ConsoleKitBenchmark::Report.count_delta('switch to a different tenant (acme -> globex)', KEYS) do
    ConsoleKit.switch_tenant('globex')
  end
  ConsoleKitBenchmark::Report.count_delta('repeat switch to the SAME tenant (globex -> globex)', KEYS) do
    ConsoleKit.switch_tenant('globex')
  end
  ConsoleKitBenchmark::Report.count_delta('reset to default (globex -> nil)', KEYS) { ConsoleKit.switch_tenant(nil) }

  ConsoleKit.switch_tenant('acme') # land on a tenant; not measured
  ConsoleKitBenchmark::Report.count_delta('ConsoleKit.verify_tenant! (re-verify current tenant)', KEYS) do
    ConsoleKit.verify_tenant!
  end
end
