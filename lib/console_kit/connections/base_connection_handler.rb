# frozen_string_literal: true

module ConsoleKit
  module Connections
    # Parent class for connection handlers
    class BaseConnectionHandler
      @registry = []

      class << self
        def registry = @registry ||= []

        def inherited(subclass)
          super
          registry << subclass
        end
      end

      attr_reader :context

      def initialize(context) = @context = context
      def connect = raise NotImplementedError, "#{self.class} must implement #connect"
      def available? = false
    end
  end
end
