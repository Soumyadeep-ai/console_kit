# lib/console_kit/doctor/checks/hook_callable_arity.rb
# frozen_string_literal: true

require_relative 'base'

module ConsoleKit
  module Doctor
    module Checks
      # Checks that registered lifecycle hooks accept exactly one argument.
      class HookCallableArity < Base
        VALID_ARITIES = [-1, 1].freeze
        HOOK_EVENTS   = %i[before_switch after_switch].freeze

        def call
          issues = collect_issues
          issues.empty? ? pass('hook arities valid') : warn(issues.join('; '))
        end

        private

        def collect_issues
          hooks_hash = config.hook_registry.instance_variable_get(:@hooks)
          HOOK_EVENTS.flat_map { |event| arity_issues_for(hooks_hash[event] || [], event) }
        end

        def arity_issues_for(hooks, event)
          hooks.filter_map do |hook|
            arity = hook.block.arity
            next if VALID_ARITIES.include?(arity)

            "#{config && event} hook arity #{arity} (expected 1 or -1)"
          end
        end
      end
    end
  end
end
