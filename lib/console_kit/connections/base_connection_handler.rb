# frozen_string_literal: true

require 'active_support/core_ext/class/subclasses'
require 'active_support/core_ext/string/inflections'
require 'active_support/core_ext/string/filters'
require_relative 'diagnostic_helpers'
require_relative '../errors'

module ConsoleKit
  module Connections
    # Parent class for connection handlers.
    #
    # Every handler implements a transactional contract so the tenant switch
    # coordinator can apply a tenant, prove it landed, and undo it on failure:
    #
    #   handler.snapshot        -> opaque previous state (never mutates)
    #   handler.prepare(target) -> validate/resolve only, never mutates
    #   handler.connect!(target)-> apply the tenant
    #   handler.verify!(target) -> prove the live connection belongs to `target`
    #   handler.restore(snap)   -> put the previous state back
    #
    # `connect` is retained as the pre-1.5 entry point and simply applies the
    # target resolved from the context.
    class BaseConnectionHandler
      include DiagnosticHelpers

      # Subclasses override these two constants.
      CONTEXT_ATTRIBUTE = nil
      DISPLAY_NAME = nil

      class << self
        def registry = descendants

        def backend_key
          @backend_key ||= name.to_s.demodulize.delete_suffix('ConnectionHandler').underscore.to_sym
        end

        def display_name = self::DISPLAY_NAME || name.to_s.demodulize.delete_suffix('ConnectionHandler')
        def context_attribute_name = self::CONTEXT_ATTRIBUTE
      end

      attr_reader :context

      def initialize(context) = @context = context

      def backend_key = self.class.backend_key
      def display_name = self.class.display_name

      # Desired backend value for the current context, or nil to mean "default".
      def target
        attr_name = self.class.context_attribute_name
        attr_name && context_attribute(attr_name).presence
      end

      def available? = raise NotImplementedError, "#{self.class} must implement #available?"
      def snapshot = raise NotImplementedError, "#{self.class} must implement #snapshot"
      def connect!(_target) = raise NotImplementedError, "#{self.class} must implement #connect!"
      def restore(_snapshot) = raise NotImplementedError, "#{self.class} must implement #restore"

      # Validate and resolve without mutating anything. Raise ConfigurationError
      # (or UnsupportedBackendError) when the target cannot possibly be applied.
      def prepare(_target) = nil

      # Prove the live connection belongs to `target`. Raise
      # ConnectionVerificationError on mismatch. Handlers that genuinely cannot
      # observe their own identity must say so in their documentation.
      def verify!(_target) = nil

      def connect = connect!(target)
      def diagnostics(level: :basic) = raise NotImplementedError, "#{self.class} must implement #diagnostics"

      # Bounded, leak-free diagnostics execution. Delegates to the shared runner.
      def safe_diagnostics(timeout: 2, level: :basic)
        Diagnostics::Runner.call(self, timeout: timeout, level: level)
      end

      def verification_error(expected, actual, message = nil)
        ConnectionVerificationError.new(
          message, backend: display_name, tenant: nil, expected: expected, actual: actual
        )
      end

      private

      def measure_latency
        start = clock_time
        yield
        ((clock_time - start) * 1000).round(1)
      end

      def context_attribute(name) = @context.try(name)

      def unavailable_diagnostics(name = display_name)
        { name: name, status: :unavailable, latency_ms: nil, details: {} }
      end
    end
  end
end
