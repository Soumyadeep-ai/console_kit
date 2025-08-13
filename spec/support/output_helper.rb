# frozen_string_literal: true

# Helper module to capture standard output for tests
module OutputHelper
  private

  # Captures and returns the output sent to stdout during the block execution
  def capture_stdout
    original_stdout = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = original_stdout
  end
end
