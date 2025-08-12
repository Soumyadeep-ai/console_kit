# frozen_string_literal: true

require_relative 'console_kit/version'
require_relative 'console_kit/configuration'
require_relative 'console_kit/setup'
require_relative 'console_kit/railtie' if defined?(Rails::Railtie)

# Main module for console kit
module ConsoleKit
  class Error < StandardError; end

  class << self
    # Expose DSL for configuring ConsoleKit
    def configure
      yield configuration
    end

    def configuration
      Thread.current[:console_kit_configuration] ||= Configuration.new
    end

    def reset_configuration!
      Thread.current[:console_kit_configuration] = nil
    end

    # Optional: Shortcuts to access specific config items
    def pretty_output
      configuration.pretty_output
    end

    def tenants
      configuration.tenants
    end

    def tenants=(value)
      configuration.tenants = value
    end

    def context_class
      configuration.context_class
    end

    def context_class=(value)
      configuration.context_class = value
    end
  end
end
