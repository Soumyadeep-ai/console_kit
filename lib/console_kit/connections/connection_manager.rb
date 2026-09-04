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
      COLLISION_WARNING = 'ConsoleKit: %<previous>s and %<current>s both claim the backend key %<key>p. Only ' \
                          '%<current>s will be switched, verified and rolled back.'

      class << self
        def available_handlers(context)
          resolved_classes.filter_map { |klass| resolve(klass, context) }
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

        # `registry` is `descendants`, which keeps every generation of a handler
        # class alive across a code reload, so one backend_key can be claimed
        # twice. Everything downstream - the plan, the undo bundle, the rollback
        # - keys on backend_key, so a duplicate has its snapshot silently
        # discarded while it is still connected and later restored from another
        # instance's snapshot. The newest definition wins, and the result is
        # ordered by backend_key so apply and rollback order no longer depend on
        # Class#subclasses order.
        def resolved_classes
          handler_classes.each_with_object({}) { |klass, by_key| claim(by_key, klass) }.sort.map(&:last)
        end

        def claim(by_key, klass)
          previous = by_key[klass.backend_key]
          report_collision(previous, klass) if collision?(previous, klass)
          by_key[klass.backend_key] = previous.nil? ? klass : preferred(previous, klass)
        end

        # `descendants` order is not definition order, so "the newest wins" is
        # decided by asking which class its own name still resolves to: a stale
        # reload generation resolves to the class that replaced it.
        def preferred(previous, klass) = live?(previous) && !live?(klass) ? previous : klass
        def live?(klass) = klass.name.to_s.safe_constantize.equal?(klass)

        # A second class under the SAME name is a reload generation of the same
        # handler and is expected. Two differently named classes claiming one
        # key is a bug in the host application, so it is reported. Anonymous
        # classes carry no name to compare, so they are left alone.
        def collision?(previous, klass) = !previous.nil? && !previous.name.nil? && previous.name != klass.name

        def report_collision(previous, klass)
          Instrumentation.increment('console_kit.handler_collision')
          Output.print_warning(format(COLLISION_WARNING, previous: previous, current: klass, key: klass.backend_key))
        end

        def handler_classes = BaseConnectionHandler.registry
      end
    end
  end
end
