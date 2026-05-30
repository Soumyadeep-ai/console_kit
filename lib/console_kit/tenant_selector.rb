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
        :abort
      rescue Interrupt
        :abort
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
        input = prompt_user_for_selection(keys.size)
        return resolve_by_integer(input, keys) if valid_integer?(input)

        resolve_by_name(input, keys)
      end

      def partner_code(tenants, key)
        return tenants.dig(key, :constants, :partner_code) || 'N/A' if tenants.is_a?(Hash)

        ConsoleKit.configuration.tenant_resolver_instance.resolve(key)&.dig(:constants, :partner_code) || 'N/A'
      end

      def prompt_user_for_selection(max_index)
        default = max_index.positive? ? '1' : '0'
        Output.print_prompt("\nEnter number or name prefix (default '#{default}'): ")
        normalize_input($stdin.gets&.chomp&.strip, max_index)
      end

      def resolve_by_integer(input, keys)
        index = input.to_i
        return nil if index.zero?

        unless index.between?(1, keys.size)
          Output.print_warning("Selection must be between 0 and #{keys.size}.")
          return :retry
        end

        keys[index - 1]
      end

      def resolve_by_name(input, keys)
        matched = keys.select { |k| k.to_s.downcase.start_with?(input.downcase) }
        case matched.size
        when 1 then matched.first
        when 0
          Output.print_warning("No tenant matches '#{input}'.")
          :retry
        else
          Output.print_warning("Ambiguous: #{matched.map(&:to_s).join(', ')}. Be more specific.")
          :retry
        end
      end

      def normalize_input(raw, max_index)
        return raw unless raw.to_s.empty?

        max_index.positive? ? '1' : '0'
      end

      def valid_integer?(input) = input.match?(/\A\d+\z/)
    end
  end
end

ConsoleKit::LegacyTenantSelector = ConsoleKit::TenantSelector
