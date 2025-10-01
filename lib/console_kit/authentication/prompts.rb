# frozen_string_literal: true

module ConsoleKit
  module Authentication
    class Prompts
      def self.prompt(label)
        Output.print_prompt("#{label}: ")
        $stdin.gets&.chomp
      end

      def self.prompt_password(label = 'Password')
        Output.print_prompt("#{label}: ")
        $stdin.noecho(&:gets)&.chomp.tap { puts }
      end

      def self.prompt_password_with_confirmation
        loop do
          pass1 = prompt_password('New Password')
          pass2 = prompt_password('Confirm Password')
          return pass1 if pass1 == pass2

          Output.print_error('Passwords do not match. Please try again.')
        end
      end
    end
  end
end
