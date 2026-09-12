# frozen_string_literal: true

require_relative 'errors'

module ConsoleKit
  # Resolves and validates what a tenant switch should do, without touching
  # anything. A nil tenant key describes a reset to the default (no tenant) state.
  class TenantPlan
    REQUIRED_KEYS = %i[shard partner_code].freeze

    attr_reader :tenant_key

    # `constants` may come pre-frozen from a committed TenantState, so verification
    # need not re-resolve through a configuration that may have changed since.
    def initialize(tenant_key, constants: nil)
      @tenant_key = tenant_key
      @constants = constants
    end

    def constants = @constants ||= resolve_constants

    # { backend_key => target_value_or_nil }
    def targets_for(handlers)
      handlers.to_h { |handler| [handler.backend_key, target_for(handler, constants)] }
    end

    private

    # The handler owns its constants key and is asked for it directly: routing
    # through the merged context mapping let one handler repoint another backend,
    # and normalising the value here made the switch judge it differently from
    # Configuration#validate!.
    def target_for(handler, constants) = constants[handler.class.constants_key]

    def resolve_constants
      return {} if tenant_key.nil?

      found = lookup_constants
      raise TenantNotFoundError, "No configuration found for tenant: #{tenant_key}" unless found

      validate!(found)
      found
    end

    def lookup_constants
      tenants = ConsoleKit.configuration.tenants
      tenants.is_a?(Hash) ? tenants.dig(tenant_key, :constants) : nil
    end

    def validate!(constants)
      missing = REQUIRED_KEYS - constants.keys
      return if missing.empty?

      raise ConfigurationError, "Tenant #{tenant_key.inspect} constants missing keys: #{missing.join(', ')}"
    end
  end
end
