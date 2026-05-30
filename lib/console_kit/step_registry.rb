# lib/console_kit/step_registry.rb
# frozen_string_literal: true

module ConsoleKit
  # Registry that maintains an ordered list of pipeline step classes.
  module StepRegistry
    # Holds a step class and its sort priority.
    Entry = Struct.new(:klass, :priority, keyword_init: true)

    class << self
      def register(klass, priority:)
        registry << Entry.new(klass: klass, priority: priority)
      end

      def ordered
        registry.sort_by(&:priority).map(&:klass)
      end

      def insert_before(target, entry)
        target_entry = registry.find { |existing| existing.klass == target }
        effective_priority = target_entry ? target_entry.priority - 0.5 : entry.priority
        registry << Entry.new(klass: entry.klass, priority: effective_priority)
      end

      def insert_after(target, entry)
        target_entry = registry.find { |existing| existing.klass == target }
        effective_priority = target_entry ? target_entry.priority + 0.5 : entry.priority
        registry << Entry.new(klass: entry.klass, priority: effective_priority)
      end

      def remove(klass)
        registry.reject! { |entry| entry.klass == klass }
      end

      private

      def registry
        @registry ||= []
      end
    end
  end
end
