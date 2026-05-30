# frozen_string_literal: true

require_relative 'base'

module ConsoleKit
  module Steps
    # Applies a named configuration preset when CONSOLE_KIT_ROLE is set.
    # Runs before EnvResolver so preset overrides (e.g. tenants) are in effect
    # during all subsequent steps.
    class PresetApplier < Base
      register priority: 8

      ROLE_ENV_KEY = 'CONSOLE_KIT_ROLE'

      def call
        role = ENV.fetch(ROLE_ENV_KEY, nil)
        return success unless role

        preset = config.presets[role.to_sym] || config.presets[role]
        return failure("CONSOLE_KIT_ROLE='#{role}' not found in configured presets") unless preset

        apply_preset(preset, role)
        success
      end

      private

      def apply_preset(preset, role)
        preset.each { |attr, value| config.public_send(:"#{attr}=", value) }
        Output.print_info("Preset active: #{role}")
      end
    end
  end
end
