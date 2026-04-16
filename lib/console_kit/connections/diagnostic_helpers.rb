# frozen_string_literal: true

module ConsoleKit
  module Connections
    # Shared helper methods for connection diagnostics
    module DiagnosticHelpers
      module_function

      def clock_time
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end

      def error_diagnostics(name, error)
        { name: name, status: :error, latency_ms: nil, details: { error: error.message.truncate(60) } }
      end

      def timeout_diagnostics(name, timeout)
        { name: name, status: :timeout, latency_ms: nil, details: { error: "Timed out after #{timeout}s" } }
      end
    end
  end
end
