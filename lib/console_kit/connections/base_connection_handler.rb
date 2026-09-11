# frozen_string_literal: true

require 'active_support/core_ext/string/filters'
require_relative 'diagnostic_helpers'
require_relative '../errors'
require_relative '../output'
require_relative '../instrumentation'
require_relative '../diagnostics'

module ConsoleKit
  module Connections
    # Declaration-ordered list of the connection handler classes ConsoleKit knows about.
    #
    # Registration is explicit - a handler joins when it declares its backend -
    # rather than implicit via Class#descendants. That is what makes a Zeitwerk
    # reload safe at the root: the reloaded generation of a class replaces its
    # own entry in place, so one backend key can never be claimed by two live
    # generations and nothing downstream has to de-duplicate. It also fixes the
    # apply and rollback order at declaration order instead of leaving it to a
    # sort on the key.
    module HandlerRegistry
      COLLISION_WARNING = 'ConsoleKit: %<previous>s and %<current>s both claim the backend key %<key>p. Only ' \
                          '%<current>s will be switched, verified and rolled back.'

      class << self
        # A frozen view. Callers iterate it every switch; handing out the live
        # array would let any of them reorder or empty the registry.
        def all = entries.dup.freeze

        def add(handler_class)
          index = entries.index { |klass| klass.backend_key == handler_class.backend_key }
          return entries << handler_class unless index

          report_collision(entries[index], handler_class)
          entries[index] = handler_class
        end

        def remove(handler_class) = entries.delete(handler_class)

        private

        def entries = @entries ||= []

        # A second class under the SAME name is a reload generation of the same
        # handler and is expected. Two differently named classes claiming one
        # key is a bug in the host application, so it is reported. Anonymous
        # classes carry no name to compare, so they are left alone.
        def report_collision(previous, current)
          return if previous.name.nil? || current.name.nil? || previous.name == current.name

          Instrumentation.increment('console_kit.handler_collision')
          Output.print_warning(format(COLLISION_WARNING, previous: previous, current: current,
                                                         key: current.backend_key))
        end
      end
    end

    # Parent class for connection handlers.
    #
    # A handler is the SINGLE source of truth for its backend. `backend` writes
    # down everything the rest of ConsoleKit needs to know about it - its key,
    # display name, context attribute, tenant-constants key and console label -
    # and `.target_error` is the one rule that decides whether a target value is
    # usable. Nothing outside a handler file names a backend, so adding one
    # means adding one file.
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

      class << self
        attr_reader :backend_key, :display_name, :context_attribute, :constants_key, :detail_label

        # Declares a backend and registers the handler for it.
        def backend(key, display_name:, context_attribute:, constants_key:, detail_label:)
          @backend_key = key
          @display_name = display_name
          @context_attribute = context_attribute
          @constants_key = constants_key
          @detail_label = detail_label
          HandlerRegistry.add(self)
        end

        def registry = HandlerRegistry.all
        def unregister(handler_class) = HandlerRegistry.remove(handler_class)

        # The one rule that answers "can this backend use this target value, and
        # if not why". `#prepare` raises on it and Configuration#validate!
        # collects it, so the two cannot drift. nil means the value is usable.
        def target_error(_value) = nil

        # Shared rule for backends whose target is a plain name.
        def identifier_error(value)
          return if value.nil? || ((value.is_a?(String) || value.is_a?(Symbol)) && value.to_s.strip.present?)

          'expected a non-blank String or Symbol'
        end
      end

      attr_reader :context

      def initialize(context) = @context = context

      def backend_key = self.class.backend_key
      def display_name = self.class.display_name

      # Desired backend value for the current context, or nil to mean "default".
      def target
        attr_name = self.class.context_attribute
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
      def safe_diagnostics(timeout: Diagnostics::DEFAULT_TIMEOUT, level: :basic)
        Diagnostics::Runner.call(self, timeout: timeout, level: level)
      end

      def verification_error(expected, actual, message = nil)
        ConnectionVerificationError.new(
          message, backend: display_name, tenant: nil, expected: expected, actual: actual
        )
      end

      private

      # `#prepare`'s half of the shared rule.
      def validate_target!(target)
        reason = self.class.target_error(target)
        return if reason.nil?

        raise ConfigurationError,
              "ConsoleKit: #{self.class.constants_key} #{target.inspect} is invalid: #{reason}."
      end

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
