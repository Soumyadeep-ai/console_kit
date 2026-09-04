# frozen_string_literal: true

require 'active_support/core_ext/object/blank'
require 'active_support/core_ext/object/inclusion'
require 'active_support/core_ext/string/inflections'

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
    def verify_tenant! = TenantSwitch.verify_current!

    # Nested, exception-safe tenant scope. Restores the enclosing tenant on exit.
    def with_tenant(key)
      previous = StateStore.current
      state = TenantSwitch.call(key)
      begin
        yield
      ensure
        TenantSwitch.unwind(state, previous)
      end
    end
    def enable_pretty_output = configuration.pretty_output = true
    def disable_pretty_output = configuration.pretty_output = false
  end
end
