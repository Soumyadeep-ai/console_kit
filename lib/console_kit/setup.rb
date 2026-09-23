# frozen_string_literal: true

require_relative 'configuration'
require_relative 'tenant_orchestrator'

# The 1.4.0 API, kept as delegators until 2.0. Delete this file then.
module ConsoleKit
  # Warns once per name per process, then runs the replacement.
  module Deprecation
    class << self
      def call(name, replacement)
        warned = (@warned ||= {})
        unless warned[name]
          warned[name] = true
          Kernel.warn("ConsoleKit: #{name} is deprecated and will be removed in 2.0. Use #{replacement} instead.")
        end
        yield
      end
    end
  end

  # 1.4.0 entry point for console setup.
  module Setup
    class << self
      def setup = Deprecation.call('Setup.setup', 'TenantOrchestrator.run') { TenantOrchestrator.run }

      def current_tenant
        Deprecation.call('Setup.current_tenant', 'ConsoleKit.current_tenant') { ConsoleKit.current_tenant }
      end

      def current_tenant=(val)
        Deprecation.call('Setup.current_tenant=', 'ConsoleKit.switch_tenant') do
          TenantOrchestrator.current_tenant = val
        end
      end

      def tenant_setup_successful?
        Deprecation.call('Setup.tenant_setup_successful?', 'ConsoleKit.current_tenant') do
          !ConsoleKit.current_tenant.to_s.empty?
        end
      end

      def reapply = Deprecation.call('Setup.reapply', 'TenantOrchestrator.reapply') { TenantOrchestrator.reapply }

      def reset_current_tenant
        Deprecation.call('Setup.reset_current_tenant', 'ConsoleKit.reset_current_tenant') do
          ConsoleKit.reset_current_tenant
        end
      end

      def auto_select?
        Deprecation.call('Setup.auto_select?', 'TenantOrchestrator.auto_select?') { TenantOrchestrator.auto_select? }
      end
    end
  end

  class << self
    %i[pretty_output context_class show_dashboard].each do |name|
      define_method(name) do
        Deprecation.call("ConsoleKit.#{name}", "ConsoleKit.configuration.#{name}") { configuration.public_send(name) }
      end
    end

    %i[pretty_output tenants context_class show_dashboard].each do |name|
      define_method(:"#{name}=") do |val|
        Deprecation.call("ConsoleKit.#{name}=", "ConsoleKit.configuration.#{name}=") do
          configuration.public_send(:"#{name}=", val)
        end
      end
    end
  end

  # 1.4.0 non-raising validation.
  class Configuration
    def validate
      Deprecation.call('Configuration#validate', 'Configuration#validate!') do
        validate!
        true
      rescue Error
        false
      end
    end
  end
end
