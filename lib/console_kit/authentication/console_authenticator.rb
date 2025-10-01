# frozen_string_literal: true

require 'io/console'
require 'bcrypt'
require 'json'
require_relative '../output'

module ConsoleKit
  module Authentication
    class ConsoleAuthenticator
      CREDENTIALS_FILE = File.expand_path('.console_credentials.json', Dir.pwd)

      def authenticate!
        return bypass_authentication unless ConsoleKit.configuration.secure_login
        return credentials_missing unless credentials_exist?

        Output.print_warning('Console access requires authentication.')
        login = prompt_for('Username or Email')
        password = prompt_for_password
        user = user_lookup[login]
        unless authenticated?(user, password)
          Output.print_error('Authentication failed. Exiting...')
          exit(1)
        end

        return handle_initial_user_setup if user['role'] == 'initial_user'

        Output.print_success("Authentication successful. Welcome #{user['username']} (#{user['role']})")
        start_console_setup
      end

      private

      def bypass_authentication
        start_console_setup
      end

      def start_console_setup
        ConsoleKit::Setup.setup
      end

      def credentials_missing
        Output.print_error("Credentials file not found at #{CREDENTIALS_FILE}")
        exit(1)
      end

      def credentials_exist?
        File.exist?(CREDENTIALS_FILE)
      end

      def prompt_for(label)
        Output.print_prompt("#{label}: ")
        $stdin.gets&.chomp
      end

      def prompt_for_password
        Output.print_prompt('Password: ')
        $stdin.noecho(&:gets)&.chomp.tap { puts }
      end

      def authenticated?(user, password)
        return false unless user && user['password']

        begin
          bcrypt_password = BCrypt::Password.new(user['password'])
          bcrypt_password == password
        rescue BCrypt::Errors::InvalidHash
          false
        end
      end

      def user_lookup
        @user_lookup ||= load_users
      end

      def load_users
        users = JSON.parse(File.read(CREDENTIALS_FILE))
        users.each_with_object({}) do |(_key, user), lookup|
          lookup[user['username']] = user
          lookup[user['email']] = user
        end
      end

      def handle_initial_user_setup
        Output.print_info('First-time setup: Create your permanent admin account')

        username = prompt_for('New Admin Username')
        email    = prompt_for('New Admin Email')
        password = prompt_for_password_with_confirmation

        new_admin = {
          username: username,
          email: email,
          password: BCrypt::Password.create(password),
          role: 'admin',
          permissions: {}
        }

        users = JSON.parse(File.read(CREDENTIALS_FILE))
        users.delete_if { |_key, user| user['role'] == 'initial_user' }
        users[username] = new_admin

        File.write(CREDENTIALS_FILE, JSON.pretty_generate(users))

        Output.print_success("Admin user #{username} created. Initial user removed.")
        exit(1)
      end

      def prompt_for_password_with_confirmation
        loop do
          pass1 = prompt_for_password_with_label('New Password')
          pass2 = prompt_for_password_with_label('Confirm Password')
          return pass1 if pass1 == pass2

          Output.print_error('Passwords do not match. Please try again.')
        end
      end

      def prompt_for_password_with_label(label)
        Output.print_prompt("#{label}: ")
        $stdin.noecho(&:gets)&.chomp.tap { puts }
      end
    end
  end
end
