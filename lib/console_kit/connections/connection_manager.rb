# lib/console_kit/connections/connection_manager.rb
# frozen_string_literal: true

module ConsoleKit
  module Connections
    # Discovers and returns connection handler objects for a given context class.
    module ConnectionManager
      class << self
        # Returns instantiated handlers from BaseConnectionHandler.registry
        # that report available? for the given +context_class+.
        def available_handlers(context_class)
          BaseConnectionHandler.registry.filter_map do |handler_class|
            handler = handler_class.new(context_class)
            handler if handler.available?
          end
        end
      end
    end
  end
end
