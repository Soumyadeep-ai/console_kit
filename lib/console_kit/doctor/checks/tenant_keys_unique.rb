# lib/console_kit/doctor/checks/tenant_keys_unique.rb
# frozen_string_literal: true

require_relative 'base'

module ConsoleKit
  module Doctor
    module Checks
      # Checks that all tenant keys are unique.
      class TenantKeysUnique < Base
        def call
          return pass('no tenants to check') if config.tenants.blank?
          return pass('tenant key uniqueness not applicable in :dynamic mode') if dynamic_tenants?

          check_duplicates
        end

        private

        def dynamic_tenants?
          config.tenants == :dynamic
        end

        def check_duplicates
          dups = duplicate_keys
          dups.empty? ? pass('tenant keys unique') : error("Duplicate tenant keys: #{dups.join(', ')}")
        end

        def duplicate_keys
          string_keys = config.tenant_resolver_instance.all_keys.map(&:to_s)
          string_keys.group_by(&:itself).select { |_, occurrences| occurrences.size > 1 }.keys
        end
      end
    end
  end
end
