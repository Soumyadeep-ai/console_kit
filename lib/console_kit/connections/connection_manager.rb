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
        # `BaseConnectionHandler.registry` is explicit registration, not
        # `descendants`, so it is already declaration-ordered and can never hold
        # two live generations of the same backend key - HandlerRegistry sorts
        # that out (and warns) at registration time. Nothing here has to
        # de-duplicate or re-order it.
        #
        # `dropped` is an optional collector. A caller that is about to commit
        # tenant state passes one in, because a dropped backend is left on
        # whatever tenant it was already serving and nothing downstream can
        # discover that from the returned handler list alone.
        def available_handlers(context, dropped = nil)
          handler_classes.filter_map { |klass| resolve(klass, context, dropped) }
        end

        private

        # A handler whose #available? answers false is an optional gem that is
        # simply not loaded, and there is nothing to report. A handler that
        # raises NotImplementedError is broken rather than absent, and dropping
        # it silently is what lets a switch claim success while that backend
        # still serves another tenant, so it is reported before it is dropped.
        def resolve(klass, context, dropped)
          handler = klass.new(context)
          handler if handler.available?
        rescue NotImplementedError => e
          report_dropped(klass, e)
          dropped << klass.backend_key if dropped
          nil
        end

        # The counter records every drop, because an operator watching the
        # metric needs the rate. The warning is printed once per backend per
        # reason: the dashboard reads this same handler list, so an unchanged
        # broken handler reprinted it on every render and buried the table the
        # operator asked for. The durable record is the key on the committed
        # tenant state, which every verification reports again.
        def report_dropped(klass, error)
          Instrumentation.increment('console_kit.handler_dropped')
          return unless unreported?(klass.backend_key, error.message)

          Output.print_warning("#{klass} #{format(DROPPED_WARNING, reason: error.message)}")
        end

        # Per thread, like every other "say this once" note ConsoleKit keeps:
        # one console reporting a drop must not silence another thread's.
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
