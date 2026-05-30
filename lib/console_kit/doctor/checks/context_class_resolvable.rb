# lib/console_kit/doctor/checks/context_class_resolvable.rb
# frozen_string_literal: true

require_relative 'base'

module ConsoleKit
  module Doctor
    module Checks
      # Checks that the configured context_class can be resolved to a constant.
      class ContextClassResolvable < Base
        def call
          config.context_class
          pass('context_class resolves')
        rescue ConsoleKit::Error => e
          error(e.message)
        end
      end
    end
  end
end
