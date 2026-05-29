# frozen_string_literal: true

require_relative 'base'

module ConsoleKit
  module Steps
    # Prints a branded startup header. Runs first in the pipeline.
    # Skipped for scoped tenant switches (ConsoleKit.with blocks).
    class WelcomeBanner < Base
      register priority: 2

      def call
        return success if ctx.scoped

        Output.print_header("ConsoleKit #{ConsoleKit::VERSION}  |  #{current_env}")
        success
      end
    end
  end
end
