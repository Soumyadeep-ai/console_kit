# frozen_string_literal: true

require_relative 'console_kit/version'
require_relative 'console_kit/setup'
require_relative 'console_kit/railtie' if defined?(Rails::Railtie)

module ConsoleKit
  class Error < StandardError; end
  # Your code goes here...
end
