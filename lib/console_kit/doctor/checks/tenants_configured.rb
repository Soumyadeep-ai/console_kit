# lib/console_kit/doctor/checks/tenants_configured.rb
# frozen_string_literal: true

require_relative 'base'

module ConsoleKit
  module Doctor
    module Checks
      # Checks that the tenants configuration is present and is a Hash.
      class TenantsConfigured < Base
        def call
          tenants = config.tenants
          return error('`tenants` not configured') if tenants.blank?
          return error('`tenants` must be a Hash') unless tenants.is_a?(Hash)

          pass('tenants configured')
        end
      end
    end
  end
end
