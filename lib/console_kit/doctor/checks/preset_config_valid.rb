# frozen_string_literal: true

require_relative 'base'

module ConsoleKit
  module Doctor
    module Checks
      # Verifies that each preset only uses known configuration attributes.
      class PresetConfigValid < Base
        VALID_ATTRS = ConsoleKit::Configuration::DEFAULTS.keys.freeze

        def call
          return pass('no presets configured') if config.presets.empty?

          invalid = find_invalid_attrs
          return pass("#{config.presets.size} preset(s) valid") if invalid.empty?

          warn("unknown preset attribute(s): #{invalid.join(', ')}")
        end

        private

        def find_invalid_attrs
          config.presets.values.flat_map(&:keys).map(&:to_sym).uniq - VALID_ATTRS
        end
      end
    end
  end
end
