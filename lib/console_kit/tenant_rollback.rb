# frozen_string_literal: true

require_relative 'instrumentation'

module ConsoleKit
  class TenantRollback
    EVENT = 'console_kit.rollback'
    MISSING_HANDLER = 'no connection handler is available to restore it, so it may still be serving the tenant ' \
                      'that was being unwound'

    class << self
      def unwind(state, previous)
        failures = restore(state, state.context_object || ConsoleKit.configuration.context_class)
        StateStore.current = previous
        raise RollbackError, failures unless failures.empty?

        previous
      end

      private

      def restore(state, ctx)
        wrapper = TenantConfigurator::ContextWrapper.new(ctx, state.undo_context.keys)
        live, missing = resolve_handlers(state, ctx)
        new(state.undo, wrapper).call(live, missing)
      end

      def resolve_handlers(state, ctx)
        live = Connections::ConnectionManager.available_handlers(ctx)
                                             .to_h { |handler| [handler.backend_key, handler] }
        present, missing = state.undo_backends.keys.partition { |key| live.key?(key) }
        [live.values_at(*present), missing]
      end
    end

    def initialize(undo, context_wrapper)
      @undo = undo
      @context_wrapper = context_wrapper
    end

    def call(handlers, unrestorable = [])
      return [] if undo.nil?

      Instrumentation.increment(EVENT)
      abandoned(unrestorable) + restore_backends(handlers) + restore_context
    end

    private

    attr_reader :undo, :context_wrapper

    def abandoned(keys)
      keys.map { |key| failure(key, UnsupportedBackendError.new("ConsoleKit: #{key} - #{MISSING_HANDLER}.")) }
    end

    def restore_backends(handlers)
      handlers.reverse.filter_map do |handler|
        handler.restore(undo[:backends][handler.backend_key])
        nil
      rescue StandardError, NotImplementedError => e
        failure(handler.display_name, e)
      end
    end

    def restore_context
      context_wrapper.restore(undo[:context])
      []
    rescue StandardError, NotImplementedError => e
      [failure('context', e)]
    end

    def failure(backend, error)
      Instrumentation.increment('console_kit.rollback_failure')
      { backend: backend, error: error }
    end
  end
end
