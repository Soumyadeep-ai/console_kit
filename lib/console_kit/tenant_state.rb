# frozen_string_literal: true

require_relative 'connections/diagnostic_helpers'

module ConsoleKit
  # Immutable description of one fully-applied tenant state. Carries everything
  # needed to undo itself, plus the backends it could not drive at all - the one
  # thing it cannot undo, and so the one thing a verification has to report.
  class TenantState
    NO_DROPPED = [].freeze
    EMPTY_UNDO = { context: {}.freeze, backends: {}.freeze, dropped: NO_DROPPED, context_object: nil }.freeze

    attr_reader :tenant_key, :constants, :context_values, :undo, :captured_at

    class << self
      def empty = new

      def undo_bundle(context:, backends:, dropped: NO_DROPPED, context_object: nil)
        { context: deep_freeze(context), backends: deep_freeze(backends),
          dropped: deep_freeze(dropped), context_object: context_object }.freeze
      end

      private

      # Containers only: a snapshot leaf may be a live class or client object, and
      # freezing one of those would break the application it was read from.
      def deep_freeze(value)
        case value
        when Hash then value.each_value { |entry| deep_freeze(entry) }.freeze
        when Array then value.each { |entry| deep_freeze(entry) }.freeze
        else value
        end
      end
    end

    def initialize(tenant_key: nil, constants: {}, context_values: {}, undo: EMPTY_UNDO, configured: false)
      @tenant_key = tenant_key
      @configured = configured
      @constants = constants.freeze
      @context_values = context_values.freeze
      @undo = undo
      @captured_at = Connections::DiagnosticHelpers.clock_time
      freeze
    end

    def active? = !@tenant_key.nil?

    # The tenant was applied through a completed, verified TenantSwitch.
    def configured? = @configured
    def undo_context = @undo[:context]
    def undo_backends = @undo[:backends]

    # The very context object this state was applied to, so an unwind writes back
    # to it even if the configuration has since been pointed at another one.
    def context_object = @undo[:context_object]

    # Handlers that exist but are broken, so the switch could not snapshot, apply,
    # verify or roll them back. They are still serving whatever tenant they had.
    def dropped_backends = @undo[:dropped] || NO_DROPPED
    def snapshot_for(backend) = @undo[:backends][backend]
    def age_ms = ((Connections::DiagnosticHelpers.clock_time - @captured_at) * 1000).round(1)

    def inspect = "#<ConsoleKit::TenantState #{@tenant_key.inspect} backends=#{@undo[:backends].keys.inspect}>"
  end

  # Single source of truth for per-thread tenant state: one thread variable
  # holding a TenantState. Not `Thread.current[]`, which is fiber-local: the SQL
  # `connected_to` frame this state describes is thread-local, so a fiber must not
  # see an empty state while sharing its thread's connections. Nesting is unwound
  # by `with_tenant` from its own stack frame, so there is deliberately no second
  # scope stack here to drift out of step.
  module StateStore
    STATE_KEY = :console_kit_state

    class << self
      def current = stored || TenantState.empty

      # The stored slot itself: `current` fabricates a fresh TenantState.empty when
      # nothing is set, which would make every identity comparison a miss.
      def stored = Thread.current.thread_variable_get(STATE_KEY)

      def current=(state)
        Thread.current.thread_variable_set(STATE_KEY, state)
      end

      def tenant_key = current.tenant_key
      def active? = current.active?
      def configured? = current.configured?

      def clear!
        Thread.current.thread_variable_set(STATE_KEY, nil)
      end
    end
  end
end
