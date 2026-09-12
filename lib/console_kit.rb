# frozen_string_literal: true

require 'English'
require 'active_support/core_ext/object/blank'
require 'active_support/core_ext/object/inclusion'
require 'active_support/core_ext/object/try'
require 'active_support/core_ext/string/inflections'
require 'active_support/core_ext/time/calculations'

require_relative 'console_kit/version'
require_relative 'console_kit/errors'
require_relative 'console_kit/tenant_state'
require_relative 'console_kit/instrumentation'
require_relative 'console_kit/configuration'
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

    def pretty_output = configuration.pretty_output

    def pretty_output=(val)
      configuration.pretty_output = val
    end

    def tenants = configuration.tenants

    def tenants=(val)
      configuration.tenants = val
    end

    def context_class = configuration.context_class

    def context_class=(val)
      configuration.context_class = val
    end

    def show_dashboard = configuration.show_dashboard

    def show_dashboard=(val)
      configuration.show_dashboard = val
    end

    def current_tenant = StateStore.tenant_key
    def reset_current_tenant = Setup.reset_current_tenant

    # Programmatic, raising tenant switch. Atomic: on failure the previous
    # tenant state is restored and TenantSwitchError is raised.
    def switch_tenant(key) = TenantSwitch.call(key)

    # Re-verify that every available backend still points at the current tenant.
    # A backend the switch never reached cannot be verified at all, so it is
    # reported here rather than being quietly counted as clean.
    def verify_tenant!
      dropped_now = []
      state = TenantSwitch.verify_current!(dropped_now)
      report_dropped_backends(state, dropped_now)
      state
    end

    # Nested, exception-safe tenant scope. Restores the enclosing tenant on exit.
    def with_tenant(key)
      previous = StateStore.current
      state = TenantSwitch.call(key)
      completed = false
      begin
        result = yield
        completed = true
        result
      ensure
        unwind_scope(state, previous, completed ? nil : $ERROR_INFO)
      end
    end

    def enable_pretty_output = configuration.pretty_output = true
    def disable_pretty_output = configuration.pretty_output = false

    private

    # Raising here instead would be defensible, but it would fire on EVERY
    # verify_tenant! in an application that legitimately ships one broken
    # third-party handler, leaving it no way to verify anything at all - and it
    # would say "a live connection is on the wrong tenant" when the truth is
    # "a backend was never driven". The state carries the list either way.
    # The union of both chances a backend has to be dropped: the switch that
    # committed this state, and the verification that just ran. A handler that
    # was healthy at switch time and has broken since appears only in the
    # second, so reporting only the first called such a tenant fully verified.
    def report_dropped_backends(state, dropped_now)
      dropped = state.dropped_backends | dropped_now
      return if dropped.empty?

      Instrumentation.increment('console_kit.incomplete_verification')
      Output.print_warning(format(INCOMPLETE_VERIFICATION, tenant: state.tenant_key, backends: dropped.join(', ')))
    end

    # A rollback failure raised from an `ensure` would replace the exception the
    # block was already raising, and that exception is the root cause the
    # operator needs. While one is in flight the rollback failure is reported
    # through Output instead; with no block exception it still surfaces.
    def unwind_scope(state, previous, in_flight)
      TenantSwitch.unwind(state, previous)
    rescue RollbackError => e
      raise e if in_flight.nil?

      Output.print_error("#{e.message}\nThis rollback failure did not replace the in-flight " \
                         "#{in_flight.class}: #{in_flight.message}")
    end
  end
end
