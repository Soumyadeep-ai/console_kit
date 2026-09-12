# ConsoleKit

![Gem Version](https://img.shields.io/gem/v/console_kit.svg)
![Gem Downloads](https://img.shields.io/gem/dt/console_kit.svg)
![Build Status](https://github.com/Soumyadeep-ai/console_kit/actions/workflows/release.yml/badge.svg)
![License](https://img.shields.io/github/license/Soumyadeep-ai/console_kit)
![Ruby](https://img.shields.io/badge/ruby-%3E=3.1.0-red)
![Rails](https://img.shields.io/badge/rails-6.1%20%E2%80%93%208.1-red)

A simple and flexible multi-tenant console setup toolkit for Rails applications.

ConsoleKit helps you manage tenant-specific database connections (SQL, MongoDB, Redis, Elasticsearch) and context configuration via an easy CLI interface and Rails integration.

## Compatibility

Every combination below is exercised by CI on each push - 28 cells, all of them required.

| Rails | Ruby |
|---|---|
| 6.1 | 3.1, 3.2, 3.3, 3.4, 4.0 |
| 7.0 | 3.1, 3.2, 3.3, 3.4, 4.0 |
| 7.1 | 3.1, 3.2, 3.3, 3.4, 4.0 |
| 7.2 | 3.1, 3.2, 3.3, 3.4, 4.0 |
| 8.0 | 3.2, 3.3, 3.4, 4.0 |
| 8.1 | 3.2, 3.3, 3.4, 4.0 |

The gem requires Ruby `>= 3.1` and Rails `>= 6.1`, with no upper bound on either.

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

  # Optional: Show connection dashboard on tenant switch (default: false)
  # config.show_dashboard = true
end
```

A constants key you omit is not left alone: switching to that tenant **resets** that backend to its
default. That is deliberate - leaving Redis on the previous tenant while SQL moves would be exactly
the mixed-tenant state this gem exists to prevent. Only `shard` and `partner_code` are required.

## Supported Connections

ConsoleKit automatically detects and manages connections for:

| Connection         | Gem Required    | Config Key             | How it switches                                                        | How it is verified                     |
|--------------------|-----------------|------------------------|------------------------------------------------------------------------|----------------------------------------|
| SQL (ActiveRecord) | `activerecord`  | `shard`                | `connecting_to(shard:)` for registered shards, `establish_connection` otherwise | `current_shard` / `db_config.name`     |
| MongoDB            | `mongoid`       | `mongo_db`             | `Mongoid.override_client` for named clients, `override_database` otherwise      | effective client or database name      |
| Redis              | `redis`         | `redis_db`             | `SELECT` on the application's Redis handle                             | the client's cached logical DB         |
| Elasticsearch      | `elasticsearch` | `elasticsearch_prefix` | `Elasticsearch::Model.index_name_prefix=`                              | the effective index prefix, read back  |

Handlers are only activated when their corresponding gem is loaded. Verification is a local read on
every backend - switching a tenant makes no diagnostic network calls.

## Tenant Switching Guarantees

A tenant switch is transactional:

```
validate -> snapshot -> prepare -> apply context -> connect -> verify -> commit
```

Two invariants follow from that:

1. **At every switch boundary, ConsoleKit is either still on the previous tenant or completely on
   the new one.** The new tenant only becomes current at the final commit, so once `switch_tenant`
   returns - successfully or not - you are never left with the context on tenant B, SQL on B and
   Redis still on A.

   This is a guarantee about boundaries, not about instants. A switch applies the context, then each
   backend in turn, then verifies. While it is running there is genuinely a window in which some
   backends have moved and others have not, and for the process-global backends below that window is
   visible to other threads. See [Concurrency and Isolation](#concurrency-and-isolation).
2. **A successful connection is not enough.** After connecting, each backend is read back and must
   report the tenant that was asked for. A handler that silently ignored the switch, or a foreign
   writer that moved the backend between connect and verify, fails the switch instead of quietly
   serving another tenant's data.

   Be precise about what this buys you: verification is a local read of the handle ConsoleKit just
   wrote, not a round trip that interrogates the server. It catches a write that did not take. It
   cannot catch a `database.yml` entry that points `shard_acme` at another tenant's server. It is an
   attestation, not a proof of provenance.

If anything fails, every touched component is restored - the context attributes and all four
backends - and the switch raises. Each component is attempted even when an earlier restore fails, so
one broken backend cannot strand the rest.

### Errors

```ruby
ConsoleKit.switch_tenant(:globex)
# ConsoleKit::TenantSwitchError:
#   Failed to switch tenant from :acme to :globex (MongoDB):
#   MongoDB verification failed. Expected "globex_db", got "acme_db"
#
#   Previous tenant state was restored successfully.
```

A rollback can itself fail, and that is reported separately rather than replacing the root cause:

```ruby
# ConsoleKit::TenantSwitchError:
#   Failed to switch tenant from :acme to :globex (MongoDB):
#   MongoDB verification failed. Expected "globex_db", got "acme_db"
#
#   WARNING: rollback did not fully succeed:
#     - SQL: shard registry offline
```

`TenantSwitchError` exposes `#original_error`, `#rollback_failures` and `#rollback_succeeded?`.
The exception hierarchy, all under `ConsoleKit::Error`:

| Error | Raised when |
|-------|-------------|
| `ConfigurationError` | configuration is missing, malformed or unusable |
| `TenantNotFoundError` | the tenant key is not in the configured tenant map |
| `ConnectionError` | a backend could not be connected or inspected |
| `ConnectionVerificationError` | a backend connected but points at the wrong tenant |
| `UnsupportedBackendError` | the installed client cannot support the requested operation |
| `TenantSwitchError` | a switch failed; carries the root cause and any rollback failures |
| `RollbackError` | restoring previous state failed |

Credentials are scrubbed from error messages, diagnostic rows and console output: connection URIs,
`key=value` and `key => value` fragments, `Authorization: Bearer <token>` style auth headers, bare
`password <value>` phrases and `for user <name>` principals. Hostnames and ports are deliberately
kept - they are not secrets, and removing them would gut the diagnostic value of a connection error.

Scrubbing is shape-matching over strings ConsoleKit did not produce, so treat it as defence in
depth rather than a boundary: it errs toward redacting, and a client version emitting a shape it has
not seen could still get through. Do not put secrets anywhere they could be logged in the first
place.

## Programmatic API

The console prompt is the usual entry point, but the same operations are available directly:

```ruby
# Raising, programmatic switch. Atomic: on failure the previous tenant is restored.
ConsoleKit.switch_tenant(:acme)

# The current tenant key, or nil.
ConsoleKit.current_tenant  # => :acme

# Re-verify that every available backend still points at the current tenant.
ConsoleKit.verify_tenant!

# Nested, exception-safe scope. The enclosing tenant is restored on exit,
# including when the block raises or the inner switch fails.
ConsoleKit.with_tenant(:globex) do
  Order.count
end
# back on :acme here

# Validate the whole configuration up front. Reports every problem at once.
ConsoleKit.configuration.validate!
```

`ConsoleKit.switch_tenant` raises on failure. The interactive console flow deliberately does not -
it reports through the console output and returns `false`, so a mistyped tenant does not tear down
your session.

Not every failure is a `TenantSwitchError`. Problems found before anything is applied - an unknown
tenant, malformed constants, a backend that cannot support the request - raise
`TenantNotFoundError`, `ConfigurationError` or `UnsupportedBackendError` directly, because there is
nothing to roll back. Rescue `ConsoleKit::Error` if you want to catch all of them:

```ruby
begin
  ConsoleKit.switch_tenant(:globex)
rescue ConsoleKit::TenantSwitchError => e
  # the switch was attempted and rolled back
  warn e.message unless e.rollback_succeeded?
rescue ConsoleKit::Error => e
  # rejected before anything was touched
  warn e.message
end
```

`verify_tenant!` raises `ConnectionVerificationError` on a mismatch and does **not** roll back - it
is a report on the current state, not a repair. If it fails, the backends really are inconsistent
and you should switch again explicitly. It checks against the tenant constants frozen at the moment
you switched, so reloading or replacing your configuration afterwards does not make it lie.

It also reports backends that were never switched at all. A handler that exists but is broken is
dropped from the switch, and a switch that silently skipped a backend must not be allowed to look
fully verified:

```ruby
ConsoleKit.verify_tenant!.dropped_backends
# => [:elasticsearch]   # this backend was never switched, verified or rolled back
```

A backend whose gem simply is not installed is not "dropped" - that is a supported setup and is
never reported.

## Concurrency and Isolation

**Read this before using ConsoleKit anywhere other than a console.**

ConsoleKit invents no isolation of its own. It writes through whatever handle your client library
gives it, so isolation is exactly as good as that handle:

| Component | Isolated per thread? |
|-----------|----------------------|
| ConsoleKit's own tenant state | **Yes** |
| Mongoid overrides (`Mongoid::Threaded`) | **Yes** |
| ActiveRecord native shard path (`connecting_to`) | **Yes** - fiber-local |
| Your context object | **Only if it stores per-thread** (e.g. `ActiveSupport::CurrentAttributes`) |
| ActiveRecord `establish_connection` fallback | **No** - replaces a process-wide pool |
| Redis via `Redis.current` (redis-rb 4) | **No** - process-global singleton |
| Elasticsearch `index_name_prefix` | **No** - one process-wide attribute |

Where isolation does not exist, the last writer wins for the whole process. The two backends whose
isolation depends on the installed client report it at runtime:

```ruby
ConsoleKit::Connections::RedisConnectionHandler.new(ctx).isolation_model
# => :scoped, :process_global, :none, or :unknown

ConsoleKit::Connections::ElasticsearchConnectionHandler.new(ctx).isolation_model
# => :process_global (always)
```

Both also answer `thread_isolated?`. The SQL and Mongoid handlers do not define these - their
isolation depends on which code path is taken, as the table above shows.

Redis on redis-rb 4 prints a one-time warning that DB selection is process-wide. Elasticsearch warns,
naming both prefixes, when live threads disagree about the prefix.

**`switch_tenant` is a console tool, not a per-request multi-tenancy mechanism.** Because it mutates
process-global backend state, calling it from a request or a background job will change the tenant
for every other thread in that process. For real isolation, run one tenant per process.

`ConsoleKit.with_tenant` and `ConsoleKit.current_tenant` are safe to read anywhere; it is the
switching itself that is process-affecting.

## Observability

ConsoleKit emits timing and counts through a small internal hook. There is no external dependency -
wire it to whatever you already use:

```ruby
ConsoleKit::Instrumentation.subscribe do |name, duration_ms, payload|
  Rails.logger.info("#{name} #{duration_ms}ms #{payload.inspect}")
end

ConsoleKit::Instrumentation.counts
# => { "console_kit.tenant_switch" => 3, "console_kit.rollback" => 1, ... }
```

Events cover tenant switches, per-backend connect and verify, rollbacks, verification failures and
diagnostics. Payloads carry tenant keys and backend names - never credentials.

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

# Show connection diagnostics dashboard
dashboard
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

See [Programmatic API](#programmatic-api) for `switch_tenant`, `with_tenant` and `verify_tenant!`.

### Connection Dashboard

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

The dashboard takes a level:

```ruby
dashboard                 # :basic - no network calls at all
dashboard(level: :full)   # adds version, health and latency probes
```

`:basic` is the default and reports only what can be read locally, so it is cheap enough to run
freely. Switching a tenant never triggers diagnostics on its own.

`:full` queries each handler with a 2-second timeout, on a bounded set of reusable per-backend
workers - the thread count is capped no matter how often you type `dashboard`, and a backend whose
previous check is still running reports as busy rather than starting another one. `:basic` needs no
timeout because it never leaves the process.

Only `:full` results are cached, for a couple of seconds; `:basic` is never cached, because it is a
local read and caching it bought nothing while costing correctness.

A cached `:full` row is reused only while all three hold: the TTL has not elapsed, the calling thread
is still on the same tenant state, and the backend still reports the same observed identity - the
Elasticsearch prefix, the Redis logical DB, the SQL pool. So another thread moving a process-global
backend drops the row on the next render rather than serving it stale. That identity check is a
memory read, so a cached render still costs zero round trips. What can be up to a cache window old is
only the *measured* part of a row - latency, cluster health, version, memory - never which tenant a
backend is on.

To auto-display the dashboard on every tenant switch, add to your initializer:

```ruby
config.show_dashboard = true
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
