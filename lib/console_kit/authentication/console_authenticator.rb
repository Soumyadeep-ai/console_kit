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
        login = prompt_for_username
        password = prompt_for_password
        user = user_lookup[login]
        unless authenticated?(user, password)
          Output.print_error('Authentication failed. Exiting...')
          exit(1)
        end

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

      def prompt_for_username
        Output.print_prompt('Username or Email')
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
    end
  end
end
