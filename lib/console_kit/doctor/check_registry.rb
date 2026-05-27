# lib/console_kit/doctor/check_registry.rb
# frozen_string_literal: true

module ConsoleKit
  module Doctor
    # Registry that holds all Doctor check classes.
    module CheckRegistry
      class << self
        def register(klass)
          registry << klass
        end

        def all
          registry.dup
        end

        private

        def registry
          @registry ||= []
        end
      end
    end
  end
end
