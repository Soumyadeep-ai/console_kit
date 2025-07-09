# frozen_string_literal: true

module ConsoleKit
  class Railtie < Rails::Railtie
    console do
      ConsoleKit.setup
    end
  end
end