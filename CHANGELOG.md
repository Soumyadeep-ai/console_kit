# Changelog

All notable changes to this project will be documented in this file.

This project adheres to [Semantic Versioning](https://semver.org/).

---

## [1.5.0] - 2026-09-23

Hardening release. Tenant switching is now transactional: a switch either
completes fully or leaves the previous tenant exactly as it was.

### Added
- **Atomic tenant switching.** `TenantSwitch` runs `validate -> snapshot -> prepare -> apply context -> connect -> verify -> commit`. The new tenant is not observable as current until the final commit, so a partially applied tenant state cannot survive a failure.
- **Rollback.** Any failure restores every touched component - the context attributes and all four backends - in the reverse of the order they were applied. Each component is attempted even when an earlier one fails, so one broken backend cannot strand the rest.
- **Connection identity verification.** A successful connection is no longer accepted as proof. SQL compares `current_shard` / `db_config.name`, Mongoid the effective client or database name, Redis the client's cached logical DB, Elasticsearch the effective index prefix. All are local reads with no network round trip; a mismatch raises `ConnectionVerificationError` and fails the switch.
- **Exception taxonomy.** `ConfigurationError`, `TenantNotFoundError`, `ConnectionError`, `ConnectionVerificationError`, `TenantSwitchError`, `RollbackError`, `UnsupportedBackendError`, all under `ConsoleKit::Error`. `TenantSwitchError` carries `#original_error`, `#rollback_failures` and `#rollback_succeeded?`, so a rollback failure never replaces the root cause.
- **`TenantState` and `StateStore`.** All per-thread tenant state lives in one thread-local holding one immutable value object, replacing five independent `Thread.current` keys.
- **`ConsoleKit.switch_tenant(:acme)`** - programmatic, raising counterpart to the interactive console flow.
- **`ConsoleKit.with_tenant(:acme) { ... }`** - nested, exception-safe tenant scope that restores the enclosing tenant on exit, including after an exception or a failed inner switch.
- **`ConsoleKit.verify_tenant!`** - re-verify that every available backend still points at the current tenant, and report any backend the switch could not drive.
- **Handlers declare their own backend.** `backend :key, display_name:, context_attribute:, constants_key:, detail_label:` plus `.target_error` as the single validation rule, called by both `prepare` and `validate!`. Adding a backend means adding one file; nothing outside a handler names a backend. Registration is explicit and keyed by backend, so two live reload generations of one backend cannot be represented.
- **Diagnostic levels.** `dashboard(level: :basic)` (the default) performs no network calls; `level: :full` keeps the version and health probes. Tenant switching triggers no diagnostics at all.
- **Diagnostic caching.** `:full` rows are cached per thread for a couple of seconds. A row is reused only while the TTL holds, the calling thread is on the same tenant state, and the backend still reports the same observed identity - so another thread moving a process-global backend drops the row rather than serving it stale. `:error` rows are never cached.
- **Instrumentation hook.** `ConsoleKit::Instrumentation.subscribe { |name, duration_ms, payload| ... }` plus counters for switches, verifications, rollbacks, dropped handlers and diagnostic timeouts. No external dependency.
- **Strict configuration validation.** `ConsoleKit.configuration.validate!` reports every problem in one pass: tenant structure, identifiers, duplicates colliding by case or type, required constants, Redis DB numbers, Elasticsearch prefixes, shard and Mongoid client names. Unrecognised keys and a `context_class` missing writers are reported as warnings.
- **Isolation reporting.** `RedisConnectionHandler#isolation_model` / `#thread_isolated?` and the Elasticsearch equivalents report at runtime whether a backend is genuinely per-thread or process-global.

- **`BaseConnectionHandler#unavailable_reason`.** A handler that exists but cannot be driven returns a reason instead of merely answering `available? => false`, and is recorded as a dropped backend rather than skipped like an optional gem that is not installed.
- **Uneven backend coverage is reported.** `validate!` warns when tenants disagree about which backend keys they name, stating that switching to a tenant which omits one resets that backend.

### Changed
- **Connection pool churn removed.** The SQL handler uses the native `connecting_to(shard:)` path when the target is a registered shard, detected by capability check rather than Rails version, and keeps ConsoleKit to exactly one entry on the `connected_to` stack. The `establish_connection` fallback re-establishes only when the resolved configuration actually changes, and no longer disconnects a pool Rails is about to replace anyway. Switching to the shard already in use performs no pool work.
- **`TenantOrchestrator.reapply`** (and the deprecated `Setup.reapply`) no longer re-establishes a connection already on the target shard.
- Diagnostics run in the calling thread. A backend's tenant lives in thread-local state, so a check run anywhere else inspects a different tenant than the caller is on.
- `ContextWrapper#assign` returns a Hash of applied values rather than triples, and owns the case-mismatch warning. It gained `current_values` and `restore`.
- `TenantConfigurator.validate_constants!` moved to `ConsoleKit::TenantPlan`. `configuration_success` is derived from `StateStore` and joined by a `configuration_success?` predicate.
- An unknown tenant key raises `TenantNotFoundError` naming the configured tenant keys, or saying that none are configured.
- A successful console switch prints one success line, `Tenant initialized: <key>`, instead of two near-identical ones.

### Deprecated
Still working, each warning once per process; all are removed in 2.0.
- `ConsoleKit::Setup.setup` -> `ConsoleKit::TenantOrchestrator.run`
- `ConsoleKit::Setup.current_tenant` -> `ConsoleKit.current_tenant`
- `ConsoleKit::Setup.current_tenant=` -> `ConsoleKit.switch_tenant`, which also switches the connections
- `ConsoleKit::Setup.tenant_setup_successful?` -> `ConsoleKit.current_tenant`
- `ConsoleKit::Setup.reapply` -> `ConsoleKit::TenantOrchestrator.reapply`
- `ConsoleKit::Setup.reset_current_tenant` -> `ConsoleKit.reset_current_tenant`
- `ConsoleKit::Setup.auto_select?` -> `ConsoleKit::TenantOrchestrator.auto_select?`
- `ConsoleKit.pretty_output` / `pretty_output=` -> `ConsoleKit.configuration.pretty_output` / `pretty_output=`
- `ConsoleKit.tenants=` -> `ConsoleKit.configuration.tenants=`
- `ConsoleKit.context_class` / `context_class=` -> `ConsoleKit.configuration.context_class` / `context_class=`
- `ConsoleKit.show_dashboard` / `show_dashboard=` -> `ConsoleKit.configuration.show_dashboard` / `show_dashboard=`
- `ConsoleKit::Configuration#validate` -> `#validate!`, which raises instead of returning `false`

### Fixed
- **Diagnostic threads leaked without bound.** Every diagnostic call spawned a thread, and a timed-out one was abandoned - deliberately, since 1.3.0 removed `Thread.kill` to avoid corrupting a connection mid-operation - so each dashboard render could leak another. Diagnostics no longer spawn threads at all, so there is nothing left to leak or to kill.
- **A failed Mongoid, Redis or Elasticsearch switch reported success.** Each handler rescued `NoMethodError` and printed a warning while the caller carried on, so a tenant switch that had not actually happened looked like one that had. Failures now propagate and roll back, and a client that genuinely cannot support the request is refused before anything is mutated.
- **Elasticsearch `:full` diagnostics reported `Connected` for an unreachable cluster.** The ping failure was swallowed and `cluster.health` was called anyway.
- **A misconfigured `sql_base_class` silently removed SQL from every switch.** An unresolvable class name made `available?` return false, which is indistinguishable from ActiveRecord not being loaded, so SQL was never switched while the switch reported success. A non-default class name that cannot be resolved now warns.
- **The gem did not require the ActiveSupport core extensions it uses.** `Object#try` and `Time.current` are called on ordinary paths but were only available if the host application had already loaded more of Rails.
- **Errors printed to the console were not scrubbed.** A tenant constant can carry a connection URI, so an authentication failure could put a plaintext password into the console and the logs.

- **The prompt named the wrong tenant after a switch.** The tenant label was baked into the prompt when it was installed, so `switch_tenant` - and choosing no tenant - left the prompt naming the tenant the console started on, while `tenant_info` reported the real one. Under IRB the label never appeared at all without Pry, because Rails' `IRB.setup` resets `IRB.conf` after the railtie installs it. The label is now computed each time the prompt is drawn, under both IRB and Pry, so it always names the current tenant and survives whatever Rails does to `IRB.conf`. Rails' own prompt and environment colouring are kept, and a `%` in a tenant name is escaped rather than read by IRB as a format directive.
- **An interactive switch was not atomic.** `switch_tenant` from the console cleared the current tenant before switching, so a switch that failed left the console on no tenant at all rather than the one it was on, and every switch printed three lines of reset noise and reset SQL once for nothing. It now switches directly, so a failure rolls back to the previous tenant; clearing happens only when you choose no tenant.
- **The banner listed backends as `Sql, Mongo`** rather than the names the handlers give themselves.

- **Tenant state was fiber-local while the ActiveRecord shard frame was thread-local.** `Thread.current[]` is fiber-scoped in Ruby, so a second Fiber or an Enumerator on the same thread saw an empty `TenantState` while sharing that thread's SQL and context state, and the diagnostics cache could serve a `:full` row cached against a different tenant. Both now use the same thread-level primitive the shard frame uses.
- **The undo bundle was only shallow-frozen**, so a caller could edit a handler snapshot after commit and make a later rollback restore altered state.
- **Rollback resolved the context class when it ran** rather than retaining the object the switch moved, so replacing or reloading `context_class` inside an open `with_tenant` scope wrote the saved values to the new object and left the original on the inner tenant.
- **A configured but unresolvable `sql_base_class` was indistinguishable from an optional gem that is not loaded.** SQL was dropped from the switch with no record, so the other backends committed while the SQL pool stayed on the previous tenant and `verify_tenant!` reported it fully verified.
- **A fallback SQL rollback could not restore "there was no pool".** A base class with no pool before the switch was left holding the tenant pool the failed switch established.
- **Two handlers could claim one context attribute**, so the context said one thing while the live connection said another. A collision now raises at declaration.
- **A malformed tenant entry raised `NoMethodError` or `TypeError`** from outside the transactional error boundary instead of `ConfigurationError`.

### Security
- **Credentials are scrubbed** from error messages, diagnostic rows and console output: connection URIs, `key=value` and `key => value` fragments, `Authorization: Bearer <token>` style auth headers, bare `password <value>` phrases and `for user <name>` principals. Hostnames and ports are deliberately kept - they are not secrets, and removing them would gut the diagnostic value of a connection error. Treat this as defence in depth, not a boundary: it is shape-matching over strings ConsoleKit did not produce.
- **Elasticsearch cross-thread prefix conflicts are detected.** `Elasticsearch::Model.index_name_prefix` is process-wide; when live threads hold different prefixes ConsoleKit warns once, naming both, instead of silently letting one thread read another tenant's indices.
- Broad `rescue StandardError` blocks were narrowed. Programming errors (`NoMethodError`, `NameError`, `ArgumentError`, `TypeError`) are no longer converted into ordinary "dependency unavailable" results.

### Performance
Measured, not asserted. `bundle exec rake benchmark` runs entirely against fakes, so it needs no database, Redis, Mongo or Elasticsearch. Counts are facts; timings are indicative.

- **Connection pool churn, per switch:**

  | Path | Pools replaced |
  |------|----------------|
  | native shard - same, different, or reset | 0 |
  | fallback - same shard | 0 |
  | fallback - different shard or reset | 1 |

  Before 1.5.0 every switch performed one `disconnect!` plus one `establish_connection` unconditionally, including a switch to the shard already in use.
- **Queries and health probes per tenant switch: 0**, including verification. The only round trip a switch makes is the one that moves the tenant, such as a Redis `SELECT`. Asserted, not just measured: every handler runs this check in the shared contract, `spec/support/shared_examples/connection_handler_contract.rb`. `dashboard(level: :basic)` performs 0 cold and cached; `level: :full` performs 8 cold and 0 within the cache window.
- **Allocations per switch:** 195 objects alternating between two tenants, 192 repeating the same tenant.
- The ActiveRecord `connected_to` stack holds exactly one ConsoleKit entry regardless of switch count or `reload!` count.
- The 1.3.0 `base_class` memoization is retained.

- **`level: :full` diagnostics no longer time out.** They previously ran on a thread ConsoleKit could abandon after two seconds. That thread could not see the caller's tenant - a backend's tenant lives in thread-local state - so it inspected a different tenant than the one being reported on, and could check out a second pool connection doing it. Reporting the wrong tenant is worse than reporting slowly, so the check now runs in the calling thread. A backend that hangs holds the dashboard until its own client gives up; `Ctrl-C` interrupts it, `:full` is never the default, and `timeout:` now counts overruns rather than cutting them off. Configure a timeout on the client to bound it - that is the only layer that can cancel its own call safely.

### Breaking changes
- **redis-rb 5 and redis-client:** these expose no process-wide client handle, so a non-default `redis_db` now raises `UnsupportedBackendError` instead of printing a warning and silently running against the wrong DB. Give each tenant its own Redis URL, for example `redis://redis.internal:6379/<db>`.
- **Elasticsearch prefixes** must be Strings or Symbols, and may not contain uppercase characters, whitespace, a leading `_`, `-` or `+`, or any of `\ / * ? " < > | , #`. Previously such values were passed through and produced unusable index names.
- **Blank tenant constants are rejected.** `shard: ''`, `mongo_db: ''` and `redis_db: ''` now raise `ConfigurationError` at both `validate!` and switch time, rather than silently meaning "use the default".
- **Incomplete tenant entries now fail `validate!`.** A tenant with no `:constants`, or missing `shard` / `partner_code`, previously validated as fine and only broke at switch time.
- **A failed backend switch now raises rather than warning.** `ConsoleKit.switch_tenant` raises; the interactive console flow still reports through `Output` and returns `false`. Failures found before anything is applied - an unknown tenant, malformed constants, an unsupported client - raise `TenantNotFoundError`, `ConfigurationError` or `UnsupportedBackendError` directly, since there is nothing to roll back.
- **A Mongoid whose overrides cannot be read back** is refused at `prepare`. Such a switch could not be verified, and its rollback would have cleared the override rather than restoring it.

### Internal API notes
Not part of the documented public surface, but visible to anyone who reached for them:
- `TenantConfigurator::CONTEXT_MAPPING` and `ContextWrapper::HANDLER_ATTRIBUTES` are gone; backends declare their own mapping.
- `BaseConnectionHandler` gained `.backend`, `#diagnostic_identity`, and a keyed `HandlerRegistry` in place of `Class#descendants`.
- `ConnectionManager.available_handlers` takes an optional collector for backends it had to drop, and returns handlers in declaration order.
- `RedisConnectionHandler#isolation_model` can return `:unknown` when the probe could not observe the client.
- New instrumentation counters: `console_kit.handler_dropped`, `console_kit.handler_collision`, `console_kit.incomplete_verification`, `console_kit.sql_frame_reasserted`.

### Compatibility
- CI covers **every Ruby × Rails combination the gemspec permits** - 28 cells, all of them gating. `railties` declares `>= 2.5` (6.1), `>= 2.7` (7.0, 7.1), `>= 3.1` (7.2) and `>= 3.2` (8.0, 8.1), none of them declare an upper bound, and this gem requires Ruby `>= 3.1`.

  | Rails | Ruby |
  |---|---|
  | 6.1 | 3.1, 3.2, 3.3, 3.4, 4.0 |
  | 7.0 | 3.1, 3.2, 3.3, 3.4, 4.0 |
  | 7.1 | 3.1, 3.2, 3.3, 3.4, 4.0 |
  | 7.2 | 3.1, 3.2, 3.3, 3.4, 4.0 |
  | 8.0 | 3.2, 3.3, 3.4, 4.0 |
  | 8.1 | 3.2, 3.3, 3.4, 4.0 |

- **Rails 8.1 and Ruby 4.0 are covered.** Rails 8.1 is what the default lockfile resolves to, so the suite had been running against it without saying so. Ruby 4.0 has been the current stable release since July 2026.
- `required_ruby_version` remains `>= 3.1.0` and the Rails dependencies remain `>= 6.1`, both without an upper bound.

### Preserved
- The 1.3.0 Mongoid named-client fixes - `override_client` for named clients, `override_database` for database names, and clearing both on reset - are intact and covered by explicit regression tests.

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
