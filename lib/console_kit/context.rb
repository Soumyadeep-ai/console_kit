# lib/console_kit/context.rb
# frozen_string_literal: true

require_relative 'fiber_storage'

module ConsoleKit
  # Fiber-local, stack-based context that tracks the currently active tenant and
  # whether the surrounding configuration step has completed successfully. Use
  # +push+/+pop+ to scope a tenant for a block of work, and +mark_configured!+
  # to flag that the tenant's configuration step finished without errors.
  class Context
    CURRENT_KEY = :console_kit_context
    STACK_KEY   = :console_kit_context_stack

    attr_reader :tenant, :configuration_success

    class << self
      def current
        FiberStorage[CURRENT_KEY] ||= new
      end

      def push(tenant_key)
        stack = (FiberStorage[STACK_KEY] ||= [])
        stack.push(current.tenant)
        FiberStorage[CURRENT_KEY] = new(tenant: tenant_key)
      end

      def pop
        stack = FiberStorage[STACK_KEY] ||= []
        previous = stack.pop
        FiberStorage[CURRENT_KEY] = new(tenant: previous)
        previous
      end

      def mark_configured!
        current.mark_configured!
      end

      def reset!
        FiberStorage[CURRENT_KEY]                  = nil
        FiberStorage[STACK_KEY]                    = nil
        FiberStorage[:console_kit_resolved_shard]  = nil
      end
    end

    def initialize(tenant: nil)
      @tenant                = tenant
      @configuration_success = false
    end

    def mark_configured!
      @configuration_success = true
      self
    end

    def configured?
      !!@tenant && @configuration_success
    end
  end
end
