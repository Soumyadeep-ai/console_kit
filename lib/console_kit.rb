# frozen_string_literal: true

require 'active_support/core_ext/object/blank'
require 'active_support/core_ext/object/inclusion'
require 'active_support/core_ext/string/inflections'

require_relative 'console_kit/version'
require_relative 'console_kit/configuration'
require_relative 'console_kit/setup'
require_relative 'console_kit/console_helpers'
require_relative 'console_kit/prompt'
require_relative 'console_kit/railtie' if defined?(Rails::Railtie)

# Main module for ConsoleKit
module ConsoleKit
  # Base error class for ConsoleKit-related exceptions.
  class Error < StandardError; end

  class << self
    def configure = yield(configuration)
    def configuration = @configuration ||= Configuration.new

    def reset_configuration!
      @configuration = nil
      Setup.current_tenant = nil
      TenantConfigurator.configuration_success = false if defined?(TenantConfigurator)
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

    def current_tenant = Setup.current_tenant
    def reset_current_tenant = Setup.reset_current_tenant
    def enable_pretty_output = configuration.pretty_output = true
    def disable_pretty_output = configuration.pretty_output = false
  end
end
