# frozen_string_literal: true

require_relative 'instrumentation'

module ConsoleKit
  # Restores a captured undo bundle after a failed tenant switch.
  #
  # Every component is attempted even when an earlier one fails, so a single
  # broken backend cannot strand the rest of the process on the new tenant. Each
  # failure is collected and reported rather than swallowed or allowed to replace
  # the original root-cause exception.
  class TenantRollback
    EVENT = 'console_kit.rollback'
    MISSING_HANDLER = 'no connection handler is available to restore it, so it may still be serving the tenant ' \
                      'that was being unwound'

    class << self
      # Undo a committed state, returning the store to `previous`.
      def unwind(state, previous)
        ctx = ConsoleKit.configuration.context_class
        wrapper = TenantConfigurator::ContextWrapper.for_context(ctx)
        live, missing = resolve_handlers(state, ctx)
        failures = new(state.undo, wrapper).call(live, missing)
        StateStore.current = previous
        raise RollbackError, failures unless failures.empty?

        previous
      end

      private

      # The snapshot is the authority on what has to be put back, never live
      # availability: a backend whose handler has disappeared since the switch
      # is still on the inner tenant, so it is reported rather than dropped.
      def resolve_handlers(state, ctx)
        live = Connections::ConnectionManager.available_handlers(ctx)
                                             .to_h { |handler| [handler.backend_key, handler] }
        present, missing = state.undo_backends.keys.partition { |key| live.key?(key) }
        [present.map { |key| live[key] }, missing]
      end
    end

    def initialize(undo, context_wrapper)
      @undo = undo
      @context_wrapper = context_wrapper
    end

    # Returns an array of { backend:, error: } for every component that could not
    # be restored. An empty array means the previous state is fully back.
    # `unrestorable` names the snapshotted backends that have no handler left.
    def call(handlers, unrestorable = [])
      return [] if undo.nil?

      Instrumentation.increment(EVENT)
      abandoned(unrestorable) + restore_backends(handlers) + restore_context
    end

    private

    attr_reader :undo, :context_wrapper

    def abandoned(keys)
      keys.map do |key|
        Instrumentation.increment('console_kit.rollback_failure')
        { backend: key, error: UnsupportedBackendError.new("ConsoleKit: #{key} - #{MISSING_HANDLER}.") }
      end
    end

    def restore_backends(handlers)
      snapshots = undo[:backends]
      handlers.reverse.filter_map do |handler|
        handler.restore(snapshots[handler.backend_key])
        nil
      rescue StandardError, NotImplementedError => e
        Instrumentation.increment('console_kit.rollback_failure')
        { backend: handler.display_name, error: e }
      end
    end

    def restore_context
      context_wrapper.restore(undo[:context])
      []
    rescue StandardError, NotImplementedError => e
      Instrumentation.increment('console_kit.rollback_failure')
      [{ backend: 'context', error: e }]
    end
  end
end
