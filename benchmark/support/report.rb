# frozen_string_literal: true

require_relative 'counters'

# Tiny formatting helper so every counting benchmark prints its numbers the
# same way: a labelled table of before/after/delta, not prose.
module ConsoleKitBenchmark
  # Prints a section title and per-counter before/after deltas.
  module Report
    ROW = '  %<key>-32s %<delta>d'

    class << self
      def title(text)
        puts
        puts text
        puts '-' * text.length
      end

      # Runs `block`, then prints how much each counter in `keys` moved. SQL has
      # no Counters entry - the ActiveRecord stand-in records statements itself -
      # so `statements:` takes that array and its growth is reported alongside.
      def count_delta(label, keys, statements: nil)
        before = Counters.dup
        sql_before = statements&.size
        yield
        puts "\n#{label}"
        keys.each { |key| puts format(ROW, key: key, delta: Counters[key] - before[key]) }
        puts format(ROW, key: :sql_statements, delta: statements.size - sql_before) if statements
      end
    end
  end
end
