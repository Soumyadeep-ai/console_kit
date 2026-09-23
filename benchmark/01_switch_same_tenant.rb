# frozen_string_literal: true

require 'benchmark/ips'
require_relative 'support/setup'

ConsoleKitBenchmark::Setup.configure_native!

ConsoleKit::Output.silence do
  ConsoleKit.switch_tenant('acme')

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
