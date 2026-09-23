# frozen_string_literal: true

module ConsoleKit
  module Connections
    # Renders diagnostic data into a Unicode box-drawing table
    module TableRenderer
      HEADERS = %w[Service Status Latency Details].freeze
      STATUS = {
        connected: "\u2713 Connected",
        error: "\u2717 Error",
        unavailable: "\u2014 N/A"
      }.freeze

      class << self
        def render(rows)
          table_rows = rows.map { |row| format_row(row) }
          widths = ([HEADERS] + table_rows).transpose.map { |column| column.map(&:length).max }

          build_table(table_rows, widths)
        end

        private

        def format_row(diag)
          latency = diag[:latency_ms]
          [
            diag[:name],
            STATUS.fetch(diag[:status], '? Unknown'),
            latency ? "#{latency}ms" : "\u2014",
            format_details(diag[:details])
          ]
        end

        def format_details(details)
          return '' unless details&.any?

          details.compact.map { |key, value| "#{key}: #{value}" }.join(', ')
        end

        def build_table(rows, widths)
          lines = [rule(widths, "\u250C\u252C\u2510"), table_line(HEADERS, widths),
                   rule(widths, "\u251C\u253C\u2524")]
          rows.each { |row| lines << table_line(row, widths) }
          lines << rule(widths, "\u2514\u2534\u2518")
          lines.join("\n")
        end

        # The three corner/junction characters of one horizontal rule, in the
        # order they appear on it.
        def rule(widths, corners)
          left, join, right = corners.chars
          "#{left}#{widths.map { |width| "\u2500" * (width + 2) }.join(join)}#{right}"
        end

        def table_line(cells, widths)
          content = cells.each_with_index.map { |cell, index| " #{cell.ljust(widths[index])} " }.join("\u2502")
          "\u2502#{content}\u2502"
        end
      end
    end
  end
end
