# frozen_string_literal: true

# Main module for console kit
module ConsoleKit
  class Error < StandardError; end
end

require_relative 'console_kit/version'
require_relative 'console_kit/fiber_storage'
require_relative 'console_kit/context'
require_relative 'console_kit/hook_registry'
require_relative 'console_kit/configuration'
require_relative 'console_kit/step_registry'
require_relative 'console_kit/pipeline_context'
require_relative 'console_kit/steps/base'
require_relative 'console_kit/steps/env_resolver'
require_relative 'console_kit/steps/safeguard_check'
require_relative 'console_kit/steps/before_hooks'
require_relative 'console_kit/steps/after_hooks'
require_relative 'console_kit/switch_pipeline'
require_relative 'console_kit/setup'
require_relative 'console_kit/tenant_history'
require 'tty-prompt'
require_relative 'console_kit/prompt_builder'
require_relative 'console_kit/steps/tenant_selector'
require_relative 'console_kit/connections/connection_manager'
require_relative 'console_kit/connections/shard_resolver'
require_relative 'console_kit/connections/shard_strategy'
require_relative 'console_kit/connections/shard_strategy_factory'
require_relative 'console_kit/steps/tenant_configurator'
require_relative 'console_kit/prompt'
require_relative 'console_kit/steps/prompt_applier'
require_relative 'console_kit/railtie' if defined?(Rails::Railtie)

module ConsoleKit
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
