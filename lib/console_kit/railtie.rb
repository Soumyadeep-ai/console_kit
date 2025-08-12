# frozen_string_literal: true

module ConsoleKit
  # Railtie
  class Railtie < Rails::Railtie
    console { ConsoleKit::Setup.setup }
  end
end
