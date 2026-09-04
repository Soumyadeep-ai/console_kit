# frozen_string_literal: true

require_relative 'counters'

# Tiny formatting helper so every counting benchmark prints its numbers the
# same way: a labelled table of before/after/delta, not prose.
module ConsoleKitBenchmark
  # Prints a section title and per-counter before/after deltas.
  module Report
    class << self
      def title(text)
        puts
        puts text
        puts '-' * text.length
      end

      # Runs `block`, then prints how much each counter in `keys` moved.
      def count_delta(label, keys)
        before = Counters.snapshot
        yield
        after = Counters.snapshot
        puts "\n#{label}"
        keys.each { |key| puts format('  %<key>-32s %<delta>d', key: key, delta: after[key] - before[key]) }
        after
      end
    end
  end
end
