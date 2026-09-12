# frozen_string_literal: true

require 'active_support/core_ext/string/filters'
require_relative 'diagnostic_helpers'
require_relative '../errors'
require_relative '../output'
require_relative '../instrumentation'
require_relative '../diagnostics'

module ConsoleKit
  module Connections
    # Declaration-ordered map of backend key to the handler class that owns it.
    #
    # Keying by backend_key rather than scanning a list makes "one live handler
    # per backend" structurally impossible to violate instead of something that
    # has to be detected: a reloaded generation replaces its own entry, in place,
    # keeping its declaration position. Ruby preserves insertion order, so apply
    # order - and therefore rollback order, which is its reverse - stays fixed at
    # declaration order.
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
        # A frozen snapshot. `Hash#values` already copies, so the registry itself
        # was never reachable through this - the freeze is about the copy: it
        # stops a caller mutating what it was handed and then reasoning about it
        # as though it still described the registry.
        def all = entries.values.freeze

        def add(handler_class)
          key = handler_class.backend_key
          drop_other_keys(handler_class, key)
          previous = entries[key]
          report_collision(previous, handler_class) if previous
          entries[key] = handler_class
        end

        # Keyed removal, guarded by identity: unregistering a handler that has
        # already been replaced by a reload generation must not remove the
        # generation that replaced it.
        def remove(handler_class)
          key = handler_class.backend_key
          entries.delete(key) if entries[key].equal?(handler_class)
        end

        private

        def entries = @entries ||= {}

        # One class owns one backend key. A class that declares `backend` a
        # second time - a reopened class body, or a reload generation that
        # renamed its key - used to stay registered under the old key as well,
        # so a single handler was switched, verified and rolled back twice and
        # `remove` could only ever take half of it out again.
        def drop_other_keys(handler_class, key)
          entries.delete_if { |existing, klass| existing != key && klass.equal?(handler_class) }
        end

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
        # Class-level instance variables are NOT inherited, so a subclass that
        # adds behaviour without re-declaring `backend` has none of these of its
        # own. It is a specialisation of its parent's backend, so it reads its
        # parent's declaration: answering nil instead made it a handler for no
        # backend at all, whose `#connect` reset its parent's backend to the
        # default without a word. Registration still happens only on an explicit
        # `backend` call, so an undeclared subclass joins no registry and cannot
        # displace the parent it borrows from.
        def backend_key = @backend_key || superclass.try(:backend_key)
        def display_name = @display_name || superclass.try(:display_name)
        def context_attribute = @context_attribute || superclass.try(:context_attribute)
        def constants_key = @constants_key || superclass.try(:constants_key)
        def detail_label = @detail_label || superclass.try(:detail_label)

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

      # What a cached diagnostic row stays true for: the backend's own observed
      # identity, read out of memory rather than over the wire. nil means
      # "nothing outside this thread can move this backend", which is what the
      # diagnostics cache assumes by default - it already discards every row
      # when this thread's TenantState changes. A handler whose backend is
      # PROCESS-global must override it, or a foreign thread moving that backend
      # leaves this thread reporting a tenant the process has already left.
      def diagnostic_identity = nil

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

      # `#prepare`'s half of the shared rule. The rejected value is scrubbed for
      # the same reason ConfigurationValidator scrubs it on its half: a tenant
      # constant can carry a whole connection URI, and this message is printed
      # and may be forwarded to a log.
      def validate_target!(target)
        reason = self.class.target_error(target)
        return if reason.nil?

        raise ConfigurationError,
              "ConsoleKit: #{self.class.constants_key} #{scrub(target.inspect)} is invalid: #{reason}."
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
