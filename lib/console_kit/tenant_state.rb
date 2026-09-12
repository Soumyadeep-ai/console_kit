# frozen_string_literal: true

require_relative 'connections/diagnostic_helpers'

module ConsoleKit
  # Immutable description of one fully-applied tenant state. Carries everything
  # needed to undo itself, plus the backends it could not drive at all - the one
  # thing it cannot undo, and so the one thing a verification has to report.
  class TenantState
    NO_DROPPED = [].freeze
    EMPTY_UNDO = { context: {}.freeze, backends: {}.freeze, dropped: NO_DROPPED }.freeze

    attr_reader :tenant_key, :constants, :context_values, :undo, :captured_at

    class << self
      def empty = new

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

    def active? = !@tenant_key.nil?

    # The tenant was applied through a completed, verified TenantSwitch.
    def configured? = @configured
    def undo_context = @undo[:context]
    def undo_backends = @undo[:backends]

    # Handlers that exist but are broken, so the switch could not snapshot, apply,
    # verify or roll them back. They are still serving whatever tenant they had.
    def dropped_backends = @undo[:dropped] || NO_DROPPED
    def snapshot_for(backend) = @undo[:backends][backend]
    def age_ms = ((Connections::DiagnosticHelpers.clock_time - @captured_at) * 1000).round(1)

    def inspect = "#<ConsoleKit::TenantState #{@tenant_key.inspect} backends=#{@undo[:backends].keys.inspect}>"
  end

  # Single source of truth for per-thread tenant state: one thread-local slot
  # holding a TenantState. Nesting is unwound by `with_tenant` from its own stack
  # frame, so there is deliberately no second scope stack here to drift out of step.
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
