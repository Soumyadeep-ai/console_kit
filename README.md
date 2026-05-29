# ConsoleKit

![Gem Version](https://img.shields.io/gem/v/console_kit.svg)
![Gem Downloads](https://img.shields.io/gem/dt/console_kit.svg)
![Build Status](https://github.com/Soumyadeep-ai/console_kit/actions/workflows/test_suite.yml/badge.svg)
![License](https://img.shields.io/github/license/Soumyadeep-ai/console_kit)
![Ruby](https://img.shields.io/badge/ruby-%3E=3.1-red)
![Rails](https://img.shields.io/badge/rails-6.1%20%7C%207.0%20%7C%207.1%20%7C%207.2%20%7C%208.0%20%7C%208.1-blue)
![Coverage](https://img.shields.io/badge/coverage-100%25-brightgreen)

**Production-safe Rails console for multi-tenant apps.**

---

## The problem

You type `rails c` in the wrong terminal tab. You're in production. You meant staging. You run a bulk update. Two minutes later your on-call is pinging you.

Or: you're in the right environment, but you meant `tenant_b` not `tenant_a`. Two thousand records. Wrong database. The rollback takes four hours.

Or: a new engineer opens the console, doesn't realize the IRB prompt looks identical in every environment, and drops a table.

**These are not hypotheticals.** In multi-tenant Rails apps, the console is the most dangerous surface your team touches. Every post-incident review has a version of this story.

ConsoleKit makes the safe path the only path:

- Forces tenant selection before you can type a single command
- Puts the tenant name and environment in the IRB prompt — permanently visible
- Blocks all ActiveRecord writes in production with a hard error, not a warning
- Demands `CONFIRM` before you get a prompt in protected environments
- Writes an audit trail of every session
- Runs a health check so your connection stack is verified before you open the console

---

## Installation

```bash
bundle add console_kit
```

Or in your Gemfile:

```ruby
gem 'console_kit'
```

## Quick start

```ruby
# config/initializers/console_kit.rb
ConsoleKit.configure do |config|
  config.tenants = {
    acme: { constants: { shard: :acme_db, partner_code: 'acme' } },
    beta: { constants: { shard: :beta_db, partner_code: 'beta' } }
  }

  config.context_class             = CurrentContext
  config.production_environments   = %w[production]
  config.protected_tenants         = %i[acme]
  config.confirm_dangerous_context = true
  config.readonly_environments     = %w[production]
end
```

Run `rails c`. ConsoleKit intercepts startup, prompts for a tenant, wires up the connection stack, and drops you into a prompt that shows exactly where you are:

```
[acme][production] main:001>
```

---

## What happens at startup

```
rails c
  │
  ├─ 1. ENV check ────────── CONSOLE_KIT_TENANT=acme skips the prompt
  ├─ 2. Tenant selection ─── fuzzy interactive picker, recent-tenant memory
  ├─ 3. Safety gate ──────── banner + CONFIRM required if env/tenant protected
  ├─ 4. Readonly mode ─────── AR writes blocked in production (hard error)
  ├─ 5. Connection setup ──── SQL, Mongo, Redis, Elasticsearch, Apartment, ActsAsTenant
  ├─ 6. Prompt ────────────── [tenant][env] set in IRB/Pry
  └─ 7. Audit log ─────────── session entry written to disk
```

---

## Compatibility

| Ruby  | Rails 6.1 | Rails 7.0 | Rails 7.1 | Rails 7.2 | Rails 8.0 | Rails 8.1 |
|-------|:---------:|:---------:|:---------:|:---------:|:---------:|:---------:|
| 3.1   | ✓         | ✓         | ✓         | ✓         | —         | —         |
| 3.2   | ✓         | ✓         | ✓         | ✓         | ✓         | ✓         |
| 3.3   | ✓         | ✓         | ✓         | ✓         | ✓         | ✓         |
| 3.4   | ✓         | ✓         | ✓         | ✓         | ✓         | ✓         |
| 4.0   | —         | —         | —         | ✓         | ✓         | ✓         |

Rails 8.0+ requires Ruby ≥ 3.2. Ruby 4.0 tested against Rails 7.2+.

---

## Readonly mode

The most common production console incident isn't a dropped table — it's a bulk update on the wrong dataset. Readonly mode makes writes physically impossible:

```ruby
config.readonly_environments = %w[production]
```

When active, any write attempt raises `ConsoleKit::ReadonlyViolation`:

```
[acme][production] main:001> User.update_all(active: false)
ConsoleKit::ReadonlyViolation: update_all blocked: readonly mode active
```

Blocked: `save`, `save!`, `update_columns`, `update_column`, `destroy`, `destroy!`, `delete`, `create`, `create!`, `insert`, `insert!`, `insert_all`, `insert_all!`, `update_all`, `delete_all`, `destroy_all`, `upsert`, `upsert_all`.

On Rails 7.1+, ConsoleKit also sets `connection.prevent_writes = true` at the adapter level — raw SQL writes through `execute` are blocked too.

```ruby
ConsoleKit.readonly?  # => true
```

---

## Audit logging

Every session is logged:

```ruby
config.audit_log      = true
config.audit_log_path = '~/.console_kit_audit.log'
```

```
2026-01-15T14:32:01+00:00 | user=alice | env=production | tenant=acme | action=tenant_switch | status=success
```

Useful for compliance ("who opened a production console session on this date?") and post-incident reconstruction.

---

## Production safeguard

When `confirm_dangerous_context: true` and the env is production (or the tenant is protected), a banner appears and requires manual confirmation:

```
╔══════════════════════════════════════╗
║  ⚠  ENVIRONMENT : PRODUCTION         ║
║  ⚠  TENANT      : acme               ║
║  ⚠  Proceed with caution.            ║
╚══════════════════════════════════════╝
Type CONFIRM to continue:
```

---

## Configuration reference

```ruby
ConsoleKit.configure do |config|
  # ── Tenants ──────────────────────────────────────────────────────────────────
  config.tenants = {
    acme: {
      constants: {
        shard:                 :acme_db,
        mongo_db:              :acme_mongo,
        partner_code:          'acme',
        redis_db:              1,
        elasticsearch_prefix:  'acme',
        apartment_schema:      'acme',     # Apartment gem
        acts_as_tenant_id:     1           # ActsAsTenant gem
      }
    }
  }

  # Dynamic resolution (large tenant counts):
  # config.tenants         = :dynamic
  # config.tenant_resolver = ->(key) { TenantRegistry.find(key) }

  config.context_class = CurrentContext

  # ── Safety ───────────────────────────────────────────────────────────────────
  config.production_environments    = %w[production]
  config.protected_tenants          = %i[acme]
  config.confirm_dangerous_context  = true

  # ── Readonly mode ─────────────────────────────────────────────────────────────
  config.readonly_environments = %w[production]  # env-based
  # config.readonly_mode = true                  # always on

  # ── Audit logging ─────────────────────────────────────────────────────────────
  config.audit_log      = true
  config.audit_log_path = '~/.console_kit_audit.log'

  # ── Rails-native sharding ────────────────────────────────────────────────────
  config.use_rails_sharding = true
  config.shard_role         = :writing

  # ── Tenant history ────────────────────────────────────────────────────────────
  config.recent_tenant_history_path = '~/.console_kit_history'
  config.recent_tenant_limit        = 5

  # ── ENV override key ─────────────────────────────────────────────────────────
  config.env_tenant_key = 'CONSOLE_KIT_TENANT'

  # ── Lifecycle hooks ───────────────────────────────────────────────────────────
  config.before_switch { |tenant| Datadog::Tracing.set_tag('tenant', tenant) }
  config.after_switch(on_error: :warn) { |tenant| Sentry.set_tag('tenant', tenant) }

  # ── ActsAsTenant ──────────────────────────────────────────────────────────────
  config.acts_as_tenant_model = 'Account'
  # Or custom finder:
  # config.acts_as_tenant_finder = ->(key, cfg) { Account.find_by(slug: key) }
end
```

---

## Supported connections

ConsoleKit activates each handler only when the corresponding gem is loaded:

| Connection         | Gem              | Config key              | What it does                                         |
|--------------------|------------------|-------------------------|------------------------------------------------------|
| SQL (ActiveRecord) | `activerecord`   | `shard`                 | `establish_connection` on your base class            |
| MongoDB            | `mongoid`        | `mongo_db`              | `Mongoid.override_database`                          |
| Redis              | `redis`          | `redis_db`              | `Redis.current.select(db)`                           |
| Elasticsearch      | `elasticsearch`  | `elasticsearch_prefix`  | `Elasticsearch::Model.index_name_prefix=`            |
| Apartment          | `apartment`      | `apartment_schema`      | `Apartment::Tenant.switch!`                          |
| ActsAsTenant       | `acts_as_tenant` | `acts_as_tenant_id`     | `ActsAsTenant.current_tenant=`                       |

### Apartment (PostgreSQL schema-based multi-tenancy)

```ruby
config.tenants = {
  acme: { constants: { shard: :acme_db, partner_code: 'acme', apartment_schema: 'acme' } }
}
# ConsoleKit calls Apartment::Tenant.switch!('acme') on startup
```

### ActsAsTenant (model-based multi-tenancy)

```ruby
config.tenants = {
  acme: { constants: { shard: :acme_db, partner_code: 'acme', acts_as_tenant_id: 1 } }
}
config.acts_as_tenant_model = 'Account'
# ConsoleKit calls ActsAsTenant.current_tenant = Account.find_by(id: 1)

# Custom finder:
config.acts_as_tenant_finder = ->(key, _cfg) { Account.find_by(slug: key) }
```

---

## Role-based presets

Define named configuration profiles for different user roles. Activate with `CONSOLE_KIT_ROLE`:

```ruby
ConsoleKit.configure do |c|
  c.presets = {
    support: {
      readonly_mode: true,
      confirm_dangerous_context: false
    },
    readonly_ops: {
      readonly_environments: %w[production staging]
    },
    engineering: {
      confirm_dangerous_context: true
    }
  }
end
```

```bash
CONSOLE_KIT_ROLE=support rails c
# Preset active: support
# [acme][production] main:001> User.update_all(...)
# ConsoleKit::ReadonlyViolation: update_all blocked: readonly mode active
```

Presets apply before tenant selection, so overrides like restricted tenant lists are in effect throughout startup. The doctor check validates preset attribute names:

```bash
rails console_kit:doctor
# ✓  2 preset(s) valid
```

---

## Scoped tenant switching

Switch tenant for a block — previous tenant restored automatically, even on exception:

```ruby
ConsoleKit.with(:beta) do
  User.count   # runs against beta
end
# back to acme

# Nestable
ConsoleKit.with(:acme) do
  ConsoleKit.with(:beta) { ... }
  # acme restored here
end
```

---

## Console helpers

```ruby
switch_tenant      # re-prompt for tenant selection
tenant_info        # print current tenant details
tenants            # list all configured tenants
dashboard          # connection diagnostics table
```

---

## Runtime introspection

```ruby
ConsoleKit.status
# ConsoleKit Status
#   Tenant     : acme
#   Configured : true
#   Environment: production
#   Shard      : acme_db
#   Readonly   : true

ConsoleKit.current_tenant   # => :acme
ConsoleKit.readonly?        # => true
```

---

## Console prompt

Tenant and environment always visible, even after `switch_tenant`:

```
[acme][production] main:001>
```

---

## Dynamic tenants

For apps with many tenants (too many to enumerate in config):

```ruby
ConsoleKit.configure do |c|
  c.tenants         = :dynamic
  c.tenant_resolver = ->(key) { TenantRegistry.resolve(key) }
  c.context_class   = CurrentContext
end
```

The resolver receives the selected key and returns a hash of constants (same shape as a static tenant's `constants:` block).

---

## Lifecycle hooks

```ruby
c.before_switch(on_error: :abort) { |tenant| AuditLog.record(tenant) }
c.after_switch(on_error: :warn)   { |tenant| Sentry.set_tag('tenant', tenant) }
```

`on_error: :abort` — hook exception vetoes the switch. `on_error: :warn` — logs warning, continues.

---

## Rails sharding

When `use_rails_sharding: true`, `ConsoleKit.with` wraps `ActiveRecord::Base.connected_to`:

```ruby
ConsoleKit.with(:beta) do
  # ActiveRecord::Base.connected_to(shard: :beta_db, role: :writing) is active
  Order.count
end
```

---

## Connection dashboard

```
--- Connection Dashboard ---
┌───────────────┬─────────────┬─────────┬──────────────────────────────────────────┐
│ Service       │ Status      │ Latency │ Details                                  │
├───────────────┼─────────────┼─────────┼──────────────────────────────────────────┤
│ SQL           │ ✓ Connected │ 1.1ms   │ adapter: PostgreSQL, pool_size: 5, ...   │
│ MongoDB       │ ✓ Connected │ 2.3ms   │ database: acme_db, version: 8.0.20       │
│ Redis         │ — N/A       │ —       │                                          │
│ Elasticsearch │ ✗ Error     │ —       │ error: connection refused                │
└───────────────┴─────────────┴─────────┴──────────────────────────────────────────┘
```

---

## Health check

```bash
rails console_kit:doctor
rails console_kit:doctor --verbose
```

```
  ✓  tenants configured
  ✓  tenant keys unique
  ✓  context_class resolves
  ⚠  tenant :beta missing key :shard
  ✓  sharding compatible
  ✓  readonly mode compatible
  ✓  audit log path writable
  ✓  Apartment 2.0.1 compatible
  ✓  ActsAsTenant configuration valid
  ✓  2 preset(s) valid

10 checks (1 warning)
```

---

## Integration examples

### Standard multi-db Rails (6.1+)

```ruby
# database.yml
production:
  primary: { ... }
  acme_db: { database: acme_production, ... }
  beta_db: { database: beta_production, ... }

# initializer
ConsoleKit.configure do |c|
  c.use_rails_sharding = true
  c.tenants = {
    acme: { constants: { shard: :acme_db, partner_code: 'acme' } },
    beta: { constants: { shard: :beta_db, partner_code: 'beta' } }
  }
  c.context_class = CurrentContext
end
```

### Mongoid

```ruby
ConsoleKit.configure do |c|
  c.tenants = {
    acme: { constants: { mongo_db: :acme_mongo, partner_code: 'acme' } }
  }
  c.context_class = CurrentContext
end
# ConsoleKit calls Mongoid.override_database(:acme_mongo) on startup
```

### Sidekiq context propagation

```ruby
c.after_switch { |tenant| Sidekiq::Client.default_context[:tenant] = tenant }
```

### Datadog + Sentry

```ruby
c.before_switch { |t| Datadog::Tracing.set_tag('tenant', t) }
c.after_switch(on_error: :warn) { |t| Sentry.set_tag('tenant', t) }
```

### CI / scripted sessions

```bash
CONSOLE_KIT_TENANT=acme rails runner 'puts ConsoleKit.current_tenant'
```

---

## Development

```bash
bin/setup
bundle exec rspec
bundle exec rubocop
bundle exec reek lib/
```

## Contributing

Bug reports and pull requests are welcome on GitHub at [console_kit](https://github.com/Soumyadeep-ai/console_kit). This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [code of conduct](https://github.com/Soumyadeep-ai/console_kit/blob/main/CODE_OF_CONDUCT.md).

## License

MIT License. See [LICENSE](https://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting in the ConsoleKit project's codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/Soumyadeep-ai/console_kit/blob/main/CODE_OF_CONDUCT.md).
