# frozen_string_literal: true

module ConsoleKit
  module Connections
    # Displays connection diagnostics as a Unicode table
    module Dashboard
      class << self
        def display
          ctx = ConsoleKit.configuration.context_class
          handlers = ConnectionManager.available_handlers(ctx)
          rows = handlers.map(&:safe_diagnostics)
          return Output.print_warning('No connections available') if rows.empty?

          Output.print_header('Connection Dashboard')
          Output.print_raw(render_table(rows))
        end

        private

        def render_table(rows)
          # Build the table data
          headers = %w[Service Status Latency Details]
          table_rows = rows.map { |r| format_row(r) }

          # Calculate column widths
          all_rows = [headers] + table_rows
          widths = headers.each_index.map do |i|
            all_rows.map { |r| r[i].length }.max
          end

          # Build Unicode box-drawing table
          build_table(headers, table_rows, widths)
        end

        def format_row(diag)
          [
            diag[:name],
            format_status(diag[:status]),
            format_latency(diag[:latency_ms]),
            format_details(diag[:details])
          ]
        end

        def format_status(status)
          case status
          when :connected then "\u2713 Connected"
          when :error, :timeout then "\u2717 Error"
          when :unavailable then "\u2014 N/A"
          else '? Unknown'
          end
        end

        def format_latency(milliseconds)
          milliseconds ? "#{milliseconds}ms" : "\u2014"
        end

        def format_details(details)
          return '' if details.nil? || details.empty?

          details.compact.map { |k, v| "#{k}: #{v}" }.join(', ')
        end

        def build_table(headers, rows, widths)
          lines = [table_top(widths)]
          lines << table_line(headers, widths)
          lines << table_mid(widths)
          rows.each { |row| lines << table_line(row, widths) }
          lines << table_bottom(widths)
          lines.join("\n")
        end

        def table_top(widths)
          "\u250C#{widths.map { |w| "\u2500" * (w + 2) }.join("\u252C")}\u2510"
        end

        def table_mid(widths)
          "\u251C#{widths.map { |w| "\u2500" * (w + 2) }.join("\u253C")}\u2524"
        end

        def table_bottom(widths)
          "\u2514#{widths.map { |w| "\u2500" * (w + 2) }.join("\u2534")}\u2518"
        end

        def table_line(cells, widths)
          "\u2502#{cells.each_with_index.map { |c, i| " #{c.ljust(widths[i])} " }.join("\u2502")}\u2502"
        end
      end
    end
  end
end
