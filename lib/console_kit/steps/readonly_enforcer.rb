# frozen_string_literal: true

require_relative 'base'

module ConsoleKit
  module Steps
    # Activates ReadonlyMode when readonly_mode is true or current env is in readonly_environments.
    # Skipped for :dynamic tenant mode or when ActiveRecord is not available.
    class ReadonlyEnforcer < Base
      register priority: 37

      def call
        return success unless should_activate?

        ReadonlyMode.install!
        ReadonlyMode.activate!
        print_readonly_banner
        success
      end

      private

      def print_readonly_banner
        Output.print_banner(
          lines: [
            'READONLY MODE ACTIVE',
            "ENVIRONMENT : #{current_env.upcase}",
            'Write operations are blocked in this session.'
          ],
          style: :warning
        )
      end

      def should_activate?
        ar_available? && (config.readonly_mode || (!dynamic_mode? && env_enforced?))
      end

      def ar_available? = defined?(ActiveRecord::Base)
      def dynamic_mode? = config.tenants == :dynamic
      def env_enforced? = config.readonly_environments.include?(current_env)
    end
  end
end
