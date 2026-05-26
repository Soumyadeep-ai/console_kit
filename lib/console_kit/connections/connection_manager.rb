# lib/console_kit/connections/connection_manager.rb
# frozen_string_literal: true

module ConsoleKit
  module Connections
    # Discovers and returns connection handler objects for a given context class.
    # Full implementation provided in Task 17 (ShardConnector).
    module ConnectionManager
      class << self
        # Returns connection handlers that are applicable to +context_class+.
        # Returns an empty array by default; overridden in Task 17.
        def available_handlers(_context_class)
          []
        end
      end
    end
  end
end
