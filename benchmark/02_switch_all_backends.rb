# frozen_string_literal: true

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
