# frozen_string_literal: true

module ConsoleKit
  module Generators
    # Sets up console credentials if secure_login is enabled
    class CredentialsGenerator < Rails::Generators::Base
      CREDENTIALS_FILE = Rails.root.join('.console_credentials.json')

      def verify_secure_login_enabled
        return if ConsoleKit.configuration.secure_login

        say_status :skipped, 'Secure login is disabled in console_kit.rb. Enable it to use this feature.', :yellow
        exit
      end

      def create_credentials_file
        if File.exist?(CREDENTIALS_FILE)
          say_status :skipped, '.console_credentials.json already exists', :yellow
        else
          create_default_admin_user
          say_status :created, '.console_credentials.json created with default admin user', :green
        end
      end

      def add_to_gitignore
        gitignore_path = Rails.root.join('.gitignore')
        return unless File.exist?(gitignore_path)

        lines = File.read(gitignore_path).split("\n")
        if lines.include?('.console_credentials.json')
          say_status :skipped, '.console_credentials.json already in .gitignore', :yellow
        else
          File.open(gitignore_path, 'a') { |f| f.puts "\n.console_credentials.json" }
          say_status :modified, '.gitignore updated to exclude .console_credentials.json', :green
        end
      end

      private

      def create_default_admin_user
        password_digest = BCrypt::Password.create('password@1234')

        initial_user = {
          username: 'initial_user',
          email: '',
          password: password_digest,
          role: 'initial_user',
          permissions: {}
        }

        File.write(CREDENTIALS_FILE, JSON.pretty_generate({ 'initial_user' => initial_user }))
      end
    end
  end
end
