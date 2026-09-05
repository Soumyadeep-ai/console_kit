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

    # `dashboard` is cheap by default: :basic asks no backend anything.
    # `dashboard(level: :full)` pings, and is bounded per backend.
    def dashboard(level: :basic)
      ConsoleKit::Connections::Dashboard.display(level: level)
      self
    end

    def tenants
      names = ConsoleKit.configuration.tenants&.keys || []
      print_available_tenants(names)
      names
    end

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
        detail_labels.each do |label, key|
          next unless constants.key?(key)

          ConsoleKit::Output.print_info("  #{label.ljust(13)}#{constants[key]}")
        end
      end

      private

      # 'Partner' and 'Environment' are not backends; every entry in between
      # comes straight off the registered handlers, so a new backend needs no
      # update here.
      def detail_labels
        backend_labels = ConsoleKit::Connections::BaseConnectionHandler.registry.to_h do |handler|
          [handler.detail_label, handler.constants_key]
        end
        { 'Partner' => :partner_code }.merge(backend_labels).merge('Environment' => :environment)
      end
    end
  end
end
