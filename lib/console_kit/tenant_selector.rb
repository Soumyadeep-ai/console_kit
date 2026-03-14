# frozen_string_literal: true

require_relative 'output'

module ConsoleKit
  # For tenant selection
  module TenantSelector
    RETRY_LIMIT = 3
    DEFAULT_SELECTION = '1'

    class << self
      def select
        RETRY_LIMIT.times do
          result = attempt_selection
          return result unless result == :retry
        end
        nil
      end

      private

      def attempt_selection
        print_tenant_selection_menu
        selection = parse_user_selection
        return :abort if selection == :abort
        return :retry unless selection

        selection.is_a?(Integer) ? resolve_selection(selection) : selection
      end

      def print_tenant_selection_menu
        Output.print_header('Multiple tenants detected. Please choose one:')
        Output.print_list(menu_items)
      end

      def menu_items
        items = ['0. Skip (load without tenant configuration)']
        ConsoleKit.tenants.keys.each_with_index do |key, index|
          items << "#{index + 1}. #{key} (partner: #{tenant_partner(key)})"
        end
        items
      end

      def tenant_partner(key) = ConsoleKit.tenants.dig(key, :constants, :partner_code) || 'N/A'

      def parse_user_selection
        input = read_input_with_default
        return :abort if input == :abort
        return :exit if %w[exit quit].include?(input.downcase)
        return find_tenant_by_name(input) unless valid_integer?(input)

        validate_index_range(input.to_i)
      end

      def find_tenant_by_name(input)
        match = ConsoleKit.tenants.keys.find { |k| k.to_s.casecmp(input).zero? }
        return match if match

        handle_invalid_input("Invalid selection: '#{input}'. Please enter a number or tenant name.")
      end

      def validate_index_range(index)
        unless valid_selection_index?(index)
          return handle_invalid_input("Selection must be between 0 and #{max_index}.")
        end

        index
      end

      def read_input_with_default
        Output.print_prompt("Selection (number or name) [#{DEFAULT_SELECTION}]: ")
        raw_input = $stdin.gets
        raw_input ? normalize_input(raw_input) : :abort
      rescue Interrupt
        :abort
      end

      def normalize_input(raw_input)
        input = raw_input.chomp.strip
        input.empty? ? DEFAULT_SELECTION : input
      end

      def handle_invalid_input(message) = Output.print_warning(message).then { nil }
      def valid_integer?(input) = input.match?(/\A\d+\z/)
      def max_index = ConsoleKit.tenants.size
      def valid_selection_index?(index) = index.between?(0, max_index)

      def resolve_selection(index)
        return :none if index.zero?

        ConsoleKit.tenants.keys[index - 1]
      end
    end
  end
end
