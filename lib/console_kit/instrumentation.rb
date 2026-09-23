# frozen_string_literal: true

require_relative 'connections/diagnostic_helpers'

module ConsoleKit
  module Instrumentation
    class << self
      def subscribe(&block)
        mutex.synchronize { subscribers << block }
        block
      end

      def clear!
        mutex.synchronize do
          subscribers.clear
          counters.clear
        end
      end

      def counters = @counters ||= Hash.new(0)

      def counts = mutex.synchronize { counters.dup }

      def increment(name)
        mutex.synchronize { counters[name] += 1 }
      end

      def instrument(name, payload = {})
        start = Connections::DiagnosticHelpers.clock_time
        yield.tap { publish(name, start, payload.merge(status: :ok)) }
      rescue StandardError, NotImplementedError => e
        publish(name, start, payload.merge(error: e.class.name, status: :error))
        raise
      end

      private

      def publish(name, start, payload)
        increment(name)
        duration_ms = elapsed_ms(start)
        each_subscriber { |sub| sub.call(name, duration_ms, payload) }
      end

      def each_subscriber
        mutex.synchronize { subscribers.dup }.each do |sub|
          yield(sub)
        rescue StandardError
          nil
        end
      end

      def elapsed_ms(start) = ((Connections::DiagnosticHelpers.clock_time - start) * 1000).round(2)
      def subscribers = @subscribers ||= []
      def mutex = @mutex ||= Mutex.new
    end
  end
end
