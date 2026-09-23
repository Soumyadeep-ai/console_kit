# frozen_string_literal: true

require 'English'
# ActiveSupport 6.1 reads Logger::Severity while defining its own logger and
# does not require logger itself, so loading it first is what keeps 6.1 working.
require 'logger'
# The base must load before any core_ext: a leaf file such as
# time/calculations pulls in active_support/duration, which reaches for
# ActiveSupport.deprecator and only finds it once the base is loaded.
require 'active_support'
require 'active_support/core_ext/object/blank'
require 'active_support/core_ext/object/try'
require 'active_support/core_ext/string/inflections'
require 'active_support/core_ext/time/calculations'

require_relative 'console_kit/version'
require_relative 'console_kit/errors'
require_relative 'console_kit/tenant_state'
require_relative 'console_kit/instrumentation'
require_relative 'console_kit/configuration'
require_relative 'console_kit/tenant_orchestrator'
require_relative 'console_kit/setup'
require_relative 'console_kit/console_helpers'
require_relative 'console_kit/prompt'
require_relative 'console_kit/railtie' if defined?(Rails::Railtie)

# Main module for ConsoleKit
module ConsoleKit
  INCOMPLETE_VERIFICATION = 'ConsoleKit: tenant %<tenant>p is verified only for the backends ConsoleKit could ' \
                            'drive. Never switched, verified or rolled back, and possibly still serving another ' \
                            'tenant: %<backends>s.'

  class << self
    def configure = yield(configuration)
    def configuration = @configuration ||= Configuration.new

    def reset_configuration!
      @configuration = nil
      StateStore.clear!
    end

    def tenants = configuration.tenants

    def current_tenant = StateStore.tenant_key
    def reset_current_tenant = TenantOrchestrator.reset

    # Atomic: on failure the previous tenant state is restored and the error raised.
    def switch_tenant(key) = TenantSwitch.call(key)

    def verify_tenant!
      dropped_now = []
      state = TenantSwitch.verify_current!(dropped_now)
      report_dropped_backends(state, dropped_now)
      state
    end

    # Nested, exception-safe tenant scope. Completion is tracked with an explicit
    # flag rather than read from `$ERROR_INFO` (`$!`), which is thread-global and
    # non-nil whenever with_tenant is called from inside another `rescue`.
    def with_tenant(key, &)
      previous = StateStore.current
      state = TenantSwitch.call(key)
      unwind_after(state, previous, &)
    end

    def enable_pretty_output = configuration.pretty_output = true
    def disable_pretty_output = configuration.pretty_output = false

    private

    # The union of both chances a backend has to be dropped: the switch that
    # committed this state, and the verification that just ran.
    def report_dropped_backends(state, dropped_now)
      dropped = state.dropped_backends | dropped_now
      return if dropped.empty?

      Instrumentation.increment('console_kit.incomplete_verification')
      Output.print_warning(format(INCOMPLETE_VERIFICATION, tenant: state.tenant_key, backends: dropped.join(', ')))
    end

    def unwind_after(state, previous)
      completed = false
      yield.tap { completed = true }
    ensure
      unwind_scope(state, previous, completed ? nil : $ERROR_INFO)
    end

    # A rollback failure raised from an `ensure` would replace the exception the
    # block was already raising, and that exception is the root cause the operator
    # needs; while one is in flight the rollback failure goes to Output instead.
    def unwind_scope(state, previous, in_flight)
      TenantSwitch.unwind(state, previous)
    rescue RollbackError => e
      raise e unless in_flight

      Output.print_error("#{e.message}\nThis rollback failure did not replace the in-flight " \
                         "#{in_flight.class}: #{in_flight.message}")
    end
  end
end
