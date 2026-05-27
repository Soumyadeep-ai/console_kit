# frozen_string_literal: true

begin
  require 'simplecov'
  SimpleCov.start do
    enable_coverage :branch
    add_filter '/spec/'
    add_filter 'lib/generators/console_kit/templates/'
    track_files 'lib/**/*.rb'

    add_group 'Core',        'lib/console_kit/'
    add_group 'Connections', 'lib/console_kit/connections/'
    add_group 'Steps',       'lib/console_kit/steps/'
    add_group 'Doctor',      'lib/console_kit/doctor/'
    add_group 'Generators',  'lib/generators/'

    minimum_coverage line: 100, branch: 100
  end
rescue LoadError
  nil
end

require 'console_kit'
require 'generator_spec'

Dir[File.join(__dir__, 'support/**/*.rb')].each { |f| require f }

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

  config.after do
    ConsoleKit.reset_configuration!
    ConsoleKit::Context.reset! if defined?(ConsoleKit::Context)
    Thread.current[:console_kit_silent] = nil
  end
end
