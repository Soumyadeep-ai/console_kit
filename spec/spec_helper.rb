# frozen_string_literal: true

require 'console_kit'
require 'generator_spec'

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = '.rspec_status'

  config.order = :random
  Kernel.srand config.seed

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.include GeneratorSpec::TestCase, type: :generator

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end
end
