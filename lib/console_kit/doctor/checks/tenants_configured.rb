# lib/console_kit/doctor/checks/tenants_configured.rb
# frozen_string_literal: true

require_relative 'base'

module ConsoleKit
  module Doctor
    module Checks
      # Checks that the tenants configuration is present and is a Hash, Array, or :dynamic.
      class TenantsConfigured < Base
        VALID_TYPES = [Hash, Array].freeze
        VALID_SYMBOL = :dynamic

        def call
          return error('`tenants` not configured') if tenants_absent?
          return error('`tenants` must be a Hash, Array, or :dynamic') unless valid_tenants?

          pass('tenants configured')
        end

        private

        def configured_tenants
          config.tenants
        end

        def tenants_absent?
          configured_tenants.blank? || configured_tenants == {}
        end

        def valid_tenants?
          VALID_TYPES.any? { |type| configured_tenants.is_a?(type) } || configured_tenants == VALID_SYMBOL
        end
      end
    end
  end
end
