# frozen_string_literal: true

require_relative 'connections/diagnostic_helpers'

module ConsoleKit
  # Immutable description of one fully-applied tenant state.
  #
  # A state carries everything needed to *undo* itself: the context values that
  # were present before it was applied and one opaque snapshot per backend.
  class TenantState
    EMPTY_UNDO = { context: {}.freeze, backends: {}.freeze }.freeze

    attr_reader :tenant_key, :constants, :context_values, :undo, :captured_at

    class << self
      def empty = new

      def undo_bundle(context:, backends:)
        { context: context.freeze, backends: backends.freeze }.freeze
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

    # A tenant key has been selected.
    def active? = !@tenant_key.nil?

    # The tenant was applied through a completed, verified TenantSwitch.
    def configured? = @configured
    def undo_context = @undo[:context]
    def undo_backends = @undo[:backends]
    def snapshot_for(backend) = @undo[:backends][backend]
    def age_ms = ((Connections::DiagnosticHelpers.clock_time - @captured_at) * 1000).round(1)

    def to_h
      {
        tenant_key: @tenant_key, configured: @configured,
        context_values: @context_values, backends: @undo[:backends].keys
      }
    end

    def inspect = "#<ConsoleKit::TenantState #{@tenant_key.inspect} backends=#{@undo[:backends].keys.inspect}>"
  end

  # Single source of truth for per-thread tenant state.
  #
  # Everything ConsoleKit knows about "the tenant this thread is on" lives in one
  # thread-local slot holding a TenantState, plus a stack used by nested scopes.
  module StateStore
    STATE_KEY = :console_kit_state
    STACK_KEY = :console_kit_state_stack

    class << self
      def current = Thread.current[STATE_KEY] || TenantState.empty

      def current=(state)
        Thread.current[STATE_KEY] = state
      end

      def tenant_key = current.tenant_key
      def active? = current.active?
      def configured? = current.configured?

      def clear!
        Thread.current[STATE_KEY] = nil
        Thread.current[STACK_KEY] = nil
      end

      def stack = Thread.current[STACK_KEY] ||= []
      def depth = stack.size

      def push(state)
        stack.push(current)
        self.current = state
      end

      def pop
        self.current = stack.pop
      end
    end
  end
end
