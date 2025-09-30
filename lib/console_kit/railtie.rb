# frozen_string_literal: true

require_relative 'authentication/console_authenticator'
module ConsoleKit
  # Railtie for integrating ConsoleKit with Rails console.
  class Railtie < Rails::Railtie
    console { ConsoleKit::Authentication::ConsoleAuthenticator.new.authenticate! }
  end
end
