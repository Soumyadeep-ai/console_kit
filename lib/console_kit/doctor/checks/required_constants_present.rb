# lib/console_kit/doctor/checks/required_constants_present.rb
# frozen_string_literal: true

require_relative 'base'

module ConsoleKit
  module Doctor
    module Checks
      # Checks that all required tenant keys are present in each tenant configuration.
      class RequiredConstantsPresent < Base
        def call
          return pass('no tenants to validate') if config.tenants.blank?

          issues = collect_issues
          return pass('all required constants present') if issues.empty?

          warn(issues.join('; '))
        end

        private

        def collect_issues
          config.tenants.filter_map do |key, tenant_config|
            constants = tenant_config&.[](:constants) || {}
            missing = config.required_tenant_keys - constants.keys
            "#{key}: missing #{missing.join(', ')}" unless missing.empty?
          end
        end
      end
    end
  end
end
