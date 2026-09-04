# frozen_string_literal: true

module ConsoleKitBenchmark
  # A plain call counter used by the fakes and by CallCounting to record how
  # many times something happened. Kept dead simple on purpose: this is the
  # thing the whole benchmark suite trusts to produce honest counts, so it
  # must not itself be clever.
  module Counters
    class << self
      def reset! = store.clear
      def increment(name) = store[name] += 1
      def count(name) = store[name]
      def snapshot = store.dup

      private

      def store = @store ||= Hash.new(0)
    end
  end
end
