# frozen_string_literal: true

module ConsoleKit
  module Connections
    # Parent class for connection handlers
    class BaseConnectionHandler
      def initialize(context)
        @context = context
      end

      def connect
        raise NotImplementedError, "#{self.class.name} must implement #connect"
      end

      def available?
        false
      end
    end
  end
end
