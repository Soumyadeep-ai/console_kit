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
                        'switched, verified or rolled back; it is recorded on the tenant state so the switch ' \
                        'cannot report itself as fully verified.'
      REPORTED_KEY = :console_kit_dropped_reported

      class << self
        # `dropped` is an optional collector: a dropped backend is left on
        # whatever tenant it was already serving, and the returned handler list
        # alone cannot show that.
        def available_handlers(context, dropped = nil)
          handler_classes.filter_map { |klass| resolve(klass, context, dropped) }
        end

        private

        # #available? false is an optional gem that is not loaded. A
        # NotImplementedError is a broken handler, and dropping it silently lets
        # a switch claim success while that backend still serves another tenant.
        def resolve(klass, context, dropped)
          handler = klass.new(context)
          handler if handler.available?
        rescue NotImplementedError => e
          report_dropped(klass, e)
          dropped << klass.backend_key if dropped
          nil
        end

        # Counted every time, warned once per backend per reason: the dashboard
        # reads this same handler list, so an unchanged broken handler would
        # reprint on every render and bury the table.
        def report_dropped(klass, error)
          Instrumentation.increment('console_kit.handler_dropped')
          return unless unreported?(klass.backend_key, error.message)

          Output.print_warning("#{klass} #{format(DROPPED_WARNING, reason: error.message)}")
        end

        # Per thread: one console reporting a drop must not silence another's.
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
