# frozen_string_literal: true

module ConsoleKit
  module ConsoleHelpers
    def switch_tenant
      ConsoleKit.reset_current_tenant
      self
    end

    def tenant_info
      tenant = ConsoleKit::StateStore.tenant_key
      return ConsoleKit::Output.print_warning('No tenant is currently configured.') unless tenant

      constants = ConsoleKit.configuration.tenants[tenant]&.[](:constants) || {}
      ConsoleHelpers.print_tenant_details(tenant, constants)
      nil
    end

    def dashboard(level: :basic)
      ConsoleKit::Connections::Dashboard.display(level: level)
      self
    end

    def tenants
      names = ConsoleKit.configuration.tenants&.keys || []
      ConsoleKit::Output.print_list(names, header: 'Available Tenants')
      names
    end

    class << self
      def print_tenant_details(tenant, constants)
        ConsoleKit::Output.print_header("Tenant: #{tenant}")
        detail_labels.each do |label, key|
          next unless constants.key?(key)

          ConsoleKit::Output.print_info("  #{label.ljust(13)}#{constants[key]}")
        end
      end

      private

      def detail_labels
        backend_labels = ConsoleKit::Connections::BaseConnectionHandler.registry.to_h do |handler|
          [handler.detail_label, handler.constants_key]
        end
        { 'Partner' => :partner_code }.merge(backend_labels).merge('Environment' => :environment)
      end
    end
  end
end
