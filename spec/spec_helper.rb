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

  # The connection handler registry is `BaseConnectionHandler.descendants`, so a
  # handler class an example builds stays discoverable by every later example
  # until it is collected. Dropping the reference is not enough, and an `after`
  # hook is too early: constant stubs and `let` memos still hold the class while
  # those run. Collecting once per group keeps the registry honest without
  # paying for a full GC on every example.
  config.after(:context) do
    GC.start
  end

  # Every piece of state ConsoleKit keeps outside a single example. Leaking any
  # of it makes examples order-dependent, which is exactly how the anonymous
  # connection handlers used to poison later examples.
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
  end
end
