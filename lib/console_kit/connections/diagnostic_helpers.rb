# frozen_string_literal: true

require 'active_support/core_ext/string/filters'

module ConsoleKit
  module Connections
    module DiagnosticHelpers
      CREDENTIAL_PATTERN = begin
        url = %r{\b[a-z][a-z0-9+.-]*://\S*}i
        secret_key = /password|passwd|pwd|secret|token|api[_-]?key|access[_-]?key|auth(?:orization)?/i
        auth_scheme = /(?:Bearer|Basic|Token|Digest|ApiKey)\s+/i
        assignment = /["']?\b#{secret_key}\b["']?\s*(?:=>|=|:(?!:))\s*["']?#{auth_scheme}?\S+/
        noise = /
          authentication|auth|is|was|for|error|required|mismatch|incorrect|invalid|failed|missing|expired|
          limit|type|count|name|header|value|must|cannot|not|and|or|in|of|to|exceeded|denied|unsupported|
          supported|rejected|refused|revoked|length|format|scheme|provider|store|file|path|key
        /xi
        phrase = /\b#{secret_key}\s+(?!#{noise}\b)["']?\S+/i
        principal = /\b(?:for user|username|user name)\b\s+["']?\S+/i
        principal_at = /\buser\s+["']?\S+@\S+/i
        Regexp.union(url, assignment, phrase, principal, principal_at).freeze
      end

      REDACTED = '[redacted]'

      module_function

      def clock_time
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end

      def scrub(message)
        message.to_s.scrub.gsub(CREDENTIAL_PATTERN, REDACTED)
      end

      def error_diagnostics(name, error)
        { name: name, status: :error, latency_ms: nil, details: { error: scrub(error.message).truncate(60) } }
      end
    end
  end
end
