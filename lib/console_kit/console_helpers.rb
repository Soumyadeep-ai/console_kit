# frozen_string_literal: true

module ConsoleKit
  # Helpers mixed into the Rails console session.
  module ConsoleHelpers
    def switch_tenant
      ConsoleKit.switch_tenant!
    end

    def tenant_info
      ConsoleKit.status.print
    end

    def tenants
      ConsoleKit.configuration.tenants&.keys || []
    end
  end
end
