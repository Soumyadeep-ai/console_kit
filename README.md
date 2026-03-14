# ConsoleKit

![Gem Version](https://img.shields.io/gem/v/console_kit.svg)
![Gem Downloads](https://img.shields.io/gem/dt/console_kit.svg)
![Build Status](https://github.com/Soumyadeep-ai/console_kit/actions/workflows/release.yml/badge.svg)
![License](https://img.shields.io/github/license/Soumyadeep-ai/console_kit)
![Ruby](https://img.shields.io/badge/ruby-%3E=3.1.0-red)

A simple and flexible multi-tenant console setup toolkit for Rails applications.

ConsoleKit helps you manage tenant-specific database connections (SQL, MongoDB, Redis, Elasticsearch) and context configuration via an easy CLI interface and Rails integration.

## Installation

Install the gem and add to the application's Gemfile by executing:

```ruby
bundle add console_kit
```

Additionally you can also add this line to your application's Gemfile:

```ruby
gem 'console_kit'
```

And then execute:

```ruby
bundle install
```

If bundler is not being used to manage dependencies, install the gem by executing:

```ruby
gem install console_kit
```

## Usage

After installing, generate the initializer and configuration files by running:

```ruby
rails generate console_kit:install
```

Then, edit config/initializers/console_kit.rb to define your tenants and context class. Example format:

```ruby
ConsoleKit.configure do |config|
  config.tenants = {
    tenant_one: {
      constants: {
        shard: :tenant_one_db,
        mongo_db: :tenant_one_mongo,
        partner_code: 'partnerA',
        redis_db: 1,
        elasticsearch_prefix: 'tenant_one',
        environment: 'production'
      }
    },
    tenant_two: {
      constants: {
        shard: :tenant_two_db,
        mongo_db: :tenant_two_mongo,
        partner_code: 'partnerB',
        redis_db: 2,
        elasticsearch_prefix: 'tenant_two',
        environment: 'staging'
      }
    }
  }

  config.context_class = CurrentContext

  # Optional: Toggle pretty CLI output
  config.pretty_output = true
end
```

## Supported Connections

ConsoleKit automatically detects and manages connections for:

| Connection      | Gem Required    | Config Key               | Behavior                                        |
|-----------------|-----------------|--------------------------|------------------------------------------------|
| SQL (ActiveRecord) | `activerecord` | `shard`               | Calls `establish_connection` on your base class |
| MongoDB         | `mongoid`       | `mongo_db`              | Calls `Mongoid.override_database`              |
| Redis           | `redis`         | `redis_db`              | Calls `Redis.current.select(db)`               |
| Elasticsearch   | `elasticsearch` | `elasticsearch_prefix`  | Sets `Elasticsearch::Model.index_name_prefix=` |

Handlers are only activated when their corresponding gem is loaded.

## Console Usage

When launching the Rails console, ConsoleKit will prompt you to select a tenant (if multiple tenants are configured). On selection, a tenant banner is displayed showing the tenant name, environment safety warnings, and active connections.

### Selection Options:
- **Number or Name:** Select a tenant by its index or name (case-insensitive).
- **0 (Skip):** Load the console without any tenant configuration.
- **exit / quit:** Immediately terminate the console session.

### Console Helpers

The following helper methods are available in your Rails console:

```ruby
# Switch to a different tenant
switch_tenant

# Print details about the current tenant
tenant_info

# List all available tenants
tenants
```

### Custom Prompt

ConsoleKit automatically sets your IRB/Pry prompt to show the active tenant:

```
[tenant_one] main:001>
```

### Other Methods

```ruby
# Get current tenant
ConsoleKit.current_tenant
# => :tenant_one

# Reset and re-select tenant
ConsoleKit.reset_current_tenant

# Toggle pretty output
ConsoleKit.enable_pretty_output
ConsoleKit.disable_pretty_output
```

### Environment Warnings

When a tenant has an `environment` key in its constants:
- **production**: A red warning is displayed at setup time.
- **staging**: A yellow warning is displayed at setup time.

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at [Console Kit](https://github.com/Soumyadeep-ai/console_kit). This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [code of conduct](https://github.com/Soumyadeep-ai/console_kit/blob/main/CODE_OF_CONDUCT.md).

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting in the ConsoleKit project's codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/Soumyadeep-ai/console_kit/blob/main/CODE_OF_CONDUCT.md).
