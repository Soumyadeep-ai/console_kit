# frozen_string_literal: true

module ConsoleKitBenchmark
  # Shared call counter for the fakes and for CallCounting. A Hash with a
  # default of 0 is the whole feature; benchmarks read deltas out of it.
  Counters = Hash.new(0)
end
