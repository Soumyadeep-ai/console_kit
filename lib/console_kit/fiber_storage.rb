# frozen_string_literal: true

module ConsoleKit
  # Abstraction for storing values in fiber-local storage, with fallback to thread-local storage
  # for Ruby versions that don't support fiber-local variables.
  module FiberStorage
    class << self
      def [](key)
        storage[key]
      end

      def []=(key, val)
        storage[key] = val
      end

      private

      def storage
        fiber_capable? ? Fiber.current : Thread.current
      end

      def fiber_capable?
        @fiber_capable ||= detect_fiber_capability
      end

      def detect_fiber_capability
        Fiber.current.respond_to?(:[])
      rescue StandardError
        false
      end
    end
  end
end
