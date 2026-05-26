# lib/console_kit/steps/base.rb
# frozen_string_literal: true

module ConsoleKit
  module Steps
    # Abstract base class for all pipeline steps.
    class Base
      # Represents the outcome of a single step execution.
      Result = Struct.new(:success, :error, keyword_init: true) do
        def success? = success
        def failure? = !success
      end

      class << self
        def register(priority:)
          ConsoleKit::StepRegistry.register(self, priority: priority)
        end
      end

      def initialize(ctx)
        @ctx = ctx
      end

      def call
        raise NotImplementedError, "#{self.class}#call not implemented"
      end

      private

      attr_reader :ctx

      def config  = ctx.config
      def success = Result.new(success: true)
      def failure(msg) = Result.new(success: false, error: msg)
    end
  end
end
