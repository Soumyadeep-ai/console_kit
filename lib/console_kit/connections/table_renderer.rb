# frozen_string_literal: true

require_relative 'table_formatter'

module ConsoleKit
  module Connections
    # Renders diagnostic data into a Unicode box-drawing table
    module TableRenderer
      class << self
        def render(rows)
          headers = %w[Service Status Latency Details]
          table_rows = rows.map { |r| TableFormatter.format_row(r) }
          widths = calculate_widths(headers, table_rows)

          build_table(headers, table_rows, widths)
        end

        private

        def calculate_widths(headers, rows)
          all_rows = [headers] + rows
          headers.each_index.map do |index|
            column_max_width(all_rows, index)
          end
        end

        def column_max_width(rows, index)
          rows.map { |row| row[index].length }.max
        end

        def build_table(headers, rows, widths)
          lines = [table_top(widths), table_line(headers, widths), table_mid(widths)]
          rows.each { |row| lines << table_line(row, widths) }
          lines << table_bottom(widths)
          lines.join("\n")
        end

        def table_top(widths) = "\u250C#{widths.map { |w| "\u2500" * (w + 2) }.join("\u252C")}\u2510"
        def table_mid(widths) = "\u251C#{widths.map { |w| "\u2500" * (w + 2) }.join("\u253C")}\u2524"
        def table_bottom(widths) = "\u2514#{widths.map { |w| "\u2500" * (w + 2) }.join("\u2534")}\u2518"

        def table_line(cells, widths)
          content = cells.each_with_index.map { |c, i| " #{c.ljust(widths[i])} " }.join("\u2502")
          "\u2502#{content}\u2502"
        end
      end
    end
  end
end
