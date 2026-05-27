# frozen_string_literal: true

module ConsoleKit
  module Connections
    # Formats raw diagnostic data for table display
    module TableFormatter
      class << self
        def format_row(diag)
          [
            diag[:name],
            format_status(diag[:status]),
            format_latency(diag[:latency_ms]),
            format_details(diag[:details])
          ]
        end

        def format_status(status)
          return "\u2713 Connected" if status == :connected
          return "\u2717 Error" if %i[error timeout].include?(status)
          return "\u2014 N/A" if status == :unavailable

          '? Unknown'
        end

        def format_latency(latency_ms)
          latency_ms ? "#{latency_ms}ms" : "\u2014"
        end

        def format_details(details)
          return '' unless details&.any?

          details.compact.map { |key, value| "#{key}: #{value}" }.join(', ')
        end
      end
    end
  end
end
