# frozen_string_literal: true

module ConsoleKit
  # Helper methods available in the Rails console
  module ConsoleHelpers
    def switch_tenant = ConsoleKit.reset_current_tenant

    def tenant_info
      tenant = ConsoleKit::Setup.current_tenant
      unless tenant
        ConsoleKit::Output.print_warning('No tenant is currently configured.')
        return
      end

      constants = ConsoleKit.configuration.tenants[tenant]&.[](:constants) || {}
      print_tenant_details(tenant, constants)
    end

    def dashboard = ConsoleKit::Connections::Dashboard.display

    def tenants
      names = ConsoleKit.configuration.tenants&.keys || []
      ConsoleKit::Output.print_list(names, header: 'Available Tenants')
      names
    end

    DETAIL_LABELS = {
      'Partner' => :partner_code, 'Shard' => :shard, 'Mongo DB' => :mongo_db,
      'Redis DB' => :redis_db, 'ES Prefix' => :elasticsearch_prefix, 'Environment' => :environment
    }.freeze

    private

    def print_tenant_details(tenant, constants)
      ConsoleKit::Output.print_header("Tenant: #{tenant}")
      DETAIL_LABELS.each do |label, key|
        constants.fetch(key, :missing).then do |val|
          case val
          when :missing then next
          else ConsoleKit::Output.print_info("  #{label.ljust(13)}#{val}")
          end
        end
      end
      nil
    end
  end
end
