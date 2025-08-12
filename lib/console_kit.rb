# frozen_string_literal: true

require_relative 'console_kit/version'
require_relative 'console_kit/configuration'
require_relative 'console_kit/setup'
require_relative 'console_kit/railtie' if defined?(Rails::Railtie)

# Main module for console kit
module ConsoleKit
  class Error < StandardError; end

  class << self
    def configure = yield(configuration)

    def configuration = Thread.current[:console_kit_configuration] ||= Configuration.new
    def reset_configuration! = Thread.current[:console_kit_configuration] = nil

    %i[pretty_output tenants context_class].each do |name|
      define_method(name) { configuration.public_send(name) }
      define_method("#{name}=") { |val| configuration.public_send("#{name}=", val) }
    end

    def current_tenant = Setup.current_tenant
    def reset_current_tenant = Setup.reset_current_tenant

    def enable_pretty_output = configuration.pretty_output = true
    def disable_pretty_output = configuration.pretty_output = false
  end
end
