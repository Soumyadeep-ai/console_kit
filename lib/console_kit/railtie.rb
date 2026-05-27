# frozen_string_literal: true

module ConsoleKit
  # Railtie wires ConsoleKit into the Rails console lifecycle.
  class Railtie < Rails::Railtie
    console do
      SwitchPipeline.run(config: ConsoleKit.configuration)
      if defined?(IRB::ExtendCommandBundle) && !defined?(Pry)
        IRB::ExtendCommandBundle.include(ConsoleKit::ConsoleHelpers)
      else
        TOPLEVEL_BINDING.receiver.extend(ConsoleKit::ConsoleHelpers)
      end
    end

    config.to_prepare do
      SwitchPipeline.run(config: ConsoleKit.configuration) if defined?(Rails::Console)
    end
  end
end
