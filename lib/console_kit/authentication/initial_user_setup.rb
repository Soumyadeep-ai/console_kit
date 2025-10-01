# frozen_string_literal: true

require_relative 'prompts'
require_relative 'user'

module ConsoleKit
  module Authentication
    class InitialUserSetup
      def initialize(store)
        @store = store
      end

      def run
        Output.print_info('First-time setup: Create your permanent admin account')

        username = Prompts.prompt('New Admin Username')
        email    = Prompts.prompt('New Admin Email')
        password = Prompts.prompt_password_with_confirmation

        new_admin = User.create(
          username: username,
          email: email,
          password: password,
          role: 'admin'
        )

        @store.remove_initial_user
        @store.add_user(new_admin)
        @store.save!

        Output.print_success("Admin user #{username} created. Initial user removed.")
        exit(1)
      end
    end
  end
end
