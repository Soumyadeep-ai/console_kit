# lib/console_kit/doctor/checks/required_constants_present.rb
# frozen_string_literal: true

require_relative 'base'

module ConsoleKit
  module Doctor
    module Checks
      # Checks that all required tenant keys are present in each tenant configuration.
      class RequiredConstantsPresent < Base
        def call
          return pass('no tenants to validate') if configured_tenants.blank?
          return pass('required constants check skipped: tenants is not a Hash') unless configured_tenants.is_a?(Hash)

          check_constants
        end

        private

        def configured_tenants
          config.tenants
        end

        def check_constants
          issues = collect_issues
          issues.empty? ? pass('all required constants present') : warn(issues.join('; '))
        end

        def collect_issues
          configured_tenants.filter_map do |key, tenant_config|
            constants = tenant_config&.[](:constants) || {}
            missing = config.required_tenant_keys - constants.keys
            "#{key}: missing #{missing.join(', ')}" unless missing.empty?
          end
        end
      end
    end
  end
end
