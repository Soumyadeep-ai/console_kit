# frozen_string_literal: true

require_relative 'errors'
require_relative 'tenant_state'
require_relative 'instrumentation'
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
      # Raises ConnectionVerificationError on the first mismatch.
      def verify_current!
        state = StateStore.current
        raise ConfigurationError, 'No tenant is currently configured.' unless state.configured?

        new(state.tenant_key).send(:verify_committed, state)
      end

      # Undo a committed state, returning the store to `previous`.
      def unwind(state, previous)
        switcher = new(nil, context: ConsoleKit.configuration.context_class)
        failures = switcher.send(:restore_undo, state.undo, handlers_for(state))
        StateStore.current = previous
        raise RollbackError, failures unless failures.empty?

        previous
      end

      private

      def handlers_for(state)
        Connections::ConnectionManager.available_handlers(ConsoleKit.configuration.context_class)
                                     .select { |h| state.undo_backends.key?(h.backend_key) }
      end
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
      constants = resolve_constants
      handlers = Connections::ConnectionManager.available_handlers(context)
      targets = resolve_targets(constants, handlers)
      prepare_all(handlers, targets)
      transact(handlers, targets, constants)
    end

    # --- validate -------------------------------------------------------

    def resolve_constants
      return {} if tenant_key.nil?

      tenants = ConsoleKit.configuration.tenants
      constants = tenants.is_a?(Hash) ? tenants.dig(tenant_key, :constants) : nil
      raise TenantNotFoundError, "No configuration found for tenant: #{tenant_key}" unless constants

      validate_constants!(constants)
      constants
    end

    def validate_constants!(constants)
      missing = %i[shard partner_code] - constants.keys
      return if missing.empty?

      raise ConfigurationError, "Tenant #{tenant_key.inspect} constants missing keys: #{missing.join(', ')}"
    end

    def resolve_targets(constants, handlers)
      handlers.to_h do |handler|
        attr_name = handler.class.context_attribute_name
        [handler.backend_key, attr_name && constants[TenantConfigurator::CONTEXT_MAPPING[attr_name]].presence]
      end
    end

    # --- prepare (no mutation) -----------------------------------------

    def prepare_all(handlers, targets)
      handlers.each { |handler| handler.prepare(targets[handler.backend_key]) }
    end

    # --- apply / verify / commit ---------------------------------------

    def transact(handlers, targets, constants)
      undo = capture_undo(handlers)
      attempted = []
      begin
        context_values = apply_context(constants)
        connect_all(handlers, targets, attempted)
        verify_all(attempted, targets)
        commit(constants, context_values, undo)
      rescue StandardError => e
        @rollback_failures = restore_undo(undo, attempted)
        raise switch_error(e)
      end
    end

    def capture_undo(handlers)
      TenantState.undo_bundle(
        context: context_wrapper.current_values,
        backends: handlers.to_h { |handler| [handler.backend_key, handler.snapshot] }
      )
    end

    def apply_context(constants)
      context_wrapper.assign(constants, TenantConfigurator::CONTEXT_MAPPING)
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

    def instrument_backend(event, handler, &)
      Instrumentation.instrument(event, backend: handler.backend_key, tenant: tenant_key, &)
    end

    def commit(constants, context_values, undo)
      StateStore.current = TenantState.new(
        tenant_key: tenant_key, constants: constants, context_values: context_values, undo: undo, configured: true
      )
    end

    # --- rollback -------------------------------------------------------

    def restore_undo(undo, handlers)
      failures = restore_backends(undo[:backends], handlers)
      failures.concat(restore_context(undo[:context]))
      Instrumentation.increment('console_kit.rollback') unless handlers.empty?
      failures
    end

    def restore_backends(snapshots, handlers)
      handlers.reverse.filter_map do |handler|
        handler.restore(snapshots[handler.backend_key])
        nil
      rescue StandardError => e
        { backend: handler.display_name, error: e }
      end
    end

    def restore_context(values)
      context_wrapper.restore(values)
      []
    rescue StandardError => e
      [{ backend: 'context', error: e }]
    end

    def switch_error(error)
      TenantSwitchError.new(
        from_tenant: StateStore.tenant_key, to_tenant: tenant_key, original_error: error,
        backend: error.try(:backend), rollback_failures: @rollback_failures
      )
    end

    def verify_committed(state)
      handlers = Connections::ConnectionManager.available_handlers(context)
      targets = resolve_targets(state.constants, handlers)
      verify_all(handlers, targets)
      true
    end

    def context_wrapper = @context_wrapper ||= TenantConfigurator::ContextWrapper.for_context(context)
  end
end
