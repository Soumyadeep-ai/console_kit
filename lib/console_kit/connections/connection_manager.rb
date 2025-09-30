# frozen_string_literal: true

require_relative 'sql_connection_handler'
require_relative 'mongo_connection_handler'

module ConsoleKit
  module Connections
    # Manages available connection handlers
    class ConnectionManager
      class << self
        def available_handlers(context)
          handler_classes.map do |klass|
            handler = klass.new(context)
            handler.available? ? handler : nil
          end.compact
        end

        private

        def handler_classes
          ConsoleKit::Connections.constants.map { |const| ConsoleKit::Connections.const_get(const) }.select { |const| const.is_a?(Class) && const < BaseConnectionHandler }
        end
      end
    end
  end
end
