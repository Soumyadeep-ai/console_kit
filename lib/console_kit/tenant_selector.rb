# frozen_string_literal: true

require_relative 'output'

module ConsoleKit
  # For tenant selection
  module TenantSelector
    RETRY_LIMIT = 3
    DEFAULT_SELECTION = '1'

    class << self
      def select
        attempt_selection(RETRY_LIMIT)
      end

      private

      def attempt_selection(retries_left)
        return nil if retries_left.zero?

        print_tenant_selection_menu
        selection = parse_user_selection
        selection ? resolve_selection(selection) : attempt_selection(retries_left - 1)
      end

      def print_tenant_selection_menu
        Output.print_header('Multiple tenants detected. Please choose one:')
        Output.print_info('  0. Load without tenant (no tenant configuration)')

        ConsoleKit.tenants.keys.each_with_index do |key, index|
          Output.print_info("  #{index + 1}. #{key} (partner: #{tenant_partner(key)})")
        end
      end

      def tenant_partner(key) = ConsoleKit.tenants.dig(key, :constants, :partner_code) || 'N/A'

      def parse_user_selection
        input = read_input_with_default
        return handle_invalid_input('Invalid input. Please enter a number.') unless valid_integer?(input)

        index = input.to_i
        unless valid_selection_index?(index)
          return handle_invalid_input("Selection must be between 0 and #{max_index}.")
        end

        index
      end

      def read_input_with_default
        prompt_message = "\nEnter the number of the tenant you want " \
                         "(or press Enter for default '#{DEFAULT_SELECTION}'): "
        Output.print_prompt(prompt_message)
        input = $stdin.gets&.chomp&.strip
        input.to_s.empty? ? DEFAULT_SELECTION : input
      end

      def handle_invalid_input(message) = Output.print_warning(message).then { nil }
      def valid_integer?(input) = input.match?(/\A\d+\z/)
      def max_index = ConsoleKit.tenants.size
      def valid_selection_index?(index) = index.between?(0, max_index)

      def resolve_selection(index)
        return nil if index.zero?

        ConsoleKit.tenants.keys[index - 1]
      end
    end
  end
end
