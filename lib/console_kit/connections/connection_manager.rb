# frozen_string_literal: true

require_relative 'sql_connection_handler'
require_relative 'mongo_connection_handler'
require_relative 'redis_connection_handler'
require_relative 'elasticsearch_connection_handler'

module ConsoleKit
  module Connections
    # Manages available connection handlers
    class ConnectionManager
      class << self
        def available_handlers(context)
          handler_classes.filter_map do |klass|
            handler = klass.new(context)
            handler if handler.available?
          rescue NotImplementedError
            nil
          end
        end

        private

        def handler_classes = BaseConnectionHandler.registry
      end
    end
  end
end
