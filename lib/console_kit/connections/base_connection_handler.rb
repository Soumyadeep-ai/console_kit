# frozen_string_literal: true

require 'active_support/core_ext/class/subclasses'
require 'active_support/core_ext/string/inflections'
require 'active_support/core_ext/string/filters'
require_relative 'diagnostic_helpers'

module ConsoleKit
  module Connections
    # Parent class for connection handlers
    class BaseConnectionHandler
      include DiagnosticHelpers

      class << self
        def registry = descendants
      end

      attr_reader :context

      def initialize(context) = @context = context
      def connect = raise NotImplementedError, "#{self.class} must implement #connect"
      def available? = raise NotImplementedError, "#{self.class} must implement #available?"
      def diagnostics = raise NotImplementedError, "#{self.class} must implement #diagnostics"

      def safe_diagnostics(timeout: 2)
        handler_name = self.class.name.demodulize.delete_suffix('ConnectionHandler')
        thread, result_wrapper = spawn_diagnostic_thread(handler_name)

        if thread.join(timeout)
          result_wrapper[:value] || error_diagnostics(handler_name, StandardError.new('Unknown error'))
        else
          thread.kill
          timeout_diagnostics(handler_name, timeout)
        end
      end

      private

      def spawn_diagnostic_thread(handler_name)
        wrapper = { value: nil }
        thread = Thread.new { wrapper[:value] = run_diagnostics_safely(handler_name) }
        [thread, wrapper]
      end

      def run_diagnostics_safely(name)
        diagnostics
      rescue StandardError => exception
        error_diagnostics(name, exception)
      end

      def context_attribute(name)
        @context.respond_to?(name, true) ? @context.send(name) : nil
      end

      def measure_latency
        start = clock_time
        yield
        ((clock_time - start) * 1000).round(1)
      end

      def unavailable_diagnostics(name)
        { name: name, status: :unavailable, latency_ms: nil, details: {} }
      end
    end
  end
end
