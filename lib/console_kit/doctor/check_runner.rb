# lib/console_kit/doctor/check_runner.rb
# frozen_string_literal: true

module ConsoleKit
  module Doctor
    # Runs all registered Doctor checks against the given configuration.
    class CheckRunner
      def initialize(config)
        @config = config
      end

      def run
        CheckRegistry.all.map { |check| check.new(@config).call }
      end
    end
  end
end
