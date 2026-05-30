# frozen_string_literal: true

require_relative 'base'

module ConsoleKit
  module Doctor
    module Checks
      # Verifies ActiveRecord is loaded when readonly_mode or readonly_environments is configured.
      class ReadonlyModeCompatibility < Base
        def call
          return pass('readonly mode not configured') unless readonly_configured?
          return pass('ActiveRecord available for readonly mode') if ar_available?

          error('readonly_mode configured but ActiveRecord is not loaded')
        end

        private

        def readonly_configured? = config.readonly_mode || config.readonly_environments.any?
        def ar_available?        = defined?(ActiveRecord::Base)
      end
    end
  end
end
