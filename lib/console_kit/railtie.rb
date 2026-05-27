# frozen_string_literal: true

# :nocov:
module ConsoleKit
  # Railtie wires ConsoleKit into the Rails console lifecycle.
  # This file is loaded only when Rails::Railtie is defined (Rails apps).
  # Unit tests run outside a Rails app, so this file is never required —
  # all lines are unreachable in test environments.
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
# :nocov:
