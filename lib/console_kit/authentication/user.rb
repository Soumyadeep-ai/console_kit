# frozen_string_literal: true

require 'bcrypt'

module ConsoleKit
  module Authentication
    class User
      attr_reader :username, :email, :role, :permissions

      def initialize(data)
        @username = data['username']
        @email = data['email']
        @role = data['role']
        @password_digest = data['password']
        @permissions = data['permissions'] || {}
      end

      def self.create(username:, email:, password:, role:)
        {
          'username' => username,
          'email' => email,
          'password' => BCrypt::Password.create(password),
          'role' => role,
          'permissions' => {}
        }
      end

      def authenticated?(password)
        BCrypt::Password.new(@password_digest) == password
      rescue BCrypt::Errors::InvalidHash
        false
      end

      def initial_user?
        role == 'initial_user'
      end
    end
  end
end
