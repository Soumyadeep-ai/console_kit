# frozen_string_literal: true

module ConsoleKit
  # Railtie
  class Railtie < Rails::Railtie
    console do
      ConsoleKit::Setup.setup
    end
  end
end
