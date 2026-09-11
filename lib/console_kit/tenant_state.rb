# frozen_string_literal: true

require_relative 'connections/diagnostic_helpers'

module ConsoleKit
  # Immutable description of one fully-applied tenant state.
  #
  # A state carries everything needed to *undo* itself: the context values that
  # were present before it was applied and one opaque snapshot per backend - plus
  # the backends it could not drive at all, which is the one thing it cannot
  # undo and therefore the one thing a verification has to report.
  class TenantState
    NO_DROPPED = [].freeze
    EMPTY_UNDO = { context: {}.freeze, backends: {}.freeze, dropped: NO_DROPPED }.freeze

    attr_reader :tenant_key, :constants, :context_values, :undo, :captured_at

    class << self
      def empty = new

      # Everything the switch captured about the process it was about to change:
      # the previous context values, one opaque snapshot per backend it could
      # drive, and the keys of the backends it could NOT drive - the part of the
      # process this bundle is unable to put back.
      def undo_bundle(context:, backends:, dropped: NO_DROPPED)
        { context: context.freeze, backends: backends.freeze, dropped: dropped.freeze }.freeze
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

    # Backends that were never part of this state: handlers that exist but are
    # broken, so the switch could not snapshot, apply, verify or roll them back.
    # They are still serving whatever tenant they were already on.
    def dropped_backends = @undo[:dropped] || NO_DROPPED
    def snapshot_for(backend) = @undo[:backends][backend]
    def age_ms = ((Connections::DiagnosticHelpers.clock_time - @captured_at) * 1000).round(1)

    def inspect = "#<ConsoleKit::TenantState #{@tenant_key.inspect} backends=#{@undo[:backends].keys.inspect}>"
  end

  # Single source of truth for per-thread tenant state.
  #
  # Everything ConsoleKit knows about "the tenant this thread is on" lives in one
  # thread-local slot holding a TenantState. Nesting is unwound by `with_tenant`
  # from its own stack frame, so there is deliberately no second scope stack
  # here to drift out of step with it - and no observable nesting depth.
  module StateStore
    STATE_KEY = :console_kit_state

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
      end
    end
  end
end
