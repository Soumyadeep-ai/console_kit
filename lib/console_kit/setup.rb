# frozen_string_literal: true

module ConsoleKit
  class << self
    attr_accessor :tenants, :context_class

    def setup
      return print_error("No tenants configured.") if tenants.nil? || tenants.empty?

      tenant_key = tenants.size == 1 || !$stdin.tty? ? tenants.keys.first : select_tenant(tenants.keys)
      return print_error("No tenant selected. Loading without tenant configuration.") unless tenant_key

      configure_tenant(tenant_key)
      print_success("Tenant initialized: #{tenant_key}")
    rescue StandardError => e
      print_error("Error setting up tenant: #{e.message}")
      print_backtrace(e)
    end

    def configure
      yield self
    end

    private

    def select_tenant(keys)
      print_header("Multiple tenants detected. Please choose one:")
      print_info("  0. Load without tenant (no tenant configuration)")
      keys.each_with_index do |key, index|
        partner = tenants.dig(key, :constants, :partner_code) || 'N/A'
        print_info("  #{index + 1}. #{key} (partner: #{partner})")
      end

      max_attempts = 3
      selected_key = nil

      max_attempts.times do
        print_prompt("\nEnter the number of the tenant you want (or press Enter for default '1'): ")
        input = $stdin.gets&.chomp&.strip

        input = '1' if input.to_s.empty?

        unless (index = input.to_i) && index.between?(0, keys.size)
          print_warning("Invalid selection. Please try again.")
          next
        end

        return nil if index.zero?

        selected_key = keys[index - 1]
        break
      end

      selected_key
    end

    def configure_tenant(key)
      config = tenants[key]
      constants = config[:constants]

      tenant_shard = constants[:shard]
      tenant_mongo_db = constants[:mongo_db]

      context_class.tenant_shard = tenant_shard
      context_class.tenant_mongo_db = tenant_mongo_db
      context_class.partner_identifier = constants[:partner_code]

      ApplicationRecord.establish_connection(tenant_shard.to_sym)
      Mongoid.override_client(tenant_mongo_db.to_s)

      print_success("Tenant set to: #{key}")
    rescue StandardError => e
      print_error("Failed to configure tenant '#{key}': #{e.message}")
      print_backtrace(e)
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
