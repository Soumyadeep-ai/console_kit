# frozen_string_literal: true

module ConsoleKit
  # Immutable description of one fully-applied tenant state. Carries everything
  # needed to undo itself, plus the backends it could not drive at all - the one
  # thing it cannot undo, and so the one thing a verification has to report.
  class TenantState
    NO_DROPPED = [].freeze
    EMPTY_UNDO = { context: {}.freeze, backends: {}.freeze, dropped: NO_DROPPED, context_object: nil }.freeze

    attr_reader :tenant_key, :constants, :undo

    # Containers are copied and then frozen: a copy because the constants a switch
    # is handed belong to the application's configuration, and freezing that in
    # place makes a later `configure` or config reload raise FrozenError far from
    # here. A leaf is left alone - it may be a live class or client object, which
    # is neither ours to freeze nor safe to duplicate.
    module OwnCopy
      class << self
        def call(value)
          case value
          when Hash then value.transform_values { |entry| call(entry) }.freeze
          when Array then value.map { |entry| call(entry) }.freeze
          else value
          end
        end
      end
    end

    class << self
      def empty = new

      def undo_bundle(context:, backends:, dropped: NO_DROPPED, context_object: nil)
        { context: OwnCopy.call(context), backends: OwnCopy.call(backends),
          dropped: OwnCopy.call(dropped), context_object: context_object }.freeze
      end
    end

    def initialize(tenant_key: nil, constants: {}, undo: EMPTY_UNDO, configured: false)
      @tenant_key = tenant_key
      @configured = configured
      @constants = OwnCopy.call(constants)
      @undo = undo
      freeze
    end

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

    # Backends this state committed that `live` no longer lists. A dependency
    # unloaded since the switch answers `available?` false with no reason, which
    # nothing outside this record can tell apart from a gem nobody installed.
    def backends_missing_from(live) = @undo[:backends].keys - live

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
      def configured? = current.configured?

      def clear!
        Thread.current.thread_variable_set(STATE_KEY, nil)
      end
    end
  end
end
