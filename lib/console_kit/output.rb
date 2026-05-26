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
        define_method("print_#{type}") do |text|
          formatted = (type == :header ? "\n=== #{text} ===" : text)
          print_with(type, formatted)
        end
      end

      def print_backtrace(exception)
        exception&.backtrace&.each { |line| print_with(:trace, "    #{line}") }
      end

      def print_banner(lines:, style: :danger)
        color = style == :danger ? "\e[31m" : "\e[33m"
        width = lines.map(&:length).max + 4
        render_banner_lines({ color:, width:, padding: '═' * width, lines: })
      end

      def render_banner_lines(context)
        reset = "\e[0m"
        color = context[:color]
        width = context[:width]
        padding = context[:padding]
        $stdout.puts "#{color}╔#{padding}╗#{reset}"
        context[:lines].each do |line|
          $stdout.puts "#{color}║#{"  ⚠  #{line}".ljust(width)}║#{reset}"
        end
        $stdout.puts "#{color}╚#{padding}╝#{reset}"
      end

      private

      def print_with(type, text, timestamp: false)
        meta = TYPES[type]
        message = build_message(text, meta[:symbol], timestamp)
        output(message, meta[:color])
      end

      def build_message(text, symbol, timestamp)
        time = timestamp ? "[#{Time.current.strftime('%Y-%m-%d %H:%M:%S')}] " : ''
        sym = symbol ? "#{symbol} " : ''
        "#{PREFIX} #{time}#{sym}#{text}"
      end

      def output(message, color)
        return puts message unless ConsoleKit.configuration.pretty_output && color

        puts "\e[#{color}m#{message}\e[0m"
      end
    end
  end
end
