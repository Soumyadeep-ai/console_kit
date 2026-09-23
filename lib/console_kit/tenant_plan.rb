# frozen_string_literal: true

require_relative 'errors'

module ConsoleKit
  class TenantPlan
    REQUIRED_KEYS = %i[shard partner_code].freeze

    attr_reader :tenant_key

    def initialize(tenant_key, constants: nil)
      @tenant_key = tenant_key
      @constants = constants
    end

    def constants = @constants ||= resolve_constants

    def targets_for(handlers)
      handlers.to_h { |handler| [handler.backend_key, target_for(handler)] }
    end

    private

    def target_for(handler) = constants[handler.class.constants_key]

    def resolve_constants
      return {} if tenant_key.nil?

      found = lookup_constants
      raise TenantNotFoundError, not_found_message unless found

      validate!(found)
      found
    end

    def not_found_message
      tenants = ConsoleKit.configuration.tenants
      keys = tenants.is_a?(Hash) ? tenants.keys : []
      known = keys.any? ? "Configured tenants: #{keys.map(&:inspect).join(', ')}." : 'No tenants are configured.'
      "No configuration found for tenant: #{tenant_key.inspect}. #{known}"
    end

    def lookup_constants
      tenants = ConsoleKit.configuration.tenants
      entry = tenants.is_a?(Hash) ? tenants[tenant_key] : nil
      constants_from(entry) unless entry.nil?
    end

    def constants_from(entry)
      raise ConfigurationError, "Tenant #{tenant_key.inspect} configuration must be a Hash, got #{entry.class}." \
        unless entry.is_a?(Hash)

      entry[:constants]
    end

    def validate!(constants)
      tenant = tenant_key.inspect
      unless constants.is_a?(Hash)
        raise ConfigurationError, "Tenant #{tenant} `:constants` must be a Hash, got #{constants.class}."
      end

      missing = REQUIRED_KEYS - constants.keys
      return if missing.empty?

      raise ConfigurationError, "Tenant #{tenant} constants missing keys: #{missing.join(', ')}"
    end
  end
end
