# lib/console_kit/doctor/checks/base.rb
# frozen_string_literal: true

module ConsoleKit
  module Doctor
    module Checks
      # Base class for all Doctor checks.
      class Base
        # Immutable value object returned by every check.
        Result = Struct.new(:check, :status, :message, keyword_init: true) do
          def failure?
            status == :error
          end

          def warning?
            status == :warn
          end
        end

        class << self
          def inherited(subclass)
            super
            ConsoleKit::Doctor::CheckRegistry.register(subclass)
          end
        end

        def initialize(config)
          @config = config
        end

        def call
          raise NotImplementedError
        end

        private

        attr_reader :config

        def pass(msg)
          Result.new(check: self.class.name, status: :ok, message: msg)
        end

        def warn(msg)
          Result.new(check: self.class.name, status: :warn, message: msg)
        end

        def error(msg)
          Result.new(check: self.class.name, status: :error, message: msg)
        end
      end
    end
  end
end
