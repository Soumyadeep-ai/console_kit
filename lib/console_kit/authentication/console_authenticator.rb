# frozen_string_literal: true

require 'io/console'
require 'digest'
require 'json'
require_relative '../output'

module ConsoleKit
  module Authentication
    class ConsoleAuthenticator
      CREDENTIALS_FILE = File.expand_path('.console_credentials.json', Dir.pwd)

      def authenticate!
        unless credentials_exist?
          Output.print_error("Credentials file not found at #{CREDENTIALS_FILE}")
          exit(1)
        end

        Output.print_warning('Console access requires authentication.')
        login = prompt_for('Username or Email')
        password = prompt_for_password

        user = user_lookup[login]
        unless user && valid_password?(user, password)
          Output.print_error('Authentication failed. Exiting...')
          exit(1)
        end

        Output.print_success("Authentication successful. Welcome #{user['username']} (#{user['role']})")
        ConsoleKit::Setup.setup
      end

      private

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

      def valid_password?(user, password)
        hashed_input = Digest::SHA256.hexdigest(password)
        hashed_input == user['password']
      end

      def user_lookup
        @user_lookup ||= load_users
      end

      def load_users
        raw_users = JSON.parse(File.read(CREDENTIALS_FILE))
        raw_users.each_with_object({}) do |(_key, user), lookup|
          lookup[user['username']] = user
          lookup[user['email']] = user
        end
      end
    end
  end
end
