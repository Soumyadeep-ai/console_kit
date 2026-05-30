# frozen_string_literal: true

require_relative 'base'

module ConsoleKit
  module Steps
    # Applies tenant and environment label to IRB/Pry prompt at end of pipeline.
    class PromptApplier < Base
      register priority: 70

      def call
        Prompt.apply
        success
      end
    end
  end
end
