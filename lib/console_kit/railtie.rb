# frozen_string_literal: true

module ConsoleKit
  # Railtie for integrating ConsoleKit with Rails console.
  class Railtie < Rails::Railtie
    console do
      ConsoleKit::Setup.setup
      ConsoleKit::Prompt.apply
      Rails::ConsoleMethods.include(ConsoleKit::ConsoleHelpers) if defined?(Rails::ConsoleMethods)
    end

    config.to_prepare { ConsoleKit::Setup.reapply if defined?(Rails::Console) }
  end
end
