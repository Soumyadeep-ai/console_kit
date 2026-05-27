# ConsoleKit

![Gem Version](https://img.shields.io/gem/v/console_kit.svg)
![Gem Downloads](https://img.shields.io/gem/dt/console_kit.svg)
![Build Status](https://github.com/Soumyadeep-ai/console_kit/actions/workflows/test_suite.yml/badge.svg)
![License](https://img.shields.io/github/license/Soumyadeep-ai/console_kit)
![Ruby](https://img.shields.io/badge/ruby-%3E=3.1-red)
![Rails](https://img.shields.io/badge/rails-6.1%20%7C%207.0%20%7C%207.1%20%7C%207.2%20%7C%208.0-blue)
![Coverage](https://img.shields.io/badge/coverage-100%25-brightgreen)

**Interactive multi-tenant Rails console framework.**

ConsoleKit gives your Rails console first-class multi-tenancy: fuzzy tenant selection, scoped tenant switching, fiber-local context isolation, production safeguards, lifecycle hooks, Rails-native sharding, and a health-check generator — all with a backward-compatible API.

## Compatibility

| Ruby  | Rails 6.1 | Rails 7.0 | Rails 7.1 | Rails 7.2 | Rails 8.0 |
|-------|-----------|-----------|-----------|-----------|-----------|
| 3.1   | ✓         | ✓         | ✓         | ✓         | ✓         |
| 3.2   | ✓         | ✓         | ✓         | ✓         | ✓         |
| 3.3   | ✓         | ✓         | ✓         | ✓         | ✓         |
| 3.4   | ✓         | ✓         | ✓         | ✓         | ✓         |

## Installation

Install the gem and add to the application's Gemfile by executing:

```bash
bundle add console_kit
```

Or add to your Gemfile:

```ruby
gem 'console_kit'
```

## Configuration

```ruby
# config/initializers/console_kit.rb
ConsoleKit.configure do |config|
  config.tenants = {
    tenant_one: {
      constants: {
        shard:                 :tenant_one_db,
        mongo_db:              :tenant_one_mongo,
        partner_code:          'partnerA',
        redis_db:              1,
        elasticsearch_prefix:  'tenant_one'
      }
    },
    tenant_two: {
      constants: {
        shard:                 :tenant_two_db,
        mongo_db:              :tenant_two_mongo,
        partner_code:          'partnerB',
        redis_db:              2,
        elasticsearch_prefix:  'tenant_two'
      }
    }
  }

  config.context_class = CurrentContext

  # --- v2.0 options ---

  # ENV override: CONSOLE_KIT_TENANT=tenant_one rails c
  config.env_tenant_key = 'CONSOLE_KIT_TENANT'

  # Production safeguards
  config.production_environments   = %w[production]
  config.protected_tenants         = %i[tenant_one]
  config.confirm_dangerous_context = true

  # Rails-native sharding (Rails 6.1+)
  config.use_rails_sharding = true
  config.shard_role         = :writing

  # Recent tenant memory
  config.recent_tenant_history_path = '~/.console_kit_history'
  config.recent_tenant_limit        = 5

  # Lifecycle hooks
  config.before_switch { |tenant| Datadog::Tracing.set_tag('tenant', tenant) }
  config.after_switch(on_error: :warn) { |tenant| Sentry.set_tag('tenant', tenant) }
end
```

## Console Usage

### Tenant Selection

On `rails c`, ConsoleKit prompts for a tenant. With `tty-prompt` installed, selection is interactive with fuzzy filtering and recent tenant memory.

Skip the prompt with an ENV override:

```bash
CONSOLE_KIT_TENANT=tenant_one rails c
```

### Scoped Tenant Switching

Switch tenant for a block — previous tenant restored automatically, even on exception:

```ruby
ConsoleKit.with(:tenant_two) do
  User.count   # runs against tenant_two
end
# back to original tenant

# Nestable
ConsoleKit.with(:tenant_one) do
  ConsoleKit.with(:tenant_two) do
    # tenant_two here
  end
  # tenant_one restored
end
```

### Runtime Introspection

```ruby
ConsoleKit.status
# ConsoleKit Status
#   Tenant     : tenant_one
#   Configured : true
#   Environment: production
#   Shard      : tenant_one_db

ConsoleKit.current_tenant   # => :tenant_one
```

### Interactive Tenant Switch

```ruby
switch_tenant          # re-prompts for tenant selection
ConsoleKit.switch_tenant!   # same
```

### Console Prompt

IRB/Pry prompt shows active tenant and environment:

```
[tenant_one][production] main:001>
```

### Console Helpers

```ruby
switch_tenant   # re-select tenant interactively
tenant_info     # print current tenant details
tenants         # list all configured tenants
dashboard       # connection diagnostics table
```

### Production Safeguards

When `confirm_dangerous_context: true` and Rails env is production (or tenant is protected):

```
╔══════════════════════════════════════╗
║  ⚠  ENVIRONMENT : PRODUCTION         ║
║  ⚠  TENANT      : tenant_one         ║
║  ⚠  Proceed with caution.            ║
╚══════════════════════════════════════╝
Type CONFIRM to continue:
```

### Lifecycle Hooks

```ruby
ConsoleKit.configure do |c|
  c.before_switch(on_error: :abort) { |tenant| AuditLog.record(tenant) }
  c.after_switch(on_error: :warn)   { |tenant| Sentry.set_tag('tenant', tenant) }
end
```

`on_error: :abort` — hook exception vetoes the switch. `on_error: :warn` — logs warning, continues.

### Rails Sharding

When `use_rails_sharding: true`, `ConsoleKit.with` wraps `ActiveRecord::Base.connected_to`:

```ruby
ConsoleKit.with(:tenant_two) do
  # ActiveRecord::Base.connected_to(shard: :tenant_two_db, role: :writing) is active
  Order.count
end
```

### Configuration Validation

```bash
rails console_kit:doctor
rails console_kit:doctor --verbose
```

Output:

```
  ✓  tenants configured
  ✓  tenant keys unique
  ✓  context_class resolves
  ⚠  tenant :tenant_two missing key :shard
  ✓  sharding compatible

5 checks (1 warning)
```

## Supported Connections

ConsoleKit automatically detects and manages connections for:

| Connection         | Gem Required    | Config Key              | Behavior                                        |
|--------------------|-----------------|-------------------------|-------------------------------------------------|
| SQL (ActiveRecord) | `activerecord`  | `shard`                 | Calls `establish_connection` on your base class |
| MongoDB            | `mongoid`       | `mongo_db`              | Calls `Mongoid.override_database`               |
| Redis              | `redis`         | `redis_db`              | Calls `Redis.current.select(db)`                |
| Elasticsearch      | `elasticsearch` | `elasticsearch_prefix`  | Sets `Elasticsearch::Model.index_name_prefix=`  |

Handlers are only activated when their corresponding gem is loaded.

## Integration Examples

### Standard multi-db Rails (Rails 6.1+)

```ruby
# database.yml
production:
  primary:
    ...
  tenant_one_db:
    ...
  tenant_two_db:
    ...

# initializer
ConsoleKit.configure do |c|
  c.use_rails_sharding = true
  c.tenants = {
    tenant_one: { constants: { shard: :tenant_one_db, partner_code: 'p1' } },
    tenant_two: { constants: { shard: :tenant_two_db, partner_code: 'p2' } }
  }
  c.context_class = CurrentContext
end
```

### Mongoid

```ruby
ConsoleKit.configure do |c|
  c.tenants = {
    tenant_one: { constants: { shard: :default, mongo_db: :tenant_one_mongo, partner_code: 'p1' } }
  }
  c.context_class = CurrentContext
end
# ConsoleKit calls Mongoid.override_database(:tenant_one_mongo) on switch
```

### Sidekiq context propagation

```ruby
ConsoleKit.configure do |c|
  c.after_switch { |tenant| Sidekiq::Client.default_context[:tenant] = tenant }
end
```

### Datadog + Sentry

```ruby
ConsoleKit.configure do |c|
  c.before_switch { |t| Datadog::Tracing.set_tag('tenant', t) }
  c.after_switch(on_error: :warn) { |t| Sentry.set_tag('tenant', t) }
end
```

## Connection Dashboard

Run `dashboard` in the console to see a diagnostics table for all active connections:

```
--- Connection Dashboard ---
┌───────────────┬─────────────┬─────────┬──────────────────────────────────────────┐
│ Service       │ Status      │ Latency │ Details                                  │
├───────────────┼─────────────┼─────────┼──────────────────────────────────────────┤
│ SQL           │ ✓ Connected │ 1.1ms   │ adapter: PostgreSQL, pool_size: 5, ...   │
│ MongoDB       │ ✓ Connected │ 2.3ms   │ database: my_tenant_db, version: 8.0.20  │
│ Redis         │ — N/A       │ —       │                                          │
│ Elasticsearch │ ✗ Error     │ —       │ error: connection refused                │
└───────────────┴─────────────┴─────────┴──────────────────────────────────────────┘
```

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`.

## Contributing

Bug reports and pull requests are welcome on GitHub at [Console Kit](https://github.com/Soumyadeep-ai/console_kit). This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [code of conduct](https://github.com/Soumyadeep-ai/console_kit/blob/main/CODE_OF_CONDUCT.md).

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting in the ConsoleKit project's codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/Soumyadeep-ai/console_kit/blob/main/CODE_OF_CONDUCT.md).
