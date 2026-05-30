# frozen_string_literal: true

module ConsoleKit
  # Base error class for all ConsoleKit-specific errors.
  class Error < StandardError; end

  # Raised when a write operation is attempted while readonly mode is active.
  class ReadonlyViolation < Error; end
end
