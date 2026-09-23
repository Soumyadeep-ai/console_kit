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

Dir[File.expand_path('support/**/*.rb', __dir__)].each { |f| require f }

RSpec.configure do |config|
  config.example_status_persistence_file_path = '.rspec_status'

  config.order = :random
  Kernel.srand config.seed

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
    ConsoleKit::StateStore.clear!
    ConsoleKit::Instrumentation.clear!
    ConsoleKit::Connections::RedisConnectionHandler.isolation_warned = nil
    ConsoleKit::Connections::ElasticsearchPrefixRegistry.record(nil)
    ElasticsearchMocks.reset!
    ActiveRecordMock.reset_default_base!
    Thread.current[:console_kit_silent] = nil
    Thread.current[:console_kit_elasticsearch_prefix] = nil
    Thread.current[:console_kit_elasticsearch_prefix_conflict] = nil
    Thread.current[:console_kit_dropped_reported] = nil
  end
end
