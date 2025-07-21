# frozen_string_literal: true

# Core Logic for initial Setup
module ConsoleKit
  class << self
    attr_accessor :tenants, :context_class

    def setup
      return print_error('No tenants configured.') if tenants.nil? || tenants.empty?

      tenant_key = resolve_tenant_key
      return print_error('No tenant selected. Loading without tenant configuration.') unless tenant_key

      initialize_tenant(tenant_key)
    rescue StandardError => e
      handle_setup_error(e)
    end

    def configure
      yield self
    end

    private

    def resolve_tenant_key
      single_tenant? || non_interactive? ? tenants.keys.first : select_tenant(tenants.keys)
    end

    def single_tenant?
      tenants.size == 1
    end

    def non_interactive?
      !$stdin.tty?
    end

    def initialize_tenant(tenant_key)
      configure_tenant(tenant_key)
      print_success("Tenant initialized: #{tenant_key}")
    end

    def handle_setup_error(error)
      print_error("Error setting up tenant: #{error.message}")
      print_backtrace(error)
    end

    def select_tenant(keys)
      print_tenant_selection_menu(keys)

      max_attempts = 3
      max_attempts.times do
        index = prompt_user_for_selection(keys.size)
        return nil if index.zero?

        selected_key = keys[index - 1]
        return selected_key if selected_key
      end

      nil
    end

    def print_tenant_selection_menu(keys)
      print_header('Multiple tenants detected. Please choose one:')
      print_info('  0. Load without tenant (no tenant configuration)')

      keys.each_with_index do |key, index|
        partner = tenants.dig(key, :constants, :partner_code) || 'N/A'
        print_info("  #{index + 1}. #{key} (partner: #{partner})")
      end
    end

    def prompt_user_for_selection(max_index)
      print_prompt("\nEnter the number of the tenant you want (or press Enter for default '1'): ")
      input = $stdin.gets&.chomp&.strip
      input = '1' if input.to_s.empty?

      parsed_index = input.to_i

      unless parsed_index.between?(0, max_index)
        print_warning('Invalid selection. Please try again.')
        return -1
      end

      parsed_index
    end

    def configure_tenant(key)
      config = tenants[key]
      return print_error("No configuration found for tenant: #{key}") unless config

      constants = config[:constants]
      apply_context(constants)
      setup_database_connections

      print_success("Tenant set to: #{key}")
    rescue StandardError => e
      print_error("Failed to configure tenant '#{key}': #{e.message}")
      print_backtrace(e)
    end

    def apply_context(constants)
      context_class.tenant_shard = constants[:shard]
      context_class.tenant_mongo_db = constants[:mongo_db]
      context_class.partner_identifier = constants[:partner_code]
    end

    def setup_database_connections
      ApplicationRecord.establish_connection(context_class.tenant_shard.to_sym)
      Mongoid.override_client(context_class.tenant_mongo_db.to_s)
    end

    def print_error(text)
      print_message("[✗] #{text}", '1;31') # Red
    end

    def print_success(text)
      print_message("[✓] #{text}", '1;32') # Green
    end

    def print_backtrace(exception)
      exception.backtrace.each { |line| print_message("    #{line}", '0;90') } # Dim gray
    end

    def print_header(text)
      print_message("\n=== #{text} ===", '1;34') # Bold Blue
    end

    def print_info(text)
      print_message(text)
    end

    def print_prompt(text)
      print_message(text, '1;36') # Cyan
    end

    def print_warning(text)
      print_message("[!] #{text}", '1;33') # Yellow
    end

    def print_message(text, color = nil)
      msg = "[ConsoleKit] #{text}"
      puts color ? "\e[#{color}m#{msg}\e[0m" : msg
    end
  end
end
