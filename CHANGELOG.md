# Changelog

All notable changes to this project will be documented in this file.

This project adheres to [Semantic Versioning](https://semver.org/).

---

## [2.0.0] - 2026-05-27

### Added
- **Fiber-local context isolation** (`ConsoleKit::Context`) — stack-based tenant context using `Fiber.current` storage; safe for concurrent Rails requests and nested switching.
- **`ConsoleKit.with(:tenant)` block API** — scoped tenant switching that restores the previous tenant automatically, even on exception. Nestable.
- **`ConsoleKit::SwitchPipeline`** — self-registering step pipeline replaces `TenantOrchestrator`. Steps: EnvResolver → SafeguardCheck → TenantSelector → BeforeHooks → TenantConfigurator → ShardConnector → PromptApplier → AfterHooks.
- **Lifecycle hooks** — `config.before_switch` and `config.after_switch` with `on_error: :abort` (veto switch) or `on_error: :warn` (log and continue).
- **ENV override** — `CONSOLE_KIT_TENANT=tenant_one rails c` skips the interactive prompt.
- **Production safeguards** — configurable `production_environments`, `protected_tenants`, and `confirm_dangerous_context` prompt.
- **Rails-native sharding** — `config.use_rails_sharding = true` wraps `ActiveRecord::Base.connected_to` on each tenant switch (Rails 6.1+).
- **`ConsoleKit.status`** — runtime introspection: current tenant, configuration state, environment, shard.
- **`ConsoleKit::TenantResolver`** — convention-over-config: configure `tenants` as a `Hash` (default), `Array` (keys + resolver proc), or `:dynamic` (unbounded proc-based resolution).
- **`ConsoleKit::Benchmarker`** — opt-in per-step timing and memory delta reporting via `config.benchmark = true`.
- **Doctor system** — `rails console_kit:doctor` validates configuration with 8 health checks: tenants configured, keys unique, context class resolvable, required constants present, adapter supported, sharding compatible, hook arity valid, history path writable.
- **Fuzzy tenant selection** via `tty-prompt` with recent tenant memory (`config.recent_tenant_limit`).
- **IRB/Pry prompt** shows `[tenant][env]` after each switch.
- **`ConsoleKit::HookRegistry`** — programmatic hook registration with `hooks_for(event)` accessor.
- **`ConsoleKit::ScopedSwitcher`** — default and sharded variants for block-scoped switching.

### Changed
- **Architecture rewrite** — unified `ConsoleKit::Context` replaces scattered `Thread.current` calls. `SwitchPipeline` replaces `TenantOrchestrator`. All hardcoded values moved to `Configuration`.
- **Backward-compatible public API** — `ConsoleKit.current_tenant`, `ConsoleKit.tenants`, `ConsoleKit.context_class`, `ConsoleKit.reset_current_tenant`, `Setup`, `TenantOrchestrator`, `TenantConfigurator`, `TenantSelector` all preserved as shims.
- Version bumped to `2.0.0`.
- Ruby >= 3.1.0 required (no upper bound — forward-compatible via runtime fiber capability check).
- `tty-prompt ~> 0.23` moved to development dependency (optional at runtime).

### Fixed
- Double-push bug in scoped switcher — `TenantConfigurator` now skips `Context.push` when switcher already pushed the tenant.

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

[2.0.0]: https://github.com/Soumyadeep-ai/console_kit/releases/tag/v2.0.0
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
