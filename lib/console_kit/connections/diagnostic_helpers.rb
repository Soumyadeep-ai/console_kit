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
      SECRET_KEY = /password|passwd|pwd|secret|token|api[_-]?key|access[_-]?key|auth(?:orization)?/i
      # key=value, key: value, key => value and "key"=>"value". The `:(?!:)`
      # keeps `Mongo::Auth::Unauthorized` from being read as an assignment.
      CREDENTIAL_ASSIGNMENT = /["']?\b#{SECRET_KEY}\b["']?\s*(?:=>|=|:(?!:))\s*["']?\S+/
      # `password hunter2` with no separator at all. The negative lookahead stops
      # `password authentication failed` from being mangled into nonsense.
      SECRET_NOISE = /authentication|auth|is|was|for|error|required|mismatch|incorrect|invalid|failed|missing|expired/i
      CREDENTIAL_PHRASE = /\b#{SECRET_KEY}\s+(?!#{SECRET_NOISE}\b)["']?\S+/i
      # `for user "svc_admin"`, `username admin` - a principal is not a password,
      # but it is half of one and routinely appears in auth failures.
      CREDENTIAL_PRINCIPAL = /\b(?:for user|username|user name)\b\s+["']?\S+/i
      # `User svc_admin@admin is not authorized` - the @ is what distinguishes a
      # principal from the ordinary English word "user".
      CREDENTIAL_PRINCIPAL_AT = /\buser\s+["']?\S+@\S+/i
      SCRUBBERS = [CREDENTIAL_URL, CREDENTIAL_ASSIGNMENT, CREDENTIAL_PHRASE,
                   CREDENTIAL_PRINCIPAL, CREDENTIAL_PRINCIPAL_AT].freeze
      REDACTED = '[redacted]'
      BUSY_REASON = 'A previous check is still running'

      module_function

      def clock_time
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end

      # Hostnames are deliberately NOT scrubbed: they are not secrets in the same
      # class as a password, and removing them would gut the diagnostic value of
      # a connection error. Everything that is half of a credential is removed.
      def scrub(message)
        SCRUBBERS.reduce(message.to_s) { |text, pattern| text.gsub(pattern, REDACTED) }
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
