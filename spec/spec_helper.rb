# frozen_string_literal: true

require 'simplecov'
SimpleCov.start do
  enable_coverage :branch
  add_filter '/spec/'
  track_files 'lib/**/*.rb'

  add_group 'Core', 'lib/console_kit/'
  add_group 'Connections', 'lib/console_kit/connections/'
  add_group 'Generators', 'lib/generators/'
end

require 'logger'
require 'console_kit'
require 'generator_spec'

# Load mocks
Dir[File.expand_path('support/mocks/**/*.rb', __dir__)].each { |f| require f }

# Load all support files
Dir[File.expand_path('support/**/*.rb', __dir__)].each { |f| require f }

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

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.after do
    ConsoleKit.reset_configuration!
    Thread.current[:console_kit_silent] = nil
    Thread.current[:console_kit_configuration_success] = nil
    Thread.current[:console_kit_current_tenant_key] = nil
    Thread.current[:console_kit_current_tenant] = nil
    Thread.current[:console_kit_elasticsearch_prefix] = nil
  end
end
