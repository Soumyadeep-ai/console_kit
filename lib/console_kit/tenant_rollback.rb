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

    class << self
      # Undo a committed state, returning the store to `previous`.
      def unwind(state, previous)
        ctx = ConsoleKit.configuration.context_class
        wrapper = TenantConfigurator::ContextWrapper.for_context(ctx)
        failures = new(state.undo, wrapper).call(handlers_for(state, ctx))
        StateStore.current = previous
        raise RollbackError, failures unless failures.empty?

        previous
      end

      private

      def handlers_for(state, ctx)
        Connections::ConnectionManager.available_handlers(ctx)
                                      .select { |handler| state.undo_backends.key?(handler.backend_key) }
      end
    end

    def initialize(undo, context_wrapper)
      @undo = undo
      @context_wrapper = context_wrapper
    end

    # Returns an array of { backend:, error: } for every component that could not
    # be restored. An empty array means the previous state is fully back.
    def call(handlers)
      Instrumentation.increment(EVENT)
      restore_backends(handlers) + restore_context
    end

    private

    attr_reader :undo, :context_wrapper

    def restore_backends(handlers)
      snapshots = undo[:backends]
      handlers.reverse.filter_map do |handler|
        handler.restore(snapshots[handler.backend_key])
        nil
      rescue StandardError => e
        Instrumentation.increment('console_kit.rollback_failure')
        { backend: handler.display_name, error: e }
      end
    end

    def restore_context
      context_wrapper.restore(undo[:context])
      []
    rescue StandardError => e
      Instrumentation.increment('console_kit.rollback_failure')
      [{ backend: 'context', error: e }]
    end
  end
end
