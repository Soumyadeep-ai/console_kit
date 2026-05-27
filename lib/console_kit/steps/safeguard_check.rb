# lib/console_kit/steps/safeguard_check.rb
# frozen_string_literal: true

require_relative 'base'

module ConsoleKit
  module Steps
    # Warns about dangerous environments (production or protected tenants) and
    # optionally requires the user to type CONFIRM before the pipeline continues.
    class SafeguardCheck < Base
      register priority: 35

      def call
        return success if ctx.scoped
        return success unless dangerous?

        show_warning
        return success unless config.confirm_dangerous_context

        confirmed? ? success : failure('Console load aborted by user.')
      end

      private

      def dangerous?
        production_env? || protected_tenant?
      end

      def production_env?
        config.production_environments.include?(current_env)
      end

      def protected_tenant?
        config.protected_tenants.map(&:to_s).include?(ctx.resolved_tenant.to_s)
      end

      def current_env
        if defined?(Rails) && Rails.respond_to?(:env)
          Rails.env.to_s
        else
          ENV.fetch('RAILS_ENV', nil) || ENV.fetch('RACK_ENV', nil) || 'development'
        end
      end

      def show_warning
        Output.print_banner(
          lines: [
            "ENVIRONMENT : #{current_env.upcase}",
            "TENANT      : #{ctx.resolved_tenant || 'none'}",
            'Proceed with caution. Changes affect live data.'
          ],
          style: :danger
        )
      end

      def confirmed?
        Output.print_prompt('Type CONFIRM to continue: ')
        $stdin.gets&.chomp&.strip == 'CONFIRM'
      rescue Interrupt
        false
      end
    end
  end
end
