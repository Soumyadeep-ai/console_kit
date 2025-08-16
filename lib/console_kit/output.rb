# frozen_string_literal: true

module ConsoleKit
  # Handles Console outputs
  module Output
    PREFIX = '[ConsoleKit]'
    TYPES = {
      error: { symbol: '[✗]', color: '1;31' },
      success: { symbol: '[✓]', color: '1;32' },
      warning: { symbol: '[!]', color: '1;33' },
      prompt: { symbol: nil,   color: '1;36' },
      header: { symbol: nil,   color: '1;34' },
      trace: { symbol: nil, color: '0;90' },
      info: { symbol: nil, color: nil }
    }.freeze

    class << self
      TYPES.each_key do |type|
        define_method("print_#{type}") do |text, timestamp: false|
          formatted = (type == :header ? "\n=== #{text} ===" : text)
          print_with(type, formatted, timestamp)
        end
      end

      def print_backtrace(exception, timestamp: false)
        exception&.backtrace&.each { |line| print_with(:trace, "    #{line}", timestamp) }
      end

      private

      def print_with(type, text, timestamp)
        meta = TYPES.fetch(type)
        message = build_message(text, meta[:symbol], timestamp)
        output(message, meta[:color])
      end

      def build_message(text, symbol, timestamp)
        "#{PREFIX} #{timestamp_prefix(timestamp)}#{symbol_prefix(symbol)}#{text}"
      end

      def timestamp_prefix(timestamp)
        timestamp ? "[#{Time.current.strftime('%Y-%m-%d %H:%M:%S')}] " : ''
      end

      def symbol_prefix(symbol)
        symbol ? "#{symbol} " : ''
      end

      def output(message, color)
        return puts message unless ConsoleKit.configuration.pretty_output && color

        puts "\e[#{color}m#{message}\e[0m"
      end
    end
  end
end
