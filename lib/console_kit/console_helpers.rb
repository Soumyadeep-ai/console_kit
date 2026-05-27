# frozen_string_literal: true

module ConsoleKit
  # Helpers mixed into the Rails console session.
  module ConsoleHelpers
    def switch_tenant
      ConsoleKit::SwitchPipeline.run(config: ConsoleKit.configuration)
    end

    def tenant_info
      ConsoleKit.status.display
    end

    def tenants
      ConsoleKit.configuration.tenants&.keys || []
    end
  end
end
