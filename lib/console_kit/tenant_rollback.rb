# frozen_string_literal: true

require_relative 'instrumentation'

module ConsoleKit
  # Restores a captured undo bundle after a failed tenant switch. Every component
  # is attempted even when an earlier one fails, and each failure is collected
  # rather than allowed to replace the original root-cause exception.
  class TenantRollback
    EVENT = 'console_kit.rollback'
    MISSING_HANDLER = 'no connection handler is available to restore it, so it may still be serving the tenant ' \
                      'that was being unwound'

    class << self
      # The context object the switch actually moved, not whatever the
      # configuration points at now: a reload or a reconfigure between the switch
      # and the unwind would otherwise write the captured values to a new object
      # and leave the original on the inner tenant. The captured bundle names the
      # slots too, for the same reason the snapshot names the backends: a handler
      # that was available at switch time may be gone now, and re-detecting the
      # attributes would leave its slot on the inner tenant.
      def unwind(state, previous)
        ctx = state.context_object || ConsoleKit.configuration.context_class
        wrapper = TenantConfigurator::ContextWrapper.new(ctx, state.undo_context.keys)
        live, missing = resolve_handlers(state, ctx)
        failures = new(state.undo, wrapper).call(live, missing)
        StateStore.current = previous
        raise RollbackError, failures unless failures.empty?

        previous
      end

      private

      # The snapshot, not live availability, is the authority on what has to be put
      # back: a backend whose handler has disappeared is still on the inner tenant.
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

    # Returns { backend:, error: } for every component that could not be restored;
    # an empty array means the previous state is fully back.
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
