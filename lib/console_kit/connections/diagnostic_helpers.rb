# frozen_string_literal: true

require 'active_support/core_ext/string/filters'

module ConsoleKit
  module Connections
    # Shared helper methods for connection diagnostics
    module DiagnosticHelpers
      # One alternation, one scan: gsub only ever looks at the ORIGINAL message,
      # so no shape can match text an earlier redaction inserted. Chaining
      # separate gsubs would re-scan the previous pass's `[redacted]` markers.
      # The parts are locals rather than constants: nothing outside this module
      # has any use for a half-built credential pattern.
      CREDENTIAL_PATTERN = begin
        url = %r{\b[a-z][a-z0-9+.-]*://\S*}i
        secret_key = /password|passwd|pwd|secret|token|api[_-]?key|access[_-]?key|auth(?:orization)?/i
        # An auth scheme spans the space between label and secret
        # (`Authorization: Bearer <jwt>`), so stopping at the first space would
        # redact the label and leave the credential. In `assignment`,
        # `:(?!:)` keeps `Mongo::Auth::Unauthorized` from reading as an assignment.
        auth_scheme = /(?:Bearer|Basic|Token|Digest|ApiKey)\s+/i
        assignment = /["']?\b#{secret_key}\b["']?\s*(?:=>|=|:(?!:))\s*["']?#{auth_scheme}?\S+/
        # Ordinary English following a secret-ish word: without the lookahead this
        # excludes, `token limit exceeded` is redacted into uselessness.
        noise = /
          authentication|auth|is|was|for|error|required|mismatch|incorrect|invalid|failed|missing|expired|
          limit|type|count|name|header|value|must|cannot|not|and|or|in|of|to|exceeded|denied|unsupported|
          supported|rejected|refused|revoked|length|format|scheme|provider|store|file|path|key
        /xi
        phrase = /\b#{secret_key}\s+(?!#{noise}\b)["']?\S+/i
        principal = /\b(?:for user|username|user name)\b\s+["']?\S+/i
        # The @ is what distinguishes a principal from the English word "user".
        principal_at = /\buser\s+["']?\S+@\S+/i
        Regexp.union(url, assignment, phrase, principal, principal_at).freeze
      end

      REDACTED = '[redacted]'

      module_function

      def clock_time
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end

      # Hostnames are deliberately NOT scrubbed: removing them would gut the
      # diagnostic value of a connection error. `String#scrub` first because this
      # runs inside TenantSwitchError's constructor, where an invalid byte
      # sequence would raise, replace the root cause and escape switch_tenant.
      def scrub(message)
        message.to_s.scrub.gsub(CREDENTIAL_PATTERN, REDACTED)
      end

      def error_diagnostics(name, error)
        { name: name, status: :error, latency_ms: nil, details: { error: scrub(error.message).truncate(60) } }
      end
    end
  end
end
