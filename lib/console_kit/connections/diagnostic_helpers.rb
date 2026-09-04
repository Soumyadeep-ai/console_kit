# frozen_string_literal: true

require 'active_support/core_ext/string/filters'

module ConsoleKit
  module Connections
    # Shared helper methods for connection diagnostics
    module DiagnosticHelpers
      # A diagnostic row is printed and may be forwarded to a log, so nothing
      # that could carry a host, user, password, token or API key is allowed
      # through verbatim. Client error messages routinely embed the whole
      # connection URL they failed on.
      CREDENTIAL_URL = %r{\b[a-z][a-z0-9+.-]*://\S*}i
      CREDENTIAL_ASSIGNMENT = /
        \b(?:password|passwd|pwd|secret|token|api[_-]?key|access[_-]?key|auth(?:orization)?)\b\s*[=:]\s*\S+
      /xi
      REDACTED = '[redacted]'
      BUSY_REASON = 'A previous check is still running'

      module_function

      def clock_time
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end

      def scrub(message)
        message.to_s.gsub(CREDENTIAL_URL, REDACTED).gsub(CREDENTIAL_ASSIGNMENT, REDACTED)
      end

      def error_diagnostics(name, error)
        { name: name, status: :error, latency_ms: nil, details: { error: scrub(error.message).truncate(60) } }
      end

      def timeout_diagnostics(name, timeout)
        expired_diagnostics(name, "Timed out after #{timeout}s")
      end

      # A check that could not even be started because the backend's worker is
      # still occupied by a previous, timed-out check. Reported as :timeout so
      # the dashboard renders it as a failure rather than an unknown state.
      def busy_diagnostics(name)
        expired_diagnostics(name, BUSY_REASON)
      end

      def expired_diagnostics(name, reason)
        { name: name, status: :timeout, latency_ms: nil, details: { error: reason } }
      end
    end
  end
end
