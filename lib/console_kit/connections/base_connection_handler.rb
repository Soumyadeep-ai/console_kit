# frozen_string_literal: true

require 'active_support/core_ext/class/subclasses'

module ConsoleKit
  module Connections
    # Parent class for connection handlers
    class BaseConnectionHandler
      class << self
        def registry = descendants
      end

      attr_reader :context

      def initialize(context) = @context = context
      def connect = raise NotImplementedError, "#{self.class} must implement #connect"
      def available? = raise NotImplementedError, "#{self.class} must implement #available?"
      def diagnostics = raise NotImplementedError, "#{self.class} must implement #diagnostics"

      def safe_diagnostics(timeout: 2)
        result = nil
        thread = Thread.new { result = diagnostics }
        unless thread.join(timeout)
          thread.kill
          return { name: self.class.name.demodulize.delete_suffix('ConnectionHandler'), status: :timeout,
                   latency_ms: nil, details: { error: "Timed out after #{timeout}s" } }
        end
        result
      end

      private

      def context_attribute(name)
        @context.respond_to?(name) ? @context.public_send(name) : nil
      end

      def measure_latency
        start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        yield
        ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) * 1000).round(1)
      end

      def unavailable_diagnostics(name)
        { name: name, status: :unavailable, latency_ms: nil, details: {} }
      end

      def error_diagnostics(name, error)
        { name: name, status: :error, latency_ms: nil, details: { error: error.message.truncate(60) } }
      end
    end
  end
end
