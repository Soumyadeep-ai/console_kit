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
      DROPPED_WARNING = 'was skipped because %<reason>s. That backend will NOT be switched, verified or rolled ' \
                        'back; it is recorded on the tenant state so the switch cannot report itself as fully ' \
                        'verified.'
      HALF_IMPLEMENTED = 'it is only half-implemented (%<message>s)'
      REPORTED_KEY = :console_kit_dropped_reported

      class << self
        # `dropped` is an optional collector: a dropped backend is left on
        # whatever tenant it was already serving, and the returned handler list
        # alone cannot show that.
        def available_handlers(context, dropped = nil)
          handler_classes.filter_map { |klass| resolve(klass, context, dropped) }
        end

        private

        # #available? false with no reason is an optional gem that is not loaded.
        # A NotImplementedError is a broken handler, and a reason is a
        # misconfigured one; dropping either silently lets a switch claim success
        # while that backend still serves another tenant.
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

        # Counted every time, warned once per backend per reason: the dashboard
        # reads this same handler list, so an unchanged broken handler would
        # reprint on every render and bury the table.
        def report_dropped(klass, reason)
          Instrumentation.increment('console_kit.handler_dropped')
          return unless unreported?(klass.backend_key, reason)

          Output.print_warning("#{klass} #{format(DROPPED_WARNING, reason: reason)}")
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
