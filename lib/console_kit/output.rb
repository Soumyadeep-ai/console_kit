# frozen_string_literal: true

module ConsoleKit
  # Handles Console outputs
  module Output
    class << self
      def print_error(text)
        print_message("[✗] #{text}", '1;31') # Red
      end

      def print_success(text)
        print_message("[✓] #{text}", '1;32') # Green
      end

      def print_backtrace(exception)
        exception.backtrace.each { |line| print_message("    #{line}", '0;90') } # Dim gray
      end

      def print_header(text)
        print_message("\n=== #{text} ===", '1;34') # Bold Blue
      end

      def print_info(text)
        print_message(text)
      end

      def print_prompt(text)
        print_message(text, '1;36') # Cyan
      end

      def print_warning(text)
        print_message("[!] #{text}", '1;33') # Yellow
      end

      private

      def print_message(text, color = nil)
        msg = "[ConsoleKit] #{text}"
        puts color ? "\e[#{color}m#{msg}\e[0m" : msg
      end
    end
  end
end
