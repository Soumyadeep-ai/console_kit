# frozen_string_literal: true

module ConsoleKit
  # Handles Console outputs
  module Output
    class << self
      def print_error(text)
        print_message("[✗] #{text}", COLORS[:error])
      end

      def print_success(text)
        print_message("[✓] #{text}", COLORS[:success])
      end

      def print_backtrace(exception)
        return unless exception&.backtrace

        exception.backtrace.each { |line| print_message("    #{line}", COLORS[:trace]) }
      end

      def print_header(text)
        print_message("\n=== #{text} ===", COLORS[:header])
      end

      def print_info(text)
        print_message(text, COLORS[:default])
      end

      def print_prompt(text)
        print_message(text, COLORS[:prompt])
      end

      def print_warning(text)
        print_message("[!] #{text}", COLORS[:warning])
      end

      private

      COLORS = {
        error: '1;31', # red
        success: '1;32', # green
        warning: '1;33', # yellow
        prompt: '1;36', # cyan
        header: '1;34', # bold blue
        trace: '0;90', # dim gray
        default: nil # no color
      }.freeze

      def print_message(text, color = nil, timestamp: false)
        msg = '[ConsoleKit] '
        msg += "[#{Time.current.strftime('%Y-%m-%d %H:%M:%S')}] " if timestamp
        msg += text
        if ConsoleKit.configuration.pretty_output && color
          puts "\e[#{color}m#{msg}\e[0m"
        else
          puts msg
        end
      end
    end
  end
end
