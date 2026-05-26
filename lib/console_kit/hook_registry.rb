# lib/console_kit/hook_registry.rb
# frozen_string_literal: true

module ConsoleKit
  # Raised when a hook registered with on_error: :abort raises an error.
  class HookError < Error; end

  # Registry for lifecycle hooks attached to console switch events.
  class HookRegistry
    # Internal struct representing a single registered hook.
    Hook = Struct.new(:event, :block, :on_error, keyword_init: true)

    def initialize
      @hooks = Hash.new { |hash, key| hash[key] = [] }
    end

    def register(event, on_error: :abort, &block)
      raise ArgumentError, 'on_error must be :abort or :warn' unless %i[abort warn].include?(on_error)

      @hooks[event] << Hook.new(event: event, block: block, on_error: on_error)
    end

    def run(event, tenant)
      @hooks[event].each do |hook|
        hook.block.call(tenant)
      rescue StandardError => e
        handle_hook_error(hook, event, e.message)
      end
    end

    private

    def handle_hook_error(hook, event, message)
      case hook.on_error
      when :abort
        raise HookError, "#{event} hook failed: #{message}"
      when :warn
        Output.print_warning("#{event} hook error (continuing): #{message}")
      end
    end
  end
end
