# frozen_string_literal: true

# WHAT: switching with all four backends (SQL, Mongo, Redis, Elasticsearch)
# available together, compared against SQL alone, to isolate the marginal
# per-backend cost of the transaction (prepare/connect!/verify! run once per
# available handler - see TenantSwitch#prepare_all/#connect_all/#verify_all).
#
# WHY: the brief lists "switching across all four backends together" as its
# own required benchmark. Comparing it to a single-backend switch is what
# turns "here is a number" into "here is what four backends actually cost
# you over one".
#
# NOTE ON ORDERING: this file must run the SQL-only scenario FIRST, in a
# process where Mongoid/Redis/Elasticsearch::Model are never defined -
# ConnectionManager.available_handlers filters by `handler.available?`, which
# for those three backends is simply `defined?(...)`. Once support/fakes
# defines those constants (via configure_native!, below) they cannot be
# cleanly undefined again, so the single-backend measurement has to come
# before the four-backend one within this process.

require 'benchmark/ips'
require_relative 'support/setup'

ConsoleKitBenchmark::Setup.configure_sql_only!
tenants_sql_only = %w[acme globex].cycle

ConsoleKit::Output.silence do
  Benchmark.ips do |x|
    x.config(time: 2, warmup: 1)
    x.report('switch_tenant (SQL backend only)') { ConsoleKit.switch_tenant(tenants_sql_only.next) }
  end
end

ConsoleKitBenchmark::Setup.configure_native!
tenants_all = %w[acme globex].cycle

ConsoleKit::Output.silence do
  Benchmark.ips do |x|
    x.config(time: 2, warmup: 1)
    x.report('switch_tenant (all 4 backends: SQL + Mongo + Redis + Elasticsearch)') do
      ConsoleKit.switch_tenant(tenants_all.next)
    end
  end
end
