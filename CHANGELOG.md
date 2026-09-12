# Changelog

All notable changes to this project will be documented in this file.

This project adheres to [Semantic Versioning](https://semver.org/).

---

## [1.5.0] - 2026-09-05

Hardening release. Tenant switching is now transactional: a switch either
completes fully or leaves the previous tenant exactly as it was.

### Added
- **Atomic tenant switching.** `TenantSwitch` runs `validate -> snapshot -> prepare -> apply context -> connect -> verify -> commit`. The new tenant is not observable as current until the final commit, so a partially applied tenant state can no longer survive a failure.
- **Rollback.** Any failure restores every touched component: context attributes and all four backends. Each component is attempted even when an earlier one fails, so one broken backend cannot strand the rest.
- **Connection identity verification.** A successful connection is no longer accepted as proof. SQL compares `current_shard` / `db_config.name`, Mongoid the effective client or database name, Redis the client's cached logical DB, Elasticsearch the effective index prefix. All are local reads with no network round trip; a mismatch raises `ConnectionVerificationError` and fails the switch.
- **Exception taxonomy.** `ConfigurationError`, `TenantNotFoundError`, `ConnectionError`, `ConnectionVerificationError`, `TenantSwitchError`, `RollbackError` and `UnsupportedBackendError`, all under `ConsoleKit::Error`. `TenantSwitchError` carries `#original_error`, `#rollback_failures` and `#rollback_succeeded?`, so a rollback failure never replaces the root cause.
- **`TenantState` and `StateStore`.** All per-thread tenant state now lives in one thread-local holding one value object, replacing five independent `Thread.current` keys.
- **`ConsoleKit.switch_tenant(:acme)`** — programmatic, raising counterpart to the interactive console flow.
- **`ConsoleKit.with_tenant(:acme) { ... }`** — nested, exception-safe tenant scope that restores the enclosing tenant on exit.
- **`ConsoleKit.verify_tenant!`** — re-verify that every available backend still points at the current tenant.
- **Diagnostic levels.** `dashboard(level: :basic)` (the default) performs no network calls; `level: :full` keeps the version/health probes. Tenant switching triggers no diagnostics at all.
- **Diagnostic caching.** A short TTL cache keyed by tenant state, level and backend. A tenant switch invalidates it immediately, and `:timeout` / `:error` rows are never cached, so a recovered backend is never masked.
- **Instrumentation hook.** `ConsoleKit::Instrumentation.subscribe { |name, duration_ms, payload| ... }` plus counters for switches, verifications, rollbacks and diagnostic timeouts. No external dependency.
- **Strict configuration validation.** `ConsoleKit.configuration.validate!` now reports every problem in one pass: tenant structure, identifiers, duplicate identifiers colliding by case or type, required constants, Redis DB numbers, Elasticsearch prefixes, shard and Mongoid client names. Unrecognised constants keys and a `context_class` missing writers are reported as warnings.
- **Isolation reporting.** `RedisConnectionHandler#isolation_model` / `#thread_isolated?` and the Elasticsearch equivalents report at runtime whether a backend is genuinely per-thread or process-global.

- **`TenantState#dropped_backends` and dropped-backend reporting.** A handler that exists but is only half-implemented is dropped from a switch. It is now recorded on the committed state and reported by `verify_tenant!`, so a switch that silently skipped a backend can no longer look fully verified. A backend whose gem is simply absent is not reported - that is a supported setup.
- **Handlers declare their own backend.** `backend :key, display_name:, context_attribute:, constants_key:, detail_label:` plus `.target_error` as the single validation rule. Adding a backend means adding one file; nothing outside a handler names a backend. Registration is explicit rather than `Class#descendants`, and the registry is keyed by backend, so two live reload generations of one backend cannot be represented.

### Changed
- **Connection pool churn removed.** The SQL handler now uses the native `connecting_to(shard:)` path when the target is a registered shard, detected by capability check rather than by Rails version. The `establish_connection` fallback re-establishes only when the resolved configuration actually changes, and no longer disconnects a pool that Rails is about to replace anyway. Switching to the shard already in use performs no pool work.
- **`reapply`** no longer re-establishes a connection that is already on the target shard.
- Diagnostics run on a bounded set of reusable per-backend workers instead of a fresh thread per call.
- `ContextWrapper#assign` returns a Hash of applied values rather than triples, and owns the case-mismatch warning itself. It gained `current_values` and `restore`.
- `TenantConfigurator.validate_constants!` moved to `ConsoleKit::TenantPlan`. `configuration_success` is now derived from `StateStore` and is joined by a `configuration_success?` predicate.

### Fixed
- **Unbounded diagnostic thread leak.** Every timed-out dashboard call previously abandoned a thread permanently. Diagnostics now use a capped set of reusable workers; a backend whose worker is still busy reports busy rather than spawning another thread. Threads are still never killed, preserving the 1.3.0 fix.
- **`NotImplementedError` escaped the transaction.** It descends from `ScriptError`, not `StandardError`, so a handler that implemented `available?`, `snapshot` and `prepare` but not `connect!` bypassed rollback entirely and left the process half-switched.
- **A failing `snapshot` destroyed the root cause.** The undo bundle was captured inside the guarded region, so a snapshot failure produced a `NoMethodError` from the rollback path in place of the real error, and no rollback ran.
- **`ContextWrapper#restore` aborted on the first failing writer**, stranding the remaining context attributes on the tenant the switch failed to reach while `current_tenant` reported the previous one.
- **A context attribute whose getter raised was snapshotted as `nil`**, so rollback wrote that `nil` over a real previous value and then reported a clean rollback. Unreadable attributes are now recorded with a sentinel, skipped on restore, and reported as rollback failures, so `rollback_succeeded?` cannot lie about them.
- **Elasticsearch `:full` diagnostics reported `Connected` for an unreachable cluster.** The ping failure was swallowed and `cluster.health` was called anyway.
- **A failed Mongoid, Redis or Elasticsearch switch could look like a success.** Each handler rescued `NoMethodError` and printed a warning while the caller carried on.
- **The ActiveRecord shard stack grew without bound.** `connecting_to` pushes onto `connected_to_stack` and `restore` popped only on failure, so every committed switch left a frame behind - and since the Railtie reapplies on every Rails `reload!`, a long console session accrued hundreds of frames that Rails walks on every `current_shard` lookup. The stack now holds exactly one ConsoleKit frame regardless of switch count, and an application's own `connected_to` blocks are never disturbed.
- **A misconfigured `sql_base_class` silently removed SQL from every switch.** An unresolvable class name made `available?` return false, which is indistinguishable from ActiveRecord not being loaded, so SQL was never switched, verified or rolled back while the switch still reported itself verified. A non-default class name that cannot be resolved now warns.
- **The Redis isolation probe returned a verdict when it failed.** A programming error inside ConsoleKit was rescued into `:process_global` - an isolation claim the rest of the system then trusted. Programming errors re-raise, and a genuine probe failure reports the new `:unknown`.
- **Handler discovery returned reload duplicates in non-deterministic order.** The registry is `descendants`, so a Zeitwerk reload leaves stale generations registered: the switch connected both while the snapshot map kept only one, so a rollback could restore a handler from a different generation's snapshot. Handlers are now deduplicated by backend and ordered deterministically.
- **`level: :basic` diagnostics were cached and could go stale.** Cache freshness keys on `TenantState` identity, which only changes when the calling thread switches, so a foreign thread moving a process-global backend left a stale row reported as current. `:basic` is a pure local read, so it is no longer cached at all; the TTL cache applies to `:full`, which is what the dashboard-hammering requirement was about.

- **`verify_tenant!` re-resolved the tenant through the mutable global configuration**, so a `reload!` or a second `configure` made it raise `TenantNotFoundError` about a tenant that was verifiably still connected. It now verifies against the constants frozen into the state at commit time.
- **Two definitions of "programming error" had drifted.** `TypeError` was re-raised in one subsystem and swallowed as "dependency unavailable" in another - exactly the masking the narrowing existed to prevent. There is now one list.
- **The handler registry was handed out as a live mutable array**, so any caller could reorder or empty the collection that decides what a switch touches.

- **Mongoid version tolerance was asymmetric, and lost rollback fidelity.** `restore`, `reset_overrides`, `named_client?` and both override readers were feature-detected for a Mongoid exposing only `override_database`, but the read-back used by verification was not. On exactly the client shape those guards exist for, a switch passed `prepare`, applied the override, then failed at `verify!` with a `NoMethodError` - and because `snapshot` had returned empty on that shape, rollback cleared the override instead of restoring it, silently. A target that cannot be read back is now refused at `prepare`, before anything is mutated, the way the Redis handler refuses a client it cannot select on.

- **A tenant switch made inside a host `connected_to` block silently served the wrong tenant.** ConsoleKit pushed an unbalanced frame and Rails pops by position, so the block's `ensure` removed ConsoleKit's frame: `current_tenant` reported one tenant while `current_shard` was another, and each block leaked a frame. ConsoleKit now keeps exactly one frame, held beneath any host frame, so a host block can only pop its own. A switch attempted inside such a block fails verification and rolls back rather than committing; the one case that cannot be prevented - the first switch inside a block, before ConsoleKit owns a frame - is detected on the next read, re-applied, warned about, and counted as `console_kit.sql_frame_reasserted`.
- **`verify_tenant!` reported only the backends dropped at switch time**, so a handler that broke after a clean switch was reported as verified. It now reports the union of switch-time and verify-time drops.
- **Re-declaring `backend` registered a class twice, permanently**, so its handler connected and verified twice while the snapshot map kept one entry. A re-declaration now drops the class's previous key.
- **`target_error` drifted between its two call sites.** `validate!` saw the raw value and the switch saw it `.presence`-stripped, so `shard: ''` raised at boot yet switched fine. Both now judge the same value, and `TenantPlan` reads the handler's own `constants_key` rather than the merged mapping, so one backend can no longer read another's key.
- **Every handler's `diagnostics` swallowed programming errors** into an `:error` row, bypassing the classification added earlier in this release. They now re-raise.
- **The gem did not require the ActiveSupport core extensions it uses.** `Time.current` was unavailable unless the host had already loaded more of Rails; the suite only passed because a test dependency did. Now required explicitly.
- **`validate!` warned about `:environment`**, a key the generator template documents and the gem itself reads and displays, and false-warned that a context would never be configured when its writers live on the singleton - the shape the README itself uses.
- **`clear` left the state marked configured**, so `verify_tenant!` afterwards "verified" a tenant that was not set.
- **An undeclared handler subclass silently reset its backend to default**; it now inherits its parent's declaration.

- **A cached `:full` diagnostic row could report a tenant identity another thread had already changed.** Cache freshness keyed only on the calling thread's tenant state, which a foreign thread moving a process-global backend never touches - the same staleness that stopped `:basic` being cached at all. A cached `:full` row is now reused only while the backend still reports the same observed identity, which is a memory read, so cached renders still cost zero round trips.
- **The Redis isolation probe could claim `:scoped` on no evidence.** A probe thread that could not reach the client returned nil, which read as "a different object, so the client must be per-thread" - turning a failed observation into the strongest claim the class makes. It now reports `:unknown`.
- **One thread was spawned per tenant switch** by the Redis isolation probe, and one per Rails `reload!` and per `:basic` dashboard render. The probe is now memoised per thread against the resolved client's identity: five switches spawn one thread, and later renders spawn none while the client is unchanged. `:scoped` detection is unaffected - it still probes on a fresh thread on first observation and whenever the client changes.
- **Elasticsearch accepted any object as a prefix**, coercing it with `to_s`, so an Integer or Hash silently became an index prefix. Non-String/Symbol values are now rejected at `validate!` and `prepare`.
- **A broken handler re-printed its drop warning on every dashboard render**; it now warns once per backend and reason per thread, while the counter still records every drop.
- **A diagnostics worker failing on something other than a StandardError reported `:timeout`**, masking the real failure; it now reports the real error.
- **`prepare`'s rejection message did not scrub the value it rejected**, unlike the configuration validator, and a tenant constant can carry a URI.

### Security
- **Credentials no longer reach error messages.** Tenant constants can carry connection URIs, so an authentication failure could put a plaintext password into `TenantSwitchError#message` and from there into logs and consoles. Root causes, rollback failures, diagnostic rows, configuration-validation messages and the interactive console's own error output are all scrubbed.
- **The scrubber now covers the shapes real clients actually emit.** It previously matched only `scheme://` URLs and bare `key=value` pairs, so a quoted `"password"=>"hunter2"` hash, a PostgreSQL `password authentication failed for user "svc_admin"`, a space-separated `with password hunter2`, a Redis `WRONGPASS ... for user default` and a Mongo `User svc_admin@admin` all passed through intact - while `Mongo::Auth::Unauthorized` was itself mangled, because `::` was read as an assignment. Hostnames and ports are deliberately still shown; they are not secrets, and removing them would gut the diagnostic value of a connection error.
- **Elasticsearch cross-thread prefix conflicts are now detected.** `Elasticsearch::Model.index_name_prefix` is process-wide; when live threads hold different prefixes ConsoleKit warns once, naming both, instead of silently letting one thread read another tenant's indices.
- Broad `rescue StandardError` blocks were narrowed. Programming errors (`NoMethodError`, `NameError`, `ArgumentError`, `TypeError`) are no longer laundered into ordinary "dependency unavailable" results.

- **Auth headers leaked their credential.** The scrubber stopped at the first whitespace, so `Authorization: Bearer <token>` was redacted to `[redacted] <token>` - the label removed and the secret kept. Auth schemes are now spanned.
- **`scrub` raised on a message that was not valid UTF-8.** It runs inside `TenantSwitchError`'s constructor, so an invalid byte sequence from a driver replaced the root cause with an encoding error and escaped `switch_tenant`; through a diagnostic row it also took the dashboard down, since `ArgumentError` is classified as a programming error and re-raised. Invalid bytes are replaced before matching.

### Performance
Measured, not asserted. `bundle exec rake benchmark` runs entirely against fakes, so it needs no database, Redis, Mongo or Elasticsearch. Counts are facts; timings are indicative and reported with run-to-run variance.

- **Connection pool churn, per switch:**

  | Path | `establish_connection` | `disconnect` |
  |------|------------------------|--------------|
  | native shard, same shard | 0 | 0 |
  | native shard, different shard | 0 | 0 |
  | native shard, reset to default | 0 | 0 |
  | fallback, same shard | 0 | 0 |
  | fallback, different shard | 1 | 1 |
  | fallback, reset to default | 1 | 1 |

  Before 1.5.0 every switch performed one `disconnect!` plus one `establish_connection` unconditionally, including a switch to the shard already in use, and including registered shards where no pool work is needed at all.
- **Network calls per tenant switch: 0**, including `verify_tenant!` - verification is a local read on every backend. `dashboard(level: :basic)` performs 0 cold and cached; `level: :full` performs 8 cold and 0 within the cache window.
- **Allocations per switch:** ~205 objects switching between tenants, ~194 repeating the same tenant.
- `TenantConfigurator.configure_tenant` short-circuits a repeat of the current tenant at roughly 300x the cost of a full switch. `ConsoleKit.switch_tenant` deliberately does not short-circuit - it re-runs the whole transaction, because its purpose is to guarantee the state rather than to assume it.
- The 1.3.0 `base_class` memoization is retained.

### Breaking changes
- **redis-rb 5 and redis-client:** these expose no process-wide client handle, so a non-default `redis_db` now raises `UnsupportedBackendError` from `prepare` instead of printing a warning and silently running against the wrong DB. Give each tenant its own Redis URL, for example `redis://redis.internal:6379/<db>`.
- **Elasticsearch prefixes** containing uppercase characters, whitespace, a leading `_`, `-` or `+`, or any of `\ / * ? " < > | , #` now raise `ConfigurationError` before any mutation. Previously they were passed through and rejected later, or silently produced unusable index names.
- **Incomplete tenant entries now fail `validate!`.** A tenant with no `:constants`, or missing `shard` / `partner_code`, previously validated as fine and only broke at switch time.
- **A failed backend switch now raises rather than warning.** `ConsoleKit.switch_tenant` raises `TenantSwitchError`; the interactive console flow still reports through `Output` and returns `false`.

### Removed
- `StateStore#push` / `#pop` / `#stack` / `#depth` and `TenantState#to_h`, all added unreleased in this cycle and never called. `with_tenant` restores from a local stack frame; routing it through the store would give one slot two writers and desync it the moment a switch committed or an unwind failed. Nesting depth is not observable, by design.

### Internal API notes
These are not part of the documented public surface, but they changed shape and are visible to anyone who reached for them:
- `RedisConnectionHandler#isolation_model` gained a fourth value, `:unknown`. Code matching on the previous three must handle it.
- `ConnectionManager.available_handlers` now returns handlers deduplicated by backend and ordered deterministically by backend key, rather than in `Class#subclasses` order.
- `Diagnostics::Cache` caches `level: :full` only.
- New instrumentation counters: `console_kit.handler_dropped`, `console_kit.handler_collision`.
- `TenantRollback#call` takes an optional second argument for backends that no longer have a live handler. `RollbackError#failures` entries may carry a Symbol backend key rather than a display-name String for those.

### Preserved
- The 1.3.0 Mongoid named-client fixes (`override_client` for named clients, `override_database` for database names, and clearing both on reset) are intact and covered by explicit regression tests.
- The 1.3.0 `base_class` memoization in the SQL handler is retained.

---

## [1.4.0] - 2026-06-24
- Minor Bug Fixes

---

## [1.3.0] - 2026-05-25
### Added
- **Mongoid Named Client Support:** `MongoConnectionHandler` now detects named Mongoid clients (configured in `mongoid.yml`) and calls `Mongoid.override_client` instead of `Mongoid.override_database`. This correctly handles multi-tenant setups where each tenant has a separate Mongoid client URI rather than a shared client with a different database name override.
- **Partner Identifier Case-Mismatch Warning:** When ConsoleKit writes a `partner_identifier` that differs from the existing context value only in case (e.g., app set `"DAHABDEV_SO"`, config has `"dahabdev_so"`), a warning is now printed so misconfigured tenant constants are immediately visible.
- **Mongoid Reset on Clear:** `TenantConfigurator.clear` now resets both `Mongoid.override_client` and `Mongoid.override_database` to nil, ensuring a clean state regardless of which override path was used.

### Fixed
- **Mongoid Wrong Database Bug:** Tenants using named Mongoid clients (separate URIs per tenant) were previously routed to a non-existent database because ConsoleKit called `Mongoid.override_database` with the client name instead of switching the client. Fixed by detecting named clients and using `Mongoid.override_client`.
- **Test Suite Stability:** Resolved 3 pre-existing failures in `tenant_orchestrator_spec.rb` caused by `auto_select?` returning true in non-TTY environments (CI/test), bypassing stubbed tenant selection. Fixed by stubbing `auto_select?` in affected examples.
- **Pending Tests Eliminated:** 12 pending tests in `output_spec.rb` caused by conditional `skip` in shared examples consolidated into a single unconditional assertion per example.

### Security
- **`safe_constantize` in Configuration:** `Configuration#resolve_context_class` now uses `safe_constantize` (returns nil on unknown constant) instead of `constantize` (raises on NameError), consistent with `SqlConnectionHandler`. Removes an inconsistency in constant resolution across the codebase.
- **Removed `Thread.kill` on Diagnostic Timeout:** Diagnostic threads that exceed the 2-second timeout are no longer forcibly killed via `Thread#kill`. Forcibly killing a thread mid-operation can leave database connections in a corrupt state. Timed-out threads now finish naturally while the main thread proceeds with a timeout diagnostic result.

### Performance
- **`base_class` Memoization in SQL Handler:** `SqlConnectionHandler#base_class` now memoizes the resolved constant with `@base_class ||=`, eliminating repeated `safe_constantize` calls across `connect`, `diagnostics`, and `disconnect_existing_pool` within the same handler instance.

---

## [1.2.0] - 2026-05-13
### Added
- **Connection Dashboard:** New `dashboard` console helper displaying a Unicode table with connection status, latency, and service-specific details (adapter, DB version, pool size, memory, cluster health) for all active handlers.
- **`show_dashboard` Config Option:** Opt-in auto-display of the dashboard on tenant switch (`config.show_dashboard = true`). Off by default to keep tenant switching fast.
- **Handler Diagnostics:** Each connection handler now exposes a `diagnostics` method with status, latency, and details.
- **Per-Handler Timeout:** Diagnostics calls are wrapped in a 2-second timeout to prevent slow services from blocking.
- **Rails 6.1+ Support:** Lowered minimum Rails version from 7.2.1 to 6.1, enabling use in older Rails applications.
- **Pry Prompt Fallback:** Graceful fallback for Pry versions < 0.13 that lack `Pry::Prompt.new`.
- **IRB Fallback:** Console helpers now work when `IRB::ExtendCommandBundle` is not available.
- **Multi-version CI:** Test matrix covering Rails 6.1, 7.0, 7.1, 7.2, and 8.0.

### Changed
- **Lightweight Dependencies:** Replaced full `rails` gem dependency with `railties`, `activerecord`, and `activesupport` only.
- **Smaller Gem Package:** Excluded `.md` files and `docs/` from the gem package.

---

## [1.1.0] - 2026-03-14
### Added
- **Redis Connection Handler:** Automatic Redis DB selection per tenant via `Redis.current.select`, with graceful fallback for Redis v5+ where `Redis.current` is deprecated.
- **Elasticsearch Connection Handler:** Sets a per-tenant Elasticsearch index name prefix via thread-local storage and `Elasticsearch::Model.index_name_prefix=` (when available).
- **Console Helpers:** New `switch_tenant`, `tenant_info`, and `tenants` methods available in the Rails console for quick tenant management.
- **Custom Console Prompt:** IRB and Pry prompts now display the active tenant name (e.g., `[acme] main:001>`).
- **Tenant Banner:** On successful tenant initialization, a banner now shows the tenant name, environment safety warnings (production in red, staging in yellow), and a summary of active connections.
- **Environment Safety Warnings:** Production and staging environments are flagged with color-coded warnings at tenant setup time.
- New tenant configuration keys: `redis_db`, `elasticsearch_prefix`, and `environment`.

### Changed
- `TenantConfigurator` now manages `tenant_redis_db` and `tenant_elasticsearch_prefix` context attributes alongside existing ones.
- Generator template updated with examples for the new configuration keys.

---

## [1.0.0] - 2026-03-01
### Added
- **Global Configuration Persistence:** ConsoleKit settings now persist across the entire session and across multiple threads.
- **Isolated Tenant Selection:** Each thread maintains its own tenant selection for safety, while sharing the global configuration.
- **Seamless Rails Reloading:** Full support for Rails `reload!`; your selected tenant and context are now automatically preserved after code reloads.
- **Reliable Tenant Switching:** Switching or clearing tenants now correctly resets all database connections (SQL and MongoDB) to their default state.
- **Flexible Tenant Selection:** Users can now select tenants by typing their names (case-insensitive) in addition to index numbers.
- **Session Control:** Added support for `exit` or `quit` commands directly at the selection prompt to terminate the console session.
- **Safe Mode:** Added a "Skip" option (0) to load the console without any tenant configuration.
- **Improved Configuration Validation:** Enhanced startup checks to provide clearer feedback if the configuration or context class is incorrectly defined.
- **Custom SQL Base Class:** New configuration option to specify a custom base class for SQL connections.

### Changed
- **Modernized CLI Interface:** Redesigned the tenant selection menu and prompts for a cleaner, more intuitive user experience.
- **Enhanced Error Feedback:** Improved messaging for invalid selections and missing configurations.
- **Optimized Performance:** Refactored internal discovery and configuration logic for better reliability in large applications.

### Fixed
- Fixed a bug where tenant context was lost after running `reload!` in the Rails console.
- Fixed an issue where database connections could remain tied to a previous tenant after the context was cleared.
- Resolved all stability and code quality warnings.
- Fixed timestamp formatting in console output.

---

## [0.1.5] - 2025-10-12
### Added
- Minor Bug Fixes

---

## [0.1.4] - 2025-09-30
### Added
- Minor Fixes and Improvements

---

## [0.1.3] - 2025-08-12
### Added
- `ConsoleKit.current_tenant` method to retrieve the current tenant at runtime.
- `ConsoleKit.reset_current_tenant` to reset tenant selection.
- `pretty_output` configuration added with ability to manually toggle CLI verbosity.

### Changed
- Refactored internal logic for improved maintainability and future extensibility.
- Enhanced test coverage for better reliability and edge case handling.

---

## [0.1.2] - 2025-07-23
### Added
- Changelog added.
- Readme and installation instructions added.

---

## [0.1.1] - 2025-07-21
### Added
- Initial generator: `console_kit:install` to scaffold configuration.
- RSpec test suite to support core features.

### Changed
- Applied RuboCop fixes for code consistency and style.

---

## [0.1.0] - 2025-07-09

- Initial release

### Added
- Core setup logic for ConsoleKit:
  - `ConsoleKit.setup`
  - Tenant selection via CLI.
  - Tenant-specific database configuration.
  - Colorized console output for improved UX.

[1.4.0]: https://github.com/Soumyadeep-ai/console_kit/releases/tag/v1.4.0
[1.3.0]: https://github.com/Soumyadeep-ai/console_kit/releases/tag/v1.3.0
[1.2.0]: https://github.com/Soumyadeep-ai/console_kit/releases/tag/v1.2.0
[1.1.0]: https://github.com/Soumyadeep-ai/console_kit/releases/tag/v1.1.0
[1.0.0]: https://github.com/Soumyadeep-ai/console_kit/releases/tag/v1.0.0
[0.1.5]: https://github.com/Soumyadeep-ai/console_kit/releases/tag/v0.1.5
[0.1.4]: https://github.com/Soumyadeep-ai/console_kit/releases/tag/v0.1.4
[0.1.3]: https://github.com/Soumyadeep-ai/console_kit/releases/tag/v0.1.3
[0.1.2]: https://github.com/Soumyadeep-ai/console_kit/releases/tag/v0.1.2
[0.1.1]: https://github.com/Soumyadeep-ai/console_kit/releases/tag/v0.1.1
[0.1.0]: https://github.com/Soumyadeep-ai/console_kit/releases/tag/v0.1.0
