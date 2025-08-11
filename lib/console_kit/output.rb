# frozen_string_literal: true

module ConsoleKit
  # Handles Console outputs
  module Output
    class << self
      def print_error(text) = print_with(:error, text)
      def print_success(text) = print_with(:success, text)
      def print_warning(text) = print_with(:warning, text)
      def print_info(text) = print_with(:info, text)
      def print_prompt(text) = print_with(:prompt, text)
      def print_header(text) = print_with(:header, "\n=== #{text} ===")

      def print_backtrace(exception)
        return unless exception&.backtrace

        exception.backtrace.each { |line| print_with(:trace, "    #{line}") }
      end

      private

      PREFIX = '[ConsoleKit]'
      SYMBOLS = {
        error: '[✗]',
        success: '[✓]',
        warning: '[!]',
        info: nil,
        prompt: nil,
        header: nil,
        trace: nil
      }.freeze

      COLORS = {
        error: '1;31', # red
        success: '1;32',  # green
        warning: '1;33',  # yellow
        prompt: '1;36',  # cyan
        header: '1;34',  # bold blue
        trace: '0;90', # dim gray
        info: nil # default
      }.freeze

      def print_with(type, text, timestamp: false)
        color = COLORS[type]
        symbol = SYMBOLS[type]
        message = build_message(text, symbol, timestamp)
        output(message, color)
      end

      def build_message(text, symbol, timestamp)
        time_str = timestamp ? "[#{Time.current.strftime('%Y-%m-%d %H:%M:%S')}] " : ''
        symbol_str = symbol ? "#{symbol} " : ''
        "#{PREFIX} #{time_str}#{symbol_str}#{text}"
      end

      def output(message, color)
        if ConsoleKit.configuration.pretty_output && color
          puts "\e[#{color}m#{message}\e[0m"
        else
          puts message
        end
      end
    end
  end
end
