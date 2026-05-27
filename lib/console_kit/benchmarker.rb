# lib/console_kit/benchmarker.rb
# frozen_string_literal: true

module ConsoleKit
  # Records per-step timing and optional memory delta for a pipeline run.
  # Enabled when config.benchmark is true; replaced by NullBenchmarker otherwise.
  class Benchmarker
    SLOWEST_MARKER = ' <- slowest'
    STEP_COL_WIDTH = 25

    attr_reader :timings

    def initialize
      @timings       = {}
      @memory_before = nil
      @start_ms      = nil
    end

    def start_memory_tracking
      @memory_before = GC.stat(:total_allocated_objects)
    end

    def wrap(step_name)
      @start_ms = clock_ms
      result    = yield
      result
    ensure
      @timings[step_name] = clock_ms - @start_ms
    end

    def report(tenant_key)
      Output.print_info("Tenant switch: #{tenant_key} [#{total_ms}ms]")
      print_step_timings
      print_memory_delta if @memory_before
    end

    def slowest_step
      @timings.max_by { |_name, duration| duration }
    end

    private

    def clock_ms
      (Process.clock_gettime(Process::CLOCK_MONOTONIC) * 1000).round(2)
    end

    def total_ms
      @timings.values.sum.round(2)
    end

    def slowest_name
      slowest_step&.first
    end

    def print_step_timings
      slowest = slowest_name
      @timings.sort_by { |_name, duration| -duration }.each do |name, ms|
        marker = name == slowest ? SLOWEST_MARKER : ''
        Output.print_info("  #{name.ljust(STEP_COL_WIDTH)} #{ms}ms#{marker}")
      end
    end

    def print_memory_delta
      delta = GC.stat(:total_allocated_objects) - @memory_before
      Output.print_info("Allocated objects delta: +#{delta}")
    end
  end

  # No-op benchmarker used when config.benchmark is false (default).
  # Zero overhead — delegates block call directly.
  class NullBenchmarker
    def start_memory_tracking   = nil
    def report(_tenant_key)     = nil
    def slowest_step            = nil
    def timings                 = {}

    def wrap(_step_name)
      yield
    end
  end
end
