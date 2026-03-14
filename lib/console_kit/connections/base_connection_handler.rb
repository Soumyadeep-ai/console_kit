# frozen_string_literal: true

require 'active_support/core_ext/class/subclasses'

module ConsoleKit
  module Connections
    # Parent class for connection handlers
    class BaseConnectionHandler
      class << self
        def registry = descendants
      end

      attr_reader :context

      def initialize(context) = @context = context
      def connect = raise NotImplementedError, "#{self.class} must implement #connect"
      def available? = raise NotImplementedError, "#{self.class} must implement #available?"

      private

      def context_attribute(name)
        @context.respond_to?(name, true) ? @context.send(name) : nil
      end
    end
  end
end
