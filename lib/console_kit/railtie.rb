# frozen_string_literal: true

module ConsoleKit
  class Railtie < Rails::Railtie
    console do
      ConsoleKit::TenantOrchestrator.run
      ConsoleKit::Prompt.apply
      if defined?(IRB::ExtendCommandBundle) && !defined?(Pry)
        IRB::ExtendCommandBundle.include(ConsoleKit::ConsoleHelpers)
      else
        TOPLEVEL_BINDING.receiver.extend(ConsoleKit::ConsoleHelpers)
      end
    end

    config.to_prepare { ConsoleKit::TenantOrchestrator.reapply if defined?(Rails::Console) }
  end
end
