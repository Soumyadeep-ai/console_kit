# frozen_string_literal: true

require_relative 'errors'
require_relative 'tenant_state'
require_relative 'instrumentation'
require_relative 'tenant_rollback'
require_relative 'tenant_plan'
require_relative 'connections/connection_manager'

module ConsoleKit
  class TenantSwitch
    EVENT = 'console_kit.tenant_switch'

    class << self
      def call(tenant_key) = new(tenant_key).call

      def clear(context: nil) = new(nil, context: context).call

      def verify_current!(dropped = nil)
        state = StateStore.current
        raise ConfigurationError, 'No tenant is currently configured.' unless state.configured?

        new(state.tenant_key).send(:verify_committed, state, dropped)
        state
      end

      def unwind(state, previous) = TenantRollback.unwind(state, previous)
    end

    def initialize(tenant_key, context: nil)
      @tenant_key = tenant_key
      @context = context || ConsoleKit.configuration.context_class
      @failing_handler = nil
      @dropped_backends = []
      @handlers = []
    end

    def call
      Instrumentation.instrument(EVENT, tenant: @tenant_key, from: StateStore.tenant_key) { perform }
    end

    private

    attr_reader :tenant_key, :context

    def perform
      plan = TenantPlan.new(tenant_key)
      @handlers = Connections::ConnectionManager.available_handlers(context, @dropped_backends)
      targets = plan.targets_for(@handlers)
      prepare_all(targets)
      run_transaction(plan.constants, targets, snapshot_state)
    end

    def prepare_all(targets)
      @handlers.each { |handler| handler.prepare(targets[handler.backend_key]) }
    end

    def snapshot_state
      snapshots = @handlers.to_h { |handler| [handler.backend_key, handler.snapshot] }
      TenantState.undo_bundle(context: context_wrapper.current_values, backends: snapshots,
                              dropped: @dropped_backends, context_object: context)
    rescue StandardError, NotImplementedError => e
      raise switch_error(e)
    end

    def run_transaction(constants, targets, undo)
      attempted = []
      apply(constants, targets, attempted)
      commit(constants, undo)
    rescue StandardError, NotImplementedError => e
      raise switch_error(e, TenantRollback.new(undo, context_wrapper).call(attempted))
    end

    def apply(constants, targets, attempted)
      context_wrapper.assign(constants, TenantConfigurator.context_mapping)
      connect_all(targets, attempted)
      verify_all(attempted, targets)
    end

    def connect_all(targets, attempted)
      @handlers.each do |handler|
        attempted << handler
        instrument_backend('console_kit.backend_connect', handler) { handler.connect!(targets[handler.backend_key]) }
      end
    end

    def verify_all(handlers, targets)
      handlers.each { |handler| verify_one(handler, targets[handler.backend_key]) }
    end

    def verify_one(handler, target)
      instrument_backend('console_kit.backend_verify', handler) { handler.verify!(target) }
    rescue ConnectionVerificationError => e
      Instrumentation.increment('console_kit.verification_failure')
      raise e
    end

    def instrument_backend(event, handler, &)
      @failing_handler = handler
      Instrumentation.instrument(event, backend: handler.backend_key, tenant: tenant_key, &)
    end

    def commit(constants, undo)
      StateStore.current = TenantState.new(tenant_key: tenant_key, constants: constants, undo: undo,
                                           configured: !tenant_key.nil?)
    end

    def switch_error(error, rollback_failures = [])
      TenantSwitchError.new(
        from_tenant: StateStore.tenant_key, to_tenant: tenant_key, original_error: error,
        backend: error.try(:backend) || @failing_handler&.display_name, rollback_failures: rollback_failures
      )
    end

    def verify_committed(state, dropped = nil)
      handlers = Connections::ConnectionManager.available_handlers(context, dropped)
      dropped&.concat(state.backends_missing_from(handlers.map(&:backend_key)) - dropped)
      verify_all(handlers, TenantPlan.new(state.tenant_key, constants: state.constants).targets_for(handlers))
      nil
    end

    def context_wrapper = @context_wrapper ||= TenantConfigurator::ContextWrapper.for_context(context)
  end
end
