# frozen_string_literal: true

require_relative '../output'
require_relative 'user_store'
require_relative 'user'
require_relative 'prompts'
require_relative 'initial_user_setup'

module ConsoleKit
  module Authentication
    class ConsoleAuthenticator
      def authenticate!
        return bypass_authentication unless ConsoleKit.configuration.secure_login

        store = UserStore.new
        return credentials_missing unless store.credentials_exist?

        Output.print_warning('Console access requires authentication.')

        login    = Prompts.prompt('Username or Email')
        password = Prompts.prompt_password

        user_data = store.find_by_login(login)
        user = User.new(user_data) if user_data

        unless user&.authenticated?(password)
          Output.print_error('Authentication failed. Exiting...')
          exit(1)
        end

        if user.initial_user?
          InitialUserSetup.new(store).run
        else
          Output.print_success("Authentication successful. Welcome #{user.username} (#{user.role})")
          ConsoleKit::Setup.setup
        end
      end

      private

      def bypass_authentication
        ConsoleKit::Setup.setup
      end

      def credentials_missing
        Output.print_error('Credentials file not found.')
        exit(1)
      end
    end
  end
end
