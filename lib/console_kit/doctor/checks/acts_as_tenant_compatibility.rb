# frozen_string_literal: true

require_relative 'base'

module ConsoleKit
  module Doctor
    module Checks
      # Verifies ActsAsTenant is loaded and model/finder configured when acts_as_tenant_id is used.
      class ActsAsTenantCompatibility < Base
        def call
          return pass('acts_as_tenant_id not used') unless acts_as_tenant_used?
          return warn('ActsAsTenant gem not loaded') unless defined?(ActsAsTenant)
          return warn('acts_as_tenant_model or acts_as_tenant_finder not configured') unless model_or_finder_set?

          pass('ActsAsTenant configuration valid')
        end

        private

        def acts_as_tenant_used?
          tenants = config.tenants
          return false unless tenants.is_a?(Hash)

          tenants.values.any? { |t| t&.dig(:constants, :acts_as_tenant_id) }
        end

        def model_or_finder_set?
          config.acts_as_tenant_model.present? || config.acts_as_tenant_finder.present?
        end
      end
    end
  end
end
