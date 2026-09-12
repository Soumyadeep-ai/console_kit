# frozen_string_literal: true

require_relative 'counters'

# Runtime `Module#prepend` wrappers used ONLY to observe how many times a few
# specific internal call sites fire during a switch. Nothing under lib/ is
# edited; these wrappers exist only in the benchmark process and simply
# increment a counter before delegating to the real implementation via
# `super`. This is how the "how many times does one switch walk the tenant
# hash / call ctx.public_methods / re-instantiate handlers" questions in the
# brief get an honest, measured answer instead of a guess from reading code.
module ConsoleKitBenchmark
  # Installs the counting wrappers described above.
  module CallCounting
    SAFE_CONSTANTIZE = Module.new do
      def safe_constantize
        Counters.increment(:safe_constantize)
        super
      end
    end

    # ContextWrapper.for_context is where `ctx.public_methods` gets scanned
    # (see ContextWrapper.detect_attributes). Counting calls to `for_context`
    # is a direct proxy for counting that scan, since detect_attributes is
    # private and only ever called from here.
    CONTEXT_WRAPPER_FOR_CONTEXT = Module.new do
      def for_context(ctx)
        Counters.increment(:context_wrapper_for_context)
        super
      end
    end

    # TenantPlan#lookup_constants is the one place a switch walks
    # `ConsoleKit.configuration.tenants` (via Hash#dig).
    TENANT_PLAN_LOOKUP = Module.new do
      private

      def lookup_constants
        Counters.increment(:tenant_hash_lookup)
        super
      end
    end

    # Every connection handler instance is created here - counting this is
    # counting "how many times a switch re-instantiates handlers".
    HANDLER_INIT = Module.new do
      def initialize(*)
        Counters.increment(:handler_instantiation)
        super
      end
    end

    AVAILABLE_HANDLERS_CALL = Module.new do
      def available_handlers(context, dropped = nil)
        Counters.increment(:available_handlers_call)
        super
      end
    end

    class << self
      def install!
        return if @installed

        String.prepend(SAFE_CONSTANTIZE)
        ConsoleKit::TenantConfigurator::ContextWrapper.singleton_class.prepend(CONTEXT_WRAPPER_FOR_CONTEXT)
        ConsoleKit::TenantPlan.prepend(TENANT_PLAN_LOOKUP)
        ConsoleKit::Connections::BaseConnectionHandler.prepend(HANDLER_INIT)
        ConsoleKit::Connections::ConnectionManager.singleton_class.prepend(AVAILABLE_HANDLERS_CALL)
        @installed = true
      end
    end
  end
end
