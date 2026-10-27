# Try It in the Browser

A simulated `rails console` with ConsoleKit installed. It follows the gem's real selection rules
and prints its real messages, but runs entirely in your browser: there is no database behind it.
Click into the console and type.

<div class="ck-sim" data-ck-sim>
  <div class="ck-sim__bar">
    <span aria-hidden="true">bin/rails console</span>
    <button type="button" class="ck-sim__restart" hidden>Restart console</button>
  </div>
  <div class="ck-sim__screen">
    <div class="ck-sim__log" role="log" aria-live="polite" aria-label="Console output"></div>
    <form class="ck-sim__form" autocomplete="off">
      <label class="ck-sim__label" for="ck-sim-input"></label>
      <input class="ck-sim__input" id="ck-sim-input" type="text" spellcheck="false" autocapitalize="off" aria-label="Console input">
    </form>
  </div>
</div>

## Things to try

| Type | What it shows |
|---|---|
| Enter | The default answer, `1`: switches to `acme`, which prints the production warning |
| `globex`, or `GLOBEX` | Selecting by name ignores case. `globex` is staging. |
| `0` | Starting with no tenant (`[no-tenant]` prompt) |
| `umbrella` | A refused switch: its shard is not registered, so nothing changes |
| `foo` three times | Invalid answers, then the console loads without a tenant |
| `exit`, Ctrl+C or Ctrl+D at the menu | Leaves the console, just like the real boot |

Once you have a prompt:

| Type | What it shows |
|---|---|
| `switch_tenant`, then `initech` | `initech` sets no Redis DB or index prefix, so those backends reset to their defaults |
| `switch_tenant`, then `0` | Clearing the tenant |
| `tenant_info`, `tenants` | The console helpers |
| `dashboard`, `dashboard(level: :full)` | The connection dashboard |
| `ConsoleKit.switch_tenant(:globex)` | The programmatic switch: raises on failure, prints no banner |
| `ConsoleKit.switch_tenant(:nope)` | `TenantNotFoundError` |
| `ConsoleKit.with_tenant(:globex) { Order.count }` | Switches for the block, then restores your tenant. The restore prints nothing. |
| `ConsoleKit.with_tenant(:umbrella) { Order.count }` | Raises like `switch_tenant` and never runs the block. Inside a block the demo runs only `Order.count` and `ConsoleKit.current_tenant`. |
| `ConsoleKit.verify_tenant!` | Re-verification of the current tenant |
| `reload!` | Rails prints `Reloading...`. ConsoleKit re-applies your tenant silently, so nothing else shows. |
| `dashboard(level: :bogus)` | `ConfigurationError` for an unknown level |
| `help` | Everything this demo understands |

Arrow keys recall earlier input.

## The demo app's configuration

```ruby
ConsoleKit.configure do |config|
  config.tenants = {
    acme:     { constants: { shard: :shard_acme, partner_code: 'acme', mongo_db: 'acme_db',
                             redis_db: 1, elasticsearch_prefix: 'acme', environment: 'production' } },
    globex:   { constants: { shard: :shard_globex, partner_code: 'globex', mongo_db: 'globex_db',
                             redis_db: 2, elasticsearch_prefix: 'globex', environment: 'staging' } },
    initech:  { constants: { shard: :shard_initech, partner_code: 'initech', mongo_db: 'initech_db' } },
    umbrella: { constants: { shard: :shard_umbrella, partner_code: 'umbrella', mongo_db: 'umbrella_db',
                             redis_db: 4, elasticsearch_prefix: 'umbrella' } }
  }
  config.context_class = 'Current'
end
```

`database.yml` registers `shard_acme`, `shard_globex` and `shard_initech`, but not
`shard_umbrella`. The demo assumes all four backends are installed and a Redis client that is
isolated per thread. Dashboard latencies and server versions are made up, and the backtrace the
real console prints after `Failed to configure tenant` is left out.

What happens under the hood is described in [Console Boot and Selection](guides/console-boot.md)
and [Architecture](architecture/overview.md).
