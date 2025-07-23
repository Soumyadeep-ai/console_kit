# frozen_string_literal: true

require_relative 'output'

module ConsoleKit
  # For tenant selection
  module TenantSelector
    class << self
      def select(tenants, keys)
        print_tenant_selection_menu(tenants, keys)

        max_attempts = 3
        max_attempts.times do |attempt|
          index = prompt_user_for_selection(keys.size)
          return nil if index.zero?
          return keys[index - 1] if index.positive?

          print_tenant_selection_menu(tenants, keys) if attempt < max_attempts - 1
        end

        nil
      end

      private

      def print_tenant_selection_menu(tenants, keys)
        Output.print_header('Multiple tenants detected. Please choose one:')
        Output.print_info('  0. Load without tenant (no tenant configuration)')

        keys.each_with_index do |key, index|
          partner = tenants.dig(key, :constants, :partner_code) || 'N/A'
          Output.print_info("  #{index + 1}. #{key} (partner: #{partner})")
        end
      end

      def prompt_user_for_selection(max_index)
        Output.print_prompt("\nEnter the number of the tenant you want (or press Enter for default '1'): ")
        input = $stdin.gets&.chomp&.strip
        input = '1' if input.to_s.empty?

        return invalid_input_response unless valid_integer?(input)

        parsed_index = input.to_i
        return invalid_range_response(max_index) unless parsed_index.between?(0, max_index)

        parsed_index
      end

      def valid_integer?(input)
        input.match?(/\A\d+\z/)
      end

      def invalid_input_response
        Output.print_warning('Invalid input. Please enter a number.')
        -1
      end

      def invalid_range_response(max_index)
        Output.print_warning("Selection must be between 0 and #{max_index}.")
        -1
      end
    end
  end
end
