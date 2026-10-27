# Backends

How each built-in handler switches, verifies and restores its backend, and when it refuses. For the
summary table and thread-isolation matrix, see [Supported Connections](../usage.md#supported-connections)
and [Concurrency and Isolation](../switching.md#concurrency-and-isolation).

Every handler follows the same lifecycle inside a switch (see
[Architecture](../architecture/overview.md#tenant-switch-sequence)):

`prepare(target)` → `snapshot` → `connect!(target)` → `verify!(target)`, and `restore(snapshot)`
on rollback.

A `nil` target means the tenant does not set that constant. Every handler treats `nil` as **reset to
the default**, not "leave alone".

## SQL (ActiveRecord)

`lib/console_kit/connections/sql_connection_handler.rb`, `sql_strategy.rb`

**Available** when `config.sql_base_class` (default `'ApplicationRecord'`) resolves to a class. If you
set a non-default name that does not resolve, the handler is reported as *dropped*. A missing
`ApplicationRecord` is treated as "no SQL here" and stays silent.

**Two paths**, chosen per switch by `SqlStrategy`:

| Path | Used when | Switches with | Verifies against | Isolation |
|---|---|---|---|---|
| Native | the base class supports `connecting_to` and a pool is registered for that shard | `connecting_to(shard:, role: current_role)` | `current_shard` | per thread (fiber-local) |
| Fallback | otherwise | `establish_connection(shard)`, skipped if already on that db config | `connection_pool.db_config.name` | process-wide, replaces the pool |

A `nil` target uses the native path when there is a `connected_to` stack to reset, and otherwise
re-establishes the environment's first database config.

**Refuses (in `prepare`):**
- `UnsupportedBackendError` when the base class has neither `establish_connection` nor the native
  sharding API.
- `ConfigurationError` when the shard is neither a registered native shard nor a `database.yml`
  config name for the current environment.

**Snapshot** records shard, role, `connected_to_stack` depth, db config name, and whether a pool
existed. **Restore** pops the stack back to its old depth, re-applies the old shard, and then either
removes a pool ConsoleKit created or re-establishes the old db config.

**Host `connected_to` blocks.** ConsoleKit remembers the stack frame it pushed (`ShardFrame`, held in
a thread variable). If your own `connected_to` block removes that frame, the next read of the live
shard re-applies ConsoleKit's shard, prints a warning, and increments
`console_kit.sql_frame_reasserted`.

**Diagnostics:** basic reports pool adapter, size, config and shard. Full runs `SELECT 1` for latency
and adds adapter, pool size and server version.

## MongoDB (Mongoid)

`lib/console_kit/connections/mongo_connection_handler.rb`, `mongoid_support.rb`

**Available** when `Mongoid` is defined.

**Switches** with `Mongoid.override_client(target)` when `target` names a client in
`Mongoid::Config.clients`. Otherwise it uses `Mongoid.override_database(target)`. A `nil` target
clears both overrides. The overrides live in `Mongoid::Threaded`, so they are per thread.

**Verifies:** for a named client, `Mongoid::Threaded.client_override == target`. For a database
name, `Mongoid.default_client.database.name == target`. For `nil`, both overrides must be unset.

**Refuses (in `prepare`, `UnsupportedBackendError`):**
- This Mongoid version lacks the setter the target needs (`override_client` or `override_database`).
- The overrides cannot be read back (`Mongoid::Threaded.database_override`, plus `client_override`
  when `override_client` exists). Without them a switch can be neither verified nor rolled back.

**Snapshot/restore:** `{ client:, database: }` overrides, written back with both setters.

**Diagnostics:** basic reports the database name. Full pings and adds the server version.

## Redis

`lib/console_kit/connections/redis_connection_handler.rb`, `redis_client_adapter.rb`

**Available** when `Redis` or `RedisClient` is defined. The handle it drives is `Redis.current`
(redis-rb 4). If that is missing, there is no client to select on.

**Switches** with `SELECT <db>` on that handle. A `nil` target means DB `0`. The switch is skipped
when the client is already on that DB or the current DB cannot be read. The DB is read from the
client's `db`, `config.db` or `connection[:db]`.

**Verifies** `(current_db || 0) == expected`. This is a local read of the client's cached DB, not a
round trip.

**Refuses (in `prepare`, `UnsupportedBackendError`)** a non-`nil` `redis_db` when the client cannot
`select` or its current DB cannot be read. The message tells you to point each tenant at its own
Redis URL instead. This includes setups with only the `redis-client` gem and no `Redis.current`.

**Isolation model** (`#isolation_model`), probed by resolving the client on a second thread:

| Value | Meaning |
|---|---|
| `:process_global` | Both threads got the same object. `SELECT` affects every thread. A warning prints once per process. |
| `:scoped` | Each thread gets its own client. |
| `:none` | No client is resolvable. |
| `:unknown` | The probe itself failed. This result is not memoized, so the next call probes again. |

**Snapshot/restore:** `{ db: }`, re-selected only if it differs.

**Diagnostics:** basic reports DB and isolation model. Full pings and adds `redis_version` and
`used_memory_human` from `INFO`.

## Elasticsearch

`lib/console_kit/connections/elasticsearch_connection_handler.rb`, `elasticsearch_prefix_registry.rb`

**Available** when `Elasticsearch::Model` is defined and responds to `client`.

**Switches** `Elasticsearch::Model.index_name_prefix = target`. This value is **always process-global**:
`isolation_model` is `:process_global` and `thread_isolated?` is `false`. `ElasticsearchPrefixRegistry`
also records which prefix each live thread asked for. If other live threads hold a different
prefix, the switch warns once per (prefix, conflicting set) and names them. The last writer still
wins.

**Verifies** the effective prefix: the global reader when it exists, otherwise this thread's recorded
prefix.

**Refuses (in `prepare`, `UnsupportedBackendError`):**
- A prefix is requested but `index_name_prefix=` does not exist.
- The setter exists but there is no `index_name_prefix` reader, so the switch could not be verified
  or rolled back.

Prefix format rules are listed in [Configuration](configuration.md#tenant-constants).

**Snapshot/restore:** `{ global:, thread: }`, both written back.

**Diagnostics:** basic reports prefix and isolation model. Full pings, reads cluster health, and adds
the cluster name and status.

## Diagnostics rows and the dashboard

Each handler's diagnostics return a row hash: `{ name:, status:, latency_ms:, details: {} }`. The
`dashboard` helper renders `status` as follows:

| `status` | Shown as |
|---|---|
| `:connected` | ✓ Connected |
| `:error` | ✗ Error, with the scrubbed message truncated to 60 characters |
| `:unavailable` | — N/A, when the handler's gem is not loaded |
| anything else (for example SQL's `:unknown`) | ? Unknown |
