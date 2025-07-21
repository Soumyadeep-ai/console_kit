# frozen_string_literal: true

require_relative 'output'

module ConsoleKit
  # For tenant selection
  module TenantSelector
    class << self
      def select(tenants, keys)
        print_tenant_selection_menu(tenants, keys)

        max_attempts = 3
        max_attempts.times do
          index = prompt_user_for_selection(keys.size)
          return nil if index.zero?
          return keys[index - 1] if index.positive?
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

        unless valid_integer?(input)
          Output.print_warning('Invalid input. Please enter a number.')
          return -1
        end

        parsed_index = input.to_i
        unless parsed_index.between?(0, max_index)
          Output.print_warning("Selection must be between 0 and #{max_index}.")
          return -1
        end

        parsed_index
      end

      def valid_integer?(input)
        input.match?(/\A\d+\z/)
      end
    end
  end
end
