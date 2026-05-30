# frozen_string_literal: true

module ConsoleKit
  # Helpers mixed into the Rails console session.
  module ConsoleHelpers
    def switch_tenant
      ConsoleKit.switch_tenant!
    end

    alias ck_switch switch_tenant

    def tenant_info
      ConsoleKit.status.print
    end

    alias ck_status tenant_info

    def dashboard
      ConsoleKit::Connections::Dashboard.display
    end

    def tenants
      configuration = ConsoleKit.configuration
      return [:dynamic_mode] if configuration.tenants == :dynamic

      configuration.tenant_resolver_instance.all_keys
    rescue ConsoleKit::Error
      []
    end
  end
end
