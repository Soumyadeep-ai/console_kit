# frozen_string_literal: true

require_relative 'errors'

module ConsoleKit
  # Resolves and validates what a tenant switch should do, without touching anything.
  #
  # This is the "validate" stage of a switch: it turns a tenant key into the
  # tenant constants and a per-backend target value. A nil tenant key describes a
  # reset to the default (no tenant) state.
  class TenantPlan
    REQUIRED_KEYS = %i[shard partner_code].freeze

    attr_reader :tenant_key

    # `constants` may be supplied by a caller that already froze them - a
    # committed TenantState - so verification does not have to re-resolve them
    # through a configuration that may have been replaced since the switch.
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

    # A handler owns its constants key, so it is asked for it directly. Routing
    # through the merged context mapping let any handler that declared another
    # backend's context attribute repoint that backend at its own key, and
    # stripping a blank value to nil here meant the switch judged a different
    # value than Configuration#validate! did - the one drift `.target_error`
    # exists to make impossible.
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
