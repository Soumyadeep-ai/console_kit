# frozen_string_literal: true

require_relative 'connections/diagnostic_helpers'

module ConsoleKit
  # Minimal internal instrumentation hook.
  #
  # ConsoleKit emits named events with a duration and a payload. Applications can
  # subscribe to forward them to their own logging/metrics stack. No external
  # dependency is introduced and no event is emitted with credentials in it.
  module Instrumentation
    class << self
      def subscribe(&block)
        mutex.synchronize { subscribers << block }
        block
      end

      def unsubscribe(handle)
        mutex.synchronize { subscribers.delete(handle) }
      end

      def clear!
        mutex.synchronize do
          subscribers.clear
          counters.clear
        end
      end

      def counters = @counters ||= Hash.new(0)

      def counts = mutex.synchronize { counters.dup }

      def increment(name, by = 1)
        mutex.synchronize { counters[name] += by }
      end

      def instrument(name, payload = {})
        start = Connections::DiagnosticHelpers.clock_time
        result = yield
        publish(name, elapsed_ms(start), payload.merge(status: :ok))
        result
      rescue StandardError, NotImplementedError => e
        publish(name, elapsed_ms(start), payload.merge(status: :error, error: e.class.name))
        raise
      end

      def publish(name, duration_ms, payload)
        increment(name)
        each_subscriber { |sub| sub.call(name, duration_ms, payload) }
      end

      private

      def each_subscriber
        mutex.synchronize { subscribers.dup }.each do |sub|
          yield(sub)
        rescue StandardError
          nil # a broken subscriber must never break a tenant switch
        end
      end

      def elapsed_ms(start) = ((Connections::DiagnosticHelpers.clock_time - start) * 1000).round(2)
      def subscribers = @subscribers ||= []
      def mutex = @mutex ||= Mutex.new
    end
  end
end
