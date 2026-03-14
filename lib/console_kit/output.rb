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
      def silent = Thread.current[:console_kit_silent]

      def silent=(val)
        Thread.current[:console_kit_silent] = val
      end

      def silence
        old_silent = silent
        self.silent = true
        yield
      ensure
        self.silent = old_silent
      end

      TYPES.each_key do |type|
        define_method("print_#{type}") do |text, timestamp: false, newline: (type != :prompt)|
          return if silent

          formatted = (type == :header ? "\n--- #{text} ---" : text)
          print_with(type, formatted, timestamp, { newline: newline })
        end
      end

      def print_list(items, header: nil)
        return if silent

        print_header(header) if header
        items.each { |item| puts "  #{item}" }
      end

      def print_raw(text)
        return if silent

        puts text
      end

      # Backtrace prints always with timestamp, no param
      def print_backtrace(exception)
        return if silent

        exception&.backtrace&.each { |line| print_with(:trace, "    #{line}", true, { newline: true }) }
      end

      private

      def print_with(type, text, timestamp, opts = {})
        meta = TYPES.fetch(type)
        message = build_message(text, meta[:symbol], timestamp)
        emit(message, meta[:color], opts.fetch(:newline, true))
      end

      def build_message(text, symbol, timestamp)
        "#{PREFIX} #{timestamp_prefix(timestamp)}#{symbol_prefix(symbol)}#{text}"
      end

      def prefix_for(value) = value ? yield(value) : ''
      def timestamp_prefix(timestamp) = prefix_for(timestamp) { Time.current.strftime('[%Y-%m-%d %H:%M:%S] ') }
      def symbol_prefix(symbol) = prefix_for(symbol) { |sym| "#{sym} " }

      def emit(message, color, newline)
        writer = newline ? :puts : :print
        formatted = ConsoleKit.configuration.pretty_output && color ? "\e[#{color}m#{message}\e[0m" : message
        send(writer, formatted)
      end
    end
  end
end
