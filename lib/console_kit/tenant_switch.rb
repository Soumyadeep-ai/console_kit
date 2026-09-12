# frozen_string_literal: true

require_relative 'errors'
require_relative 'tenant_state'
require_relative 'instrumentation'
require_relative 'tenant_rollback'
require_relative 'tenant_plan'
require_relative 'connections/connection_manager'

module ConsoleKit
  # Transactional tenant switch coordinator.
  #
  #   validate -> snapshot -> prepare -> apply context -> connect -> verify -> commit
  #
  # Any failure after the snapshot rolls every touched component back to the
  # captured state and raises TenantSwitchError, which preserves both the root
  # cause and any rollback failures. Until #commit runs, the previous tenant is
  # still the observable current tenant.
  class TenantSwitch
    EVENT = 'console_kit.tenant_switch'

    class << self
      def call(tenant_key, context: nil) = new(tenant_key, context: context).call

      def clear(context: nil) = new(nil, context: context).call

      # Re-verify that every available backend still matches the current tenant.
      # Raises ConnectionVerificationError on the first mismatch. The returned
      # state also names the backends the switch never reached, which no amount
      # of verifying the ones it did reach can discover.
      #
      # `dropped` is an optional collector for the backends THIS verification
      # could not drive. A handler that was healthy at switch time and has
      # broken since is dropped here and nowhere else: the committed state
      # cannot know about it, so a caller that reports only `state
      # .dropped_backends` calls such a tenant fully verified.
      def verify_current!(dropped = nil)
        state = StateStore.current
        raise ConfigurationError, 'No tenant is currently configured.' unless state.configured?

        new(state.tenant_key).send(:verify_committed, state, dropped)
        state
      end

      # Undo a committed state, returning the store to `previous`.
      def unwind(state, previous) = TenantRollback.unwind(state, previous)
    end

    def initialize(tenant_key, context: nil)
      @tenant_key = tenant_key
      @context = context || ConsoleKit.configuration.context_class
      @rollback_failures = []
    end

    def call
      Instrumentation.instrument(EVENT, tenant: @tenant_key, from: StateStore.tenant_key) { perform }
    end

    private

    attr_reader :tenant_key, :context

    def perform
      plan = TenantPlan.new(tenant_key)
      @dropped_backends = []
      handlers = Connections::ConnectionManager.available_handlers(context, @dropped_backends)
      targets = plan.targets_for(handlers)
      prepare_all(handlers, targets)
      transact(handlers, targets, plan.constants)
    end

    # --- prepare (no mutation) -----------------------------------------

    def prepare_all(handlers, targets)
      handlers.each { |handler| handler.prepare(targets[handler.backend_key]) }
    end

    # --- apply / verify / commit ---------------------------------------

    def transact(handlers, targets, constants)
      run_transaction(handlers, targets, constants, snapshot_state(handlers))
    end

    # Snapshotting runs before anything has been applied, so a failure here needs
    # no rollback - but it must still surface as a TenantSwitchError carrying its
    # cause rather than escaping raw.
    def snapshot_state(handlers)
      capture_undo(handlers)
    rescue StandardError, NotImplementedError => e
      raise switch_error(e)
    end

    def run_transaction(handlers, targets, constants, undo)
      attempted = []
      apply(handlers, targets, constants, undo, attempted)
    rescue StandardError, NotImplementedError => e
      @rollback_failures = rollback(undo, attempted)
      raise switch_error(e)
    end

    def apply(handlers, targets, constants, undo, attempted)
      context_values = apply_context(constants)
      connect_all(handlers, targets, attempted)
      verify_all(attempted, targets)
      commit(constants, context_values, undo)
    end

    def capture_undo(handlers)
      snapshots = handlers.to_h { |handler| [handler.backend_key, handler.snapshot] }
      TenantState.undo_bundle(context: context_wrapper.current_values, backends: snapshots,
                              dropped: @dropped_backends)
    end

    def apply_context(constants)
      context_wrapper.assign(constants, TenantConfigurator.context_mapping)
    end

    def connect_all(handlers, targets, attempted)
      handlers.each do |handler|
        attempted << handler
        instrument_backend('console_kit.backend_connect', handler) { handler.connect!(targets[handler.backend_key]) }
      end
    end

    def verify_all(handlers, targets)
      handlers.each do |handler|
        instrument_backend('console_kit.backend_verify', handler) { handler.verify!(targets[handler.backend_key]) }
      rescue ConnectionVerificationError => e
        Instrumentation.increment('console_kit.verification_failure')
        raise e
      end
    end

    # Remembers which handler is being applied, so a raw backend error - one the
    # handler did not wrap in a ConnectionError of its own - can still be
    # attributed to the backend that raised it.
    def instrument_backend(event, handler, &)
      @failing_handler = handler
      Instrumentation.instrument(event, backend: handler.backend_key, tenant: tenant_key, &)
    end

    # A clear is a completed switch too, but it commits no tenant: reporting it
    # as configured left `StateStore.configured?` true with no tenant key, so
    # the compat `configuration_success?` answered yes after a clear and
    # `verify_tenant!` cheerfully "verified" the default state.
    def commit(constants, context_values, undo)
      StateStore.current = TenantState.new(tenant_key: tenant_key, constants: constants, undo: undo,
                                           context_values: context_values, configured: !tenant_key.nil?)
    end

    # --- rollback -------------------------------------------------------

    def rollback(undo, handlers)
      TenantRollback.new(undo, context_wrapper).call(handlers)
    end

    def switch_error(error)
      TenantSwitchError.new(
        from_tenant: StateStore.tenant_key, to_tenant: tenant_key, original_error: error,
        backend: error.try(:backend) || @failing_handler&.display_name, rollback_failures: @rollback_failures
      )
    end

    def verify_committed(state, dropped = nil)
      handlers = Connections::ConnectionManager.available_handlers(context, dropped)
      verify_all(handlers, TenantPlan.new(state.tenant_key, constants: state.constants).targets_for(handlers))
      nil
    end

    def context_wrapper = @context_wrapper ||= TenantConfigurator::ContextWrapper.for_context(context)
  end
end
