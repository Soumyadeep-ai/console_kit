# frozen_string_literal: true

require_relative 'output'

module ConsoleKit
  # For tenant selection
  module TenantSelector
    MAX_ATTEMPTS = 3
    private_constant :MAX_ATTEMPTS

    class << self
      def select(tenants = nil, keys = nil)
        config = ConsoleKit.configuration
        tenants ||= config.tenants
        keys ||= (tenants == :dynamic ? [] : config.tenant_resolver_instance.all_keys)
        MAX_ATTEMPTS.times do
          result = attempt_with_menu(tenants, keys)
          return result unless result == :retry
        end
        nil
      end

      private

      def attempt_with_menu(tenants, keys)
        Output.print_header('Multiple tenants detected. Please choose one:')
        Output.print_info('  0. Load without tenant (no tenant configuration)')
        keys.each_with_index do |key, idx|
          Output.print_info("  #{idx + 1}. #{key} (partner: #{partner_code(tenants, key)})")
        end
        attempt_selection(keys)
      end

      def attempt_selection(keys)
        index = prompt_user_for_selection(keys.size)
        return nil if index.zero?
        return keys[index - 1] if index.positive?

        :retry
      end

      def partner_code(tenants, key)
        return tenants.dig(key, :constants, :partner_code) || 'N/A' if tenants.is_a?(Hash)

        ConsoleKit.configuration.tenant_resolver_instance.resolve(key)&.dig(:constants, :partner_code) || 'N/A'
      end

      def prompt_user_for_selection(max_index)
        Output.print_prompt("\nEnter the number of the tenant you want (or press Enter for default '1'): ")
        input = normalize_input($stdin.gets&.chomp&.strip)
        return invalid_input_response unless valid_integer?(input)

        validate_range(input.to_i, max_index)
      end

      def validate_range(parsed, max_index)
        return invalid_range_response(max_index) unless parsed.between?(0, max_index)

        parsed
      end

      def normalize_input(raw)
        raw.to_s.empty? ? '1' : raw
      end

      def valid_integer?(input) = input.match?(/\A\d+\z/)
      def invalid_input_response = Output.print_warning('Invalid input. Please enter a number.').then { -1 }

      def invalid_range_response(max_index)
        Output.print_warning("Selection must be between 0 and #{max_index}.")
        -1
      end
    end
  end
end

ConsoleKit::LegacyTenantSelector = ConsoleKit::TenantSelector
