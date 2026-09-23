# frozen_string_literal: true

require_relative 'counters'

module ConsoleKitBenchmark
  module Report
    ROW = '  %<key>-32s %<delta>d'

    class << self
      def title(text)
        puts
        puts text
        puts '-' * text.length
      end

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
