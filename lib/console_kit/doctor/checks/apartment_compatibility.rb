# frozen_string_literal: true

require_relative 'base'

module ConsoleKit
  module Doctor
    module Checks
      # Verifies Apartment >= 1.0 when apartment_schema key is used in tenant config.
      class ApartmentCompatibility < Base
        MIN_VERSION = '1.0'

        def call
          return pass('apartment_schema not configured') unless apartment_schema_used?
          return warn('Apartment gem not loaded but apartment_schema is configured') unless defined?(Apartment)
          return pass("Apartment #{apartment_version} compatible") if version_sufficient?

          error("Apartment gem >= #{MIN_VERSION} required; found #{apartment_version}")
        end

        private

        def apartment_schema_used?
          tenants = config.tenants
          return false unless tenants.is_a?(Hash)

          tenants.values.any? { |t| t&.dig(:constants, :apartment_schema) }
        end

        def version_sufficient?
          Gem::Version.new(apartment_version) >= Gem::Version.new(MIN_VERSION)
        rescue StandardError
          false
        end

        def apartment_version
          Gem.loaded_specs['apartment']&.version&.to_s || '0'
        end
      end
    end
  end
end
