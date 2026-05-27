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

          dups = duplicate_keys
          dups.empty? ? pass('tenant keys unique') : error("Duplicate tenant keys: #{dups.join(', ')}")
        end

        private

        def duplicate_keys
          config.tenants.keys.map(&:to_s).group_by(&:itself).select { |_, count| count.size > 1 }.keys
        end
      end
    end
  end
end
