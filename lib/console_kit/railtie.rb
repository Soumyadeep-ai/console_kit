# frozen_string_literal: true

module ConsoleKit
  # Railtie for integrating ConsoleKit with Rails console.
  class Railtie < Rails::Railtie
    console do
      ConsoleKit::Setup.setup
      ConsoleKit::Prompt.apply
      if defined?(IRB::ExtendCommandBundle) && !defined?(Pry)
        IRB::ExtendCommandBundle.include(ConsoleKit::ConsoleHelpers)
      else
        TOPLEVEL_BINDING.receiver.extend(ConsoleKit::ConsoleHelpers)
      end
    end

    config.to_prepare { ConsoleKit::Setup.reapply if defined?(Rails::Console) }
  end
end
