# Glossary

**Tenant.** One customer or environment your application serves. Configured as a key in
`config.tenants` with a `:constants` hash. See [Configuration](guides/configuration.md).

**Tenant key.** The Symbol or String naming a tenant (`:acme`). Lookup is an exact match, so
`validate!` rejects keys that differ only by case or type.

**Constants.** A tenant's values: `shard` and `partner_code` (required), plus `mongo_db`,
`redis_db`, `elasticsearch_prefix` and `environment`. An omitted backend constant resets that
backend to its default.

**Context class.** Your application's class (for example an `ActiveSupport::CurrentAttributes`) that
ConsoleKit writes tenant values onto, so application code sees the same tenant as the connections.

**Context attribute.** The writer on the context class a backend owns, such as `tenant_shard`.
Each attribute belongs to exactly one backend.

**Backend.** A data store ConsoleKit switches: SQL, MongoDB, Redis or Elasticsearch, or one you
add. See [Backends](guides/backends.md).

**Handler.** The class that switches one backend, a subclass of `BaseConnectionHandler`. See
[Writing a Handler](guides/custom-backend-handler.md).

**Backend key.** A handler's unique name in the registry: `:sql`, `:mongo`, `:redis`,
`:elasticsearch`.

**Constants key.** The constant a handler reads its target from, such as `:shard` for SQL.

**Target.** The value a handler is asked to switch to for the current tenant. `nil` means reset to
the default.

**Transactional switch.** `validate → prepare → snapshot → apply context → connect → verify →
commit`. The new tenant becomes current only at the commit. See
[Architecture](architecture/overview.md#tenant-switch-sequence).

**Snapshot / undo bundle.** What each handler and the context held before the switch, captured
before anything changes, deep-frozen, and kept on the committed tenant state.

**Rollback.** Restoring the undo bundle after a failed switch: handlers in reverse order, then the
context. Every component is attempted, and failures are collected into `rollback_failures`.

**Unwind.** The rollback `with_tenant` runs when its block exits, returning to the enclosing tenant.

**Verification.** After connecting, each handler reads its live state back and must report the
target. A mismatch raises `ConnectionVerificationError`. This is a local read, not a network call.

**Dropped backend.** A registered handler skipped because it is broken or unavailable for a stated
reason. It is never switched, verified or rolled back, and `verify_tenant!` reports it.

**Isolation model.** Whether a backend's switch is visible only to the current thread (`:scoped`)
or to the whole process (`:process_global`). See
[Concurrency and Isolation](switching.md#concurrency-and-isolation).

**Native path / fallback path.** The SQL handler's two ways to switch: `connecting_to` a registered
shard (per thread, no pool churn) or `establish_connection` (process-wide, replaces the pool).

**Diagnostic identity.** A value a handler reports so the dashboard knows when a cached `:full` row
is stale.

**Prefix registry.** `ElasticsearchPrefixRegistry`: the process-wide index prefix plus a record of
which prefix each live thread asked for, used to warn about conflicts.

**TenantState / StateStore.** The immutable record of the current tenant (key, constants, undo
bundle), and the per-thread slot that holds it.
