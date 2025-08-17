# frozen_string_literal: true

# Helper module to capture standard output for tests
module OutputSpecHelper
  module_function

  # Captures and returns the output sent to stdout during the block execution
  def capture_stdout
    original_stdout = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = original_stdout
  end

  def format_header_line(message)
    "[ConsoleKit] \n=== #{message} ==="
  end

  def format_standard_line(symbol, message)
    line = '[ConsoleKit] '
    line += "#{symbol} " if symbol
    line + message
  end

  def format_expected_line(method, message, symbol)
    {
      print_header: -> { format_header_line(message) }
    }.fetch(method, -> { format_standard_line(symbol, message) }).call
  end
end
