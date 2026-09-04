# frozen_string_literal: true

require_relative 'sql_connection_handler'
require_relative 'mongo_connection_handler'
require_relative 'redis_connection_handler'
require_relative 'elasticsearch_connection_handler'
require_relative '../output'
require_relative '../instrumentation'

module ConsoleKit
  module Connections
    # Manages available connection handlers
    class ConnectionManager
      DROPPED_WARNING = 'was skipped because it is only half-implemented (%<reason>s). That backend will NOT be ' \
                        'switched, verified or rolled back, and a switch will still report itself as verified.'

      class << self
        def available_handlers(context)
          handler_classes.filter_map { |klass| resolve(klass, context) }
        end

        private

        # A handler whose #available? answers false is an optional gem that is
        # simply not loaded, and there is nothing to report. A handler that
        # raises NotImplementedError is broken rather than absent, and dropping
        # it silently is what lets a switch claim success while that backend
        # still serves another tenant, so it is reported before it is dropped.
        def resolve(klass, context)
          handler = klass.new(context)
          handler if handler.available?
        rescue NotImplementedError => e
          report_dropped(klass, e)
          nil
        end

        def report_dropped(klass, error)
          Instrumentation.increment('console_kit.handler_dropped')
          Output.print_warning("#{klass} #{format(DROPPED_WARNING, reason: error.message)}")
        end

        def handler_classes = BaseConnectionHandler.registry
      end
    end
  end
end
