# frozen_string_literal: true

require_relative 'sql_connection_handler'
require_relative 'mongo_connection_handler'
require_relative 'redis_connection_handler'
require_relative 'elasticsearch_connection_handler'
require_relative '../output'
require_relative '../instrumentation'

module ConsoleKit
  module Connections
    class ConnectionManager
      DROPPED_WARNING = 'was skipped because %<reason>s. That backend will NOT be switched, verified or rolled ' \
                        'back; it is recorded on the tenant state so the switch cannot report itself as fully ' \
                        'verified.'
      HALF_IMPLEMENTED = 'it is only half-implemented (%<message>s)'
      REPORTED_KEY = :console_kit_dropped_reported

      class << self
        def available_handlers(context, dropped = nil)
          handler_classes.filter_map { |klass| resolve(klass, context, dropped) }
        end

        private

        def resolve(klass, context, dropped)
          handler = klass.new(context)
          return handler if handler.available?

          drop(klass, dropped, handler.try(:unavailable_reason))
        rescue NotImplementedError => e
          drop(klass, dropped, format(HALF_IMPLEMENTED, message: e.message))
        end

        def drop(klass, dropped, reason)
          return nil unless reason

          report_dropped(klass, reason)
          dropped << klass.backend_key if dropped
          nil
        end

        def report_dropped(klass, reason)
          Instrumentation.increment('console_kit.handler_dropped')
          return unless unreported?(klass.backend_key, reason)

          Output.print_warning("#{klass} #{format(DROPPED_WARNING, reason: reason)}")
        end

        def unreported?(key, reason)
          reported = Thread.current[REPORTED_KEY] ||= {}
          return false if reported[key] == reason

          reported[key] = reason
          true
        end

        def handler_classes = BaseConnectionHandler.registry
      end
    end
  end
end
