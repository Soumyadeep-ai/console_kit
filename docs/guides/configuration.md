# Configuration and Validation

Covers every setting, the tenant constants format, and every rule `validate!` enforces. For a
first-time setup walkthrough, see [Usage](../usage.md#usage).

??? abstract "Relevant source files"

    - [`lib/console_kit/configuration.rb`](https://github.com/Soumyadeep-ai/console_kit/blob/master/lib/console_kit/configuration.rb)
    - [`lib/console_kit/configuration_validator.rb`](https://github.com/Soumyadeep-ai/console_kit/blob/master/lib/console_kit/configuration_validator.rb)
    - [`lib/console_kit/errors.rb`](https://github.com/Soumyadeep-ai/console_kit/blob/master/lib/console_kit/errors.rb)
    - [`lib/console_kit.rb`](https://github.com/Soumyadeep-ai/console_kit/blob/master/lib/console_kit.rb)
    - [`lib/generators/console_kit/templates/console_kit.rb`](https://github.com/Soumyadeep-ai/console_kit/blob/master/lib/generators/console_kit/templates/console_kit.rb)


## Settings

Set inside `ConsoleKit.configure` (generated at `config/initializers/console_kit.rb` by
`rails generate console_kit:install`). Source: `lib/console_kit/configuration.rb`.

| Setting | Default | Notes |
|---|---|---|
| `tenants` | `nil` | Required. A Hash of tenant key → `{ constants: { ... } }`. |
| `context_class` | `nil` | Required. A Class, String or Symbol. Strings and Symbols are resolved with `safe_constantize` on every read, so they survive `reload!`. An unresolvable name raises `ConsoleKit::Error`. |
| `sql_base_class` | `'ApplicationRecord'` | The ActiveRecord class the SQL handler switches. See [Backends](backends.md#sql-activerecord). |
| `pretty_output` | `true` | Colored, prefixed output. Also toggled by `ConsoleKit.enable_pretty_output` / `disable_pretty_output`. |
| `show_dashboard` | `false` | Print the connection dashboard after each interactive tenant selection. |

The generated initializer wraps `configure` in `Rails.application.config.after_initialize`, so your
context class and models are loaded before ConsoleKit reads them.

## Tenant constants

```ruby
config.tenants = {
  acme: {
    constants: {
      shard: :shard_acme,           # required - SQL
      partner_code: 'acme',         # required - written to context.partner_identifier
      mongo_db: 'acme_db',          # optional - MongoDB
      redis_db: 1,                  # optional - Redis
      elasticsearch_prefix: 'acme', # optional - Elasticsearch
      environment: 'production'     # optional - banner warning only
    }
  }
}
```

| Constant | Context attribute written | Valid values |
|---|---|---|
| `shard` | `tenant_shard` | non-blank String or Symbol |
| `partner_code` | `partner_identifier` | anything (not validated) |
| `mongo_db` | `tenant_mongo_db` | non-blank String or Symbol |
| `redis_db` | `tenant_redis_db` | non-negative Integer, or a String of digits |
| `elasticsearch_prefix` | `tenant_elasticsearch_prefix` | String or Symbol: lowercase; not starting with `_`, `-` or `+`; no whitespace; none of `\ / * ? " < > \| , #` |
| `environment` | none | `'production'` prints a red banner, `'staging'` a yellow one (case-insensitive) |

**An omitted optional constant resets that backend to its default.** It does not leave the backend on
the previous tenant. See [Usage](../usage.md#usage).

The context class only needs writers for the attributes you use. ConsoleKit writes
`partner_identifier` whenever the context has a public `partner_identifier=` writer. It writes a
backend attribute only when the writer exists **and** that backend's handler is available.

## What `validate!` checks

`Configuration#validate!` runs at console boot (`TenantOrchestrator.run`) and can be called directly.
It collects **every** problem and raises them together as one `ConfigurationError`. Warnings are
printed and do not raise. Source: `lib/console_kit/configuration_validator.rb`.

Presence checks (each raises `ConsoleKit::Error` immediately):

- `tenants` is blank
- `tenants` is not a Hash
- `context_class` is blank

Per tenant (errors):

- The tenant key is not a non-blank Symbol or String.
- The tenant entry is not a Hash.
- `:constants` is missing or not a Hash.
- `shard` or `partner_code` is missing.
- A backend constant fails that handler's `target_error` (the "Valid values" column above).

Per tenant (warnings):

- Unrecognised constant keys, usually a typo such as `mongodb:` for `mongo_db:`. Recognised keys are
  `partner_code`, every registered handler's `constants_key`, and `environment`.

Across tenants:

- **Error:** two tenant keys are equal after `to_s.downcase` (for example `:acme` and `'ACME'`).
  Lookup is an exact match, so only one of them could ever be selected.
- **Warning:** a tenant omits a backend constant that other tenants set. Switching to it resets that
  backend.
- **Warning:** a constant is used but `context_class` has no writer for its attribute. That backend
  will never be configured during a switch.
- **Error:** `context_class` is a String or Symbol that does not resolve.

Validation of a single tenant also happens on every switch (`TenantPlan`). An unknown key raises
`TenantNotFoundError`, which lists the configured tenants. A malformed entry raises
`ConfigurationError`. Both are raised before anything is changed.
