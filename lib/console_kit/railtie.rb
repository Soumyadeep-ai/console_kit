# frozen_string_literal: true

module ConsoleKit
  # Railtie for integrating ConsoleKit with Rails console.
  class Railtie < Rails::Railtie
    console { ConsoleKit::Setup.setup }
  end
end
