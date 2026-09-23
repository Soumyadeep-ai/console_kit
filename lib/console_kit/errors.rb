# frozen_string_literal: true

require_relative 'connections/diagnostic_helpers'

module ConsoleKit
  PROGRAMMING_ERRORS = [NameError, ArgumentError, TypeError].freeze

  class << self
    def programming_error?(error) = PROGRAMMING_ERRORS.any? { |klass| error.is_a?(klass) }
  end

  class Error < StandardError; end

  class ConfigurationError < Error; end

  class TenantNotFoundError < ConfigurationError; end

  class UnsupportedBackendError < Error; end

  class ConnectionError < Error
    attr_reader :backend, :tenant, :operation

    def initialize(message = nil, backend: nil, tenant: nil, operation: nil)
      @backend = backend
      @tenant = tenant
      @operation = operation
      super(message || "#{backend} #{operation} failed for tenant #{tenant.inspect}")
    end
  end

  class ConnectionVerificationError < ConnectionError
    attr_reader :expected, :actual

    def initialize(message = nil, expected: nil, actual: nil, **opts)
      @expected = expected
      @actual = actual
      super(message || default_message(opts[:backend]), operation: :verify, **opts)
    end

    private

    def default_message(backend)
      "#{backend} verification failed. Expected #{expected.inspect}, got #{actual.inspect}"
    end
  end

  class RollbackError < Error
    attr_reader :failures

    def initialize(failures)
      @failures = failures
      super("Rollback failed for: #{failures.map { |failure| failure[:backend] }.join(', ')}")
    end
  end

  class TenantSwitchError < Error
    attr_reader :from_tenant, :to_tenant, :backend, :original_error, :rollback_failures

    def initialize(from_tenant:, to_tenant:, original_error:, backend: nil, rollback_failures: [])
      @from_tenant = from_tenant
      @to_tenant = to_tenant
      @backend = backend
      @original_error = original_error
      @rollback_failures = rollback_failures
      super(build_message)
    end

    def rollback_succeeded? = rollback_failures.empty?

    private

    def build_message
      [headline, scrub(original_error.message), rollback_summary].compact.join("\n")
    end

    def scrub(message) = Connections::DiagnosticHelpers.scrub(message)

    def headline
      scope = backend ? " (#{backend})" : nil
      "Failed to switch tenant from #{from_tenant.inspect} to #{to_tenant.inspect}#{scope}:"
    end

    def rollback_summary
      return "\nPrevious tenant state was restored successfully." if rollback_succeeded?

      "\nWARNING: rollback did not fully succeed:\n#{formatted_failures}"
    end

    def formatted_failures
      rollback_failures.map { |failure| "  - #{failure[:backend]}: #{scrub(failure[:error].message)}" }.join("\n")
    end
  end
end
