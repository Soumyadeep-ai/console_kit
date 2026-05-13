# frozen_string_literal: true

module ConsoleKit
  # Helper methods available in the Rails console
  module ConsoleHelpers
    def switch_tenant
      ConsoleKit.reset_current_tenant
      self
    end

    def tenant_info
      tenant = ConsoleKit::Setup.current_tenant
      return no_tenant_warning unless tenant

      display_tenant_info(tenant)
      nil
    end

    def dashboard
      ConsoleKit::Connections::Dashboard.display
      self
    end

    def tenants
      names = ConsoleKit.configuration.tenants&.keys || []
      print_available_tenants(names)
      names
    end

    DETAIL_LABELS = {
      'Partner' => :partner_code, 'Shard' => :shard, 'Mongo DB' => :mongo_db,
      'Redis DB' => :redis_db, 'ES Prefix' => :elasticsearch_prefix, 'Environment' => :environment
    }.freeze

    private

    def no_tenant_warning
      ConsoleKit::Output.print_warning('No tenant is currently configured.')
      self
    end

    def display_tenant_info(tenant)
      constants = ConsoleKit.configuration.tenants[tenant]&.[](:constants) || {}
      ConsoleHelpers.print_tenant_details(tenant, constants)
      self
    end

    def print_available_tenants(names)
      ConsoleKit::Output.print_list(names, header: 'Available Tenants')
      self
    end

    class << self
      def print_tenant_details(tenant, constants)
        ConsoleKit::Output.print_header("Tenant: #{tenant}")
        DETAIL_LABELS.each do |label, key|
          next unless constants.key?(key)

          ConsoleKit::Output.print_info("  #{label.ljust(13)}#{constants[key]}")
        end
      end
    end
  end
end
