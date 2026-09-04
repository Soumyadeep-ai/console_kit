# frozen_string_literal: true

module ConsoleKit
  # Base error class for ConsoleKit-related exceptions.
  class Error < StandardError; end

  # Raised when ConsoleKit configuration is missing, malformed or unusable.
  class ConfigurationError < Error; end

  # Raised when a tenant key is not present in the configured tenant map.
  class TenantNotFoundError < ConfigurationError; end

  # Raised when a backend cannot support the requested tenant operation.
  class UnsupportedBackendError < Error; end

  # Raised when a backend connection cannot be established or inspected.
  class ConnectionError < Error
    attr_reader :backend, :tenant, :operation

    def initialize(message = nil, backend: nil, tenant: nil, operation: nil)
      @backend = backend
      @tenant = tenant
      @operation = operation
      super(message || "#{backend} #{operation} failed for tenant #{tenant.inspect}")
    end
  end

  # Raised when a backend connects successfully but points at the wrong tenant resource.
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

  # Raised when restoring previous state fails. Carries every per-backend failure.
  class RollbackError < Error
    attr_reader :failures

    def initialize(failures)
      @failures = failures
      super("Rollback failed for: #{failures.map { |f| f[:backend] }.join(', ')}")
    end
  end

  # Raised when a tenant switch fails. Preserves the root cause and any rollback failures.
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
      [headline, original_error.message, rollback_summary].compact.join("\n")
    end

    def headline
      "Failed to switch tenant from #{from_tenant.inspect} to #{to_tenant.inspect}" \
        "#{backend ? " (#{backend})" : ''}:"
    end

    def rollback_summary
      return "\nPrevious tenant state was restored successfully." if rollback_succeeded?

      "\nWARNING: rollback did not fully succeed:\n#{formatted_failures}"
    end

    def formatted_failures
      rollback_failures.map { |f| "  - #{f[:backend]}: #{f[:error].message}" }.join("\n")
    end
  end
end
