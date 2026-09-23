# frozen_string_literal: true

require_relative 'diagnostic_helpers'
require_relative '../errors'
require_relative '../output'
require_relative '../instrumentation'
require_relative '../diagnostics'

module ConsoleKit
  module Connections
    # Declaration-ordered map of backend key to the handler class that owns it.
    # Insertion order fixes apply order - and rollback, which is its reverse.
    # Keying by backend_key means a Zeitwerk reload generation replaces its own
    # entry in place instead of adding a second live handler for the backend.
    module HandlerRegistry
      COLLISION_WARNING = 'ConsoleKit: %<previous>s and %<current>s both claim the backend key %<key>p. Only ' \
                          '%<current>s will be switched, verified and rolled back.'
      DUPLICATE_ATTRIBUTE = 'ConsoleKit: %<current>s claims the context attribute %<attribute>p, which %<previous>s ' \
                            'already claims for the %<key>p backend. One attribute is one slot on the context ' \
                            'object, so each backend would write the other values there and the context would ' \
                            'disagree with the live connection. Give %<current>s a context attribute of its own.'

      class << self
        def all = entries.values.freeze

        def add(handler_class)
          key = handler_class.backend_key
          reject_duplicate_attribute(handler_class, key)
          drop_other_keys(handler_class, key)
          report_collision(entries[key], handler_class)
          entries[key] = handler_class
        end

        # Identity-guarded: unregistering a handler that a reload generation has
        # already replaced must not remove its replacement.
        def remove(handler_class)
          key = handler_class.backend_key
          entries.delete(key) if entries[key].equal?(handler_class)
        end

        private

        def entries = @entries ||= {}

        # One class owns one backend key: a class that declares `backend` a
        # second time must not stay registered under its old key as well.
        def drop_other_keys(handler_class, key)
          entries.delete_if { |existing, klass| existing != key && klass.equal?(handler_class) }
        end

        # Refused rather than warned: there is no resolution a switch could pick
        # that leaves the context and the live connections agreeing. A reload
        # generation re-declaring the same backend is not a duplicate.
        def reject_duplicate_attribute(handler_class, key)
          attribute = handler_class.context_attribute
          previous_key, previous_class =
            entries.find { |other, klass| other != key && klass.context_attribute == attribute }
          return if !previous_class || same_declaration?(previous_class, handler_class)

          raise ConfigurationError, format(DUPLICATE_ATTRIBUTE, current: handler_class, previous: previous_class,
                                                                attribute: attribute, key: previous_key)
        end

        def same_declaration?(previous, current)
          previous_name = previous.name
          previous.equal?(current) || (previous_name && previous_name == current.name)
        end

        # A second class under the SAME name is an expected reload generation;
        # two differently named classes claiming one key is a host bug. Anonymous
        # classes carry no name to compare.
        def report_collision(previous, current)
          previous_name = previous&.name
          current_name = current.name
          return unless previous_name && current_name && previous_name != current_name

          Instrumentation.increment('console_kit.handler_collision')
          Output.print_warning(format(COLLISION_WARNING, previous: previous, current: current,
                                                         key: current.backend_key))
        end
      end
    end

    # Parent class for connection handlers: a handler is the single source of
    # truth for its backend. Subclasses implement snapshot / prepare / connect! /
    # verify! / restore so a switch can be applied, proved and rolled back.
    class BaseConnectionHandler
      include DiagnosticHelpers

      class << self
        # Class-level instance variables are NOT inherited: without the fallback
        # a subclass that adds behaviour without re-declaring `backend` would be
        # a handler for no backend at all.
        def backend_key = declaration[:backend_key] || superclass.try(:backend_key)
        def display_name = declaration[:display_name] || superclass.try(:display_name)
        def context_attribute = declaration[:context_attribute] || superclass.try(:context_attribute)
        def constants_key = declaration[:constants_key] || superclass.try(:constants_key)
        def detail_label = declaration[:detail_label] || superclass.try(:detail_label)

        def backend(key, display_name:, context_attribute:, constants_key:, detail_label:)
          @declaration = { backend_key: key, display_name: display_name, context_attribute: context_attribute,
                           constants_key: constants_key, detail_label: detail_label }
          HandlerRegistry.add(self)
        end

        # What `backend` declared on THIS class, empty until it declares any.
        def declaration = @declaration ||= {}

        def registry = HandlerRegistry.all
        def unregister(handler_class) = HandlerRegistry.remove(handler_class)

        # nil means the value is usable. `#prepare` raises on it and
        # Configuration#validate! collects it, so the two cannot drift.
        def target_error(_value) = nil

        def identifier_error(value)
          return if value.nil? || ((value.is_a?(String) || value.is_a?(Symbol)) && value.to_s.strip.present?)

          'expected a non-blank String or Symbol'
        end
      end

      attr_reader :context

      def initialize(context) = @context = context

      def backend_key = self.class.backend_key
      def display_name = self.class.display_name

      # nil means "default".
      def target
        attr_name = self.class.context_attribute
        attr_name && context_attribute(attr_name).presence
      end

      def available? = raise NotImplementedError, "#{self.class} must implement #available?"
      def snapshot = raise NotImplementedError, "#{self.class} must implement #snapshot"
      def connect!(_target) = raise NotImplementedError, "#{self.class} must implement #connect!"
      def restore(_snapshot) = raise NotImplementedError, "#{self.class} must implement #restore"

      # Why `available?` said false, when that is a fault rather than an optional
      # gem nobody installed: a reason is recorded as a dropped backend, nil stays silent.
      def unavailable_reason = nil

      # Override to validate and resolve without mutating anything.
      def prepare(_target) = nil

      # Override to prove the live connection belongs to `target`, raising
      # ConnectionVerificationError on mismatch.
      def verify!(_target) = nil

      # One shape for every backend: an unavailable backend is a row rather than
      # an error, a real fault becomes an error row, and a ConsoleKit bug is
      # re-raised so it reaches the operator as the bug it is.
      def diagnostics(level: :basic)
        return unavailable_diagnostics unless available?

        diagnostics_at(level)
      rescue StandardError => e
        raise e if ConsoleKit.programming_error?(e)

        error_diagnostics(display_name, e)
      end

      # What a cached diagnostic row stays true for, read out of memory rather
      # than over the wire. nil means "nothing outside this thread can move this
      # backend", so a handler whose backend is PROCESS-global must override it.
      def diagnostic_identity = nil

      def safe_diagnostics(timeout: Diagnostics::DEFAULT_TIMEOUT, level: :basic)
        Diagnostics::Runner.call(self, timeout: timeout, level: level)
      end

      def verification_error(expected, actual)
        ConnectionVerificationError.new(
          nil, backend: display_name, tenant: nil, expected: expected, actual: actual
        )
      end

      private

      # NotImplementedError is not a StandardError, so #diagnostics' rescue lets
      # these through: a handler that implements no level is broken, not broken-
      # down, and the manager records it as a dropped backend.
      def diagnostics_at(level) = level == :full ? full_diagnostics : basic_diagnostics

      def basic_diagnostics = raise NotImplementedError, "#{self.class} must implement #basic_diagnostics"
      def full_diagnostics = raise NotImplementedError, "#{self.class} must implement #full_diagnostics"

      # The rejected value is scrubbed: a tenant constant can carry a whole
      # connection URI, and this message may be forwarded to a log.
      def validate_target!(target)
        handler_class = self.class
        reason = handler_class.target_error(target)
        return unless reason

        raise ConfigurationError,
              "ConsoleKit: #{handler_class.constants_key} #{scrub(target.inspect)} is invalid: #{reason}."
      end

      def measure_latency
        start = clock_time
        yield
        ((clock_time - start) * 1000).round(1)
      end

      def context_attribute(name) = @context.try(name)

      def unavailable_diagnostics
        { name: display_name, status: :unavailable, latency_ms: nil, details: {} }
      end
    end
  end
end
