# frozen_string_literal: true

require 'json'
require_relative 'user'

module ConsoleKit
  module Authentication
    class UserStore
      FILE_PATH = File.expand_path('.console_credentials.json', Dir.pwd)

      def initialize
        @users = load_users
      end

      def all
        @users.values
      end

      def find_by_login(login)
        user_lookup[login]
      end

      def initial_user_exists?
        @users.values.any? { |user| user['role'] == 'initial_user' }
      end

      def add_user(user_data)
        @users[user_data['username']] = user_data
      end

      def remove_initial_user
        @users.delete_if { |_k, user| user['role'] == 'initial_user' }
      end

      def save!
        File.write(FILE_PATH, JSON.pretty_generate(@users))
      end

      def credentials_exist?
        File.exist?(FILE_PATH)
      end

      private

      def load_users
        return {} unless credentials_exist?

        raw_users = JSON.parse(File.read(FILE_PATH))
        raw_users.transform_values { |u| u }
      end

      def user_lookup
        @user_lookup ||= build_lookup
      end

      def build_lookup
        lookup = {}
        @users.each_value do |user|
          lookup[user['username']] = user
          lookup[user['email']] = user
        end
        lookup
      end
    end
  end
end
